#!/usr/bin/env bash
# Поиск: файлы подтверждения Вебмастера и Search Console, IndexNow и переадресации /go/<игра>
# (поручение 06; README, «Поиск: Вебмастер, Search Console, IndexNow»).
#
# Запускает автообновление сайта (deploy/update-site.sh) в каждом проходе — раз в 5 минут; вручную —
# от root:  bash /opt/gornitsa/deploy/seo/apply.sh
# Скрипт можно запускать сколько угодно раз: он доводит настройку и ничего не ломает.
#
# Что делает:
#   1. Файлы подтверждения из /etc/gornitsa-site/verification/ (кладёт владелец, в репозитории их нет):
#      yandex_<код>.html, google<код>.html — копирует в корень сайта. После каждой выкладки rsync
#      их стирает, а этот скрипт в том же проходе возвращает.
#   2. Ключ IndexNow: /etc/gornitsa-site/indexnow.key (нет — создаёт сам), файл ключа <ключ>.txt —
#      в корень сайта.
#   3. Переадресации /go/<игра> → RuStore: build/go.conf (собирает build.py) —
#      в /etc/nginx/snippets/gornitsa.games-go.conf; не прошёл nginx -t — возвращается прежний.
#   4. IndexNow: адреса из sitemap.xml, чьи страницы изменились с прошлой отправки, —
#      в yandex.com/indexnow (deploy/seo/indexnow.py). Отключить: touch /etc/gornitsa-site/indexnow-off.

set -euo pipefail

DIR="${DIR:-/opt/gornitsa}"
DOMAIN="${DOMAIN:-gornitsa.games}"
WEBROOT="/var/www/${DOMAIN}"
ETC=/etc/gornitsa-site
STATE=/var/lib/gornitsa-site
SITE_CONF=/etc/nginx/sites-available/${DOMAIN}.conf
SNIPPET=/etc/nginx/snippets/${DOMAIN}-go.conf
INCLUDE="include /etc/nginx/snippets/${DOMAIN}-*.conf;"

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: bash $0" >&2
  exit 1
fi
[[ -d "${WEBROOT}" ]] || { echo "seo: нет ${WEBROOT} — сайт ещё не выложен" >&2; exit 0; }

install -d -m 755 "${ETC}" "${ETC}/verification"
install -d -m 750 "${STATE}"

# 1. Файлы подтверждения. Только известные имена: в корень сайта не попадёт ничего постороннего.
shopt -s nullglob
for f in "${ETC}/verification/"*; do
  name="$(basename "$f")"
  if [[ ! "$name" =~ ^(yandex_[0-9a-f]{8,32}\.html|google[0-9a-f]{8,32}\.html)$ ]]; then
    echo "seo: ${f} — не файл подтверждения (yandex_<код>.html или google<код>.html), пропускаю" >&2
    continue
  fi
  if ! cmp -s "$f" "${WEBROOT}/${name}"; then
    install -m 644 "$f" "${WEBROOT}/${name}"
    echo "seo: файл подтверждения ${name} — в корне сайта"
  fi
done
shopt -u nullglob

# 2. Ключ IndexNow: 32 шестнадцатеричных знака. Это не секрет — он и так лежит открытым файлом
#    в корне сайта, — но в репозиторий его не кладём, как и коды подтверждения.
if [[ ! -s "${ETC}/indexnow.key" ]]; then
  python3 -c 'import secrets; print(secrets.token_hex(16))' > "${ETC}/indexnow.key"
  chmod 644 "${ETC}/indexnow.key"
  echo "seo: создан ключ IndexNow ${ETC}/indexnow.key"
fi
KEY="$(tr -d '[:space:]' < "${ETC}/indexnow.key")"
if [[ ! "${KEY}" =~ ^[A-Za-z0-9-]{8,128}$ ]]; then
  echo "seo: ключ IndexNow в ${ETC}/indexnow.key — 8–128 знаков: латиница, цифры, дефис" >&2
  KEY=""
fi
if [[ -n "${KEY}" && "$(cat "${WEBROOT}/${KEY}.txt" 2>/dev/null || true)" != "${KEY}" ]]; then
  printf '%s' "${KEY}" > "${WEBROOT}/${KEY}.txt"
  chmod 644 "${WEBROOT}/${KEY}.txt"
fi

# 3. /go/<игра>: сниппет nginx. Нужна строка include в конфиге сайта (deploy/nginx/*.conf).
GO_SRC="${DIR}/build/go.conf"
if [[ -s "${GO_SRC}" && -f "${SITE_CONF}" ]] && grep -qF "${INCLUDE}" "${SITE_CONF}" && ! cmp -s "${GO_SRC}" "${SNIPPET}"; then
  BACKUP=""
  if [[ -f "${SNIPPET}" ]]; then BACKUP="$(mktemp)"; cp "${SNIPPET}" "${BACKUP}"; fi
  install -m 644 "${GO_SRC}" "${SNIPPET}"
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx
    echo "seo: переадресации /go/ обновлены"
  else
    if [[ -n "${BACKUP}" ]]; then install -m 644 "${BACKUP}" "${SNIPPET}"; else rm -f "${SNIPPET}"; fi
    echo "seo: новые переадресации /go/ не прошли nginx -t — оставлены прежние" >&2
    nginx -t || true
  fi
  if [[ -n "${BACKUP}" ]]; then rm -f "${BACKUP}"; fi
fi

# 4. IndexNow — только когда HTTPS уже есть: поисковик проверяет ключ по https://<домен>/<ключ>.txt.
if [[ -n "${KEY}" && -d "/etc/letsencrypt/live/${DOMAIN}" && ! -e "${ETC}/indexnow-off" ]]; then
  python3 "${DIR}/deploy/seo/indexnow.py" --webroot "${WEBROOT}" --host "${DOMAIN}" --key "${KEY}" \
    --state "${STATE}/indexnow.json" || echo "seo: IndexNow не ответил — повторю через 5 минут" >&2
fi
