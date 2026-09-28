#!/usr/bin/env bash
# Автообновление сайта: забирает свежий main из GitHub и выкладывает site/ в папку nginx.
# Запускается systemd-таймером gornitsa-update.timer (см. deploy/bootstrap.sh).
# Если HTTPS ещё не включён, а DNS уже указывает на сервер, выпускает сертификат Let's Encrypt.
# Когда в репозитории меняется deploy/votchina/, deploy/nardy/ или deploy/skazy/, доводит настройку
# сервера игры «Вотчина» (deploy/votchina/setup.sh), «Длинные нарды» (deploy/nardy/setup.sh) или
# заставы «Сказов» (deploy/skazy/setup.sh).
# Сам этот скрипт тоже обновляется из репозитория.

set -euo pipefail

DIR="/opt/gornitsa"
BRANCH="${BRANCH:-main}"
DOMAIN="${DOMAIN:-gornitsa.games}"
EMAIL="${EMAIL:-dev@gornitsa.games}"   # почта аккаунта Let's Encrypt — ящик разработчика студии
WEBROOT="/var/www/${DOMAIN}"
STAMP="/var/lib/gornitsa-deployed-commit"
VOTCHINA_STAMP="/var/lib/gornitsa-votchina-setup"
NARDY_STAMP="/var/lib/gornitsa-nardy-setup"
SKAZY_STAMP="/var/lib/gornitsa-skazy-setup"
LE_STAMP="/var/lib/gornitsa-le-email"
SELF="/usr/local/bin/gornitsa-update"

git -C "${DIR}" fetch -q origin "${BRANCH}"
REMOTE="$(git -C "${DIR}" rev-parse "origin/${BRANCH}")"
DEPLOYED="$(cat "${STAMP}" 2>/dev/null || true)"

if [[ "${REMOTE}" != "${DEPLOYED}" ]]; then
  git -C "${DIR}" reset -q --hard "origin/${BRANCH}"
  bash "${DIR}/deploy/fetch-fonts.sh"
  python3 "${DIR}/build.py" >/dev/null
  rsync -a --delete --chmod=D755,F644 "${DIR}/site/" "${WEBROOT}/"
  chown -R deploy:www-data "${WEBROOT}" 2>/dev/null || true
  echo "${REMOTE}" > "${STAMP}"
  echo "Выложена версия ${REMOTE:0:7}"
fi

# Сервер «Вотчины»: настройка машины — при каждом изменении deploy/votchina/ в репозитории.
VOTCHINA_TREE="$(git -C "${DIR}" rev-parse -q --verify "HEAD:deploy/votchina" 2>/dev/null || true)"
if [[ -n "${VOTCHINA_TREE}" && "${VOTCHINA_TREE}" != "$(cat "${VOTCHINA_STAMP}" 2>/dev/null || true)" ]]; then
  if bash "${DIR}/deploy/votchina/setup.sh"; then
    echo "${VOTCHINA_TREE}" > "${VOTCHINA_STAMP}"
  else
    echo "Настройка сервера «Вотчины» не удалась — повторю через 5 минут" >&2
  fi
fi

# Сервер «Длинных нард» — так же, при каждом изменении deploy/nardy/.
NARDY_TREE="$(git -C "${DIR}" rev-parse -q --verify "HEAD:deploy/nardy" 2>/dev/null || true)"
if [[ -n "${NARDY_TREE}" && "${NARDY_TREE}" != "$(cat "${NARDY_STAMP}" 2>/dev/null || true)" ]]; then
  if bash "${DIR}/deploy/nardy/setup.sh"; then
    echo "${NARDY_TREE}" > "${NARDY_STAMP}"
  else
    echo "Настройка сервера нард не удалась — повторю через 5 минут" >&2
  fi
fi

# Сервер заставы «Сказов» — так же, при каждом изменении deploy/skazy/.
SKAZY_TREE="$(git -C "${DIR}" rev-parse -q --verify "HEAD:deploy/skazy" 2>/dev/null || true)"
if [[ -n "${SKAZY_TREE}" && "${SKAZY_TREE}" != "$(cat "${SKAZY_STAMP}" 2>/dev/null || true)" ]]; then
  if bash "${DIR}/deploy/skazy/setup.sh"; then
    echo "${SKAZY_TREE}" > "${SKAZY_STAMP}"
  else
    echo "Настройка сервера «Сказов» не удалась — повторю через 5 минут" >&2
  fi
fi

if [[ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
  SERVER_IP="$(curl -4 -fsS --max-time 10 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
  APEX_IP="$(getent ahostsv4 "${DOMAIN}" | awk 'NR==1{print $1}' || true)"
  WWW_IP="$(getent ahostsv4 "www.${DOMAIN}" | awk 'NR==1{print $1}' || true)"
  if [[ -n "${SERVER_IP}" && "${APEX_IP}" == "${SERVER_IP}" && "${WWW_IP}" == "${SERVER_IP}" ]]; then
    certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" -m "${EMAIL}" --agree-tos -n --redirect
    systemctl reload nginx
    echo "HTTPS включён для ${DOMAIN}"
  fi
fi

# Почта аккаунта Let's Encrypt — одного на все сертификаты машины. Меняется один раз после смены
# адреса (раньше был Gmail студии); следующий запуск по отметке в LE_STAMP ничего не делает.
if [[ -d /etc/letsencrypt/accounts && "$(cat "${LE_STAMP}" 2>/dev/null || true)" != "${EMAIL}" ]]; then
  if certbot update_account -m "${EMAIL}" --no-eff-email -n >/dev/null 2>&1; then
    echo "${EMAIL}" > "${LE_STAMP}"
    echo "Почта аккаунта Let's Encrypt: ${EMAIL}"
  else
    echo "Не удалось сменить почту аккаунта Let's Encrypt — повторю через 5 минут" >&2
  fi
fi

# Установленная копия этого скрипта — из репозитория (следующий запуск возьмёт свежую).
if [[ -f "${SELF}" ]] && ! cmp -s "${DIR}/deploy/update-site.sh" "${SELF}"; then
  install -m 755 "${DIR}/deploy/update-site.sh" "${SELF}"
  echo "Скрипт автообновления обновлён"
fi
