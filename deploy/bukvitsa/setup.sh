#!/usr/bin/env bash
# Закрытая веб-версия «Буквицы» на этой машине: https://gornitsa.games/bukvitsa/test/
# (docs/02-architecture.md, «Веб-сборка», и ADR 0007 в репозитории Nefeste/bukvitsa). Как у «Узоров»
# (deploy/uzory/): только для владельца и тех, кому он даст пароль; в сборке — задачи-черновики, ещё не
# сверенные со сканом, поэтому сборка лежит в открытой ветке vps только зашифрованной.
#
# Запускает автообновление сайта (deploy/update-site.sh), когда эта папка меняется в репозитории;
# вручную — от root:  bash /opt/gornitsa/deploy/bukvitsa/setup.sh
# Скрипт можно запускать сколько угодно раз: он доводит настройку и ничего не ломает.
# Службы нет: это статические файлы, их отдаёт nginx сайта.
#
# Что настраивает:
#   - папки: сборки /opt/bukvitsa, состояние /var/lib/bukvitsa-deploy, пароли и ключ /etc/bukvitsa;
#   - ключ шифрования машины (age): открытая часть — https://gornitsa.games/.well-known/bukvitsa-age.pub,
#     ею CI «Буквицы» (site.yml) шифрует сборку в ветке vps; закрытая (/etc/bukvitsa/age.key) не покидает машину;
#   - bukvitsa-pull каждые 5 минут: новая сборка из ветки vps → /opt/bukvitsa/releases/<коммит>, ссылка current;
#   - bukvitsa-nginx: /bukvitsa/test/ в nginx сайта — только HTTPS и только с паролем; пока пароля нет — 403;
#   - bukvitsa-password: имя и пароль задаёт владелец — sudo bukvitsa-password.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETC=/etc/bukvitsa
META=/var/www/bukvitsa-meta

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: bash $0" >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -q -y -o DPkg::Lock::Timeout=300)

echo "==> Буквица: пакеты"
need=()
for p in git age openssl gzip; do command -v "$p" >/dev/null || need+=("$p"); done
if (( ${#need[@]} )); then
  "${APT[@]}" update
  "${APT[@]}" install "${need[@]}"
fi

echo "==> Буквица: папки"
install -d -m 755 /opt/bukvitsa /opt/bukvitsa/releases "$META"
install -d -m 700 /var/lib/bukvitsa-deploy
install -d -m 750 -o root -g www-data "$ETC"

echo "==> Буквица: ключ шифрования сборки"
if [[ ! -f "$ETC/age.key" ]]; then
  (umask 077 && age-keygen -o "$ETC/age.key" 2>/dev/null)
fi
chmod 600 "$ETC/age.key"
age-keygen -y "$ETC/age.key" > "$META/bukvitsa-age.pub"
chmod 644 "$META/bukvitsa-age.pub"

echo "==> Буквица: скрипты и таймер"
install -m 755 "$SRC/pull.sh" /usr/local/sbin/bukvitsa-pull
install -m 755 "$SRC/nginx.sh" /usr/local/sbin/bukvitsa-nginx
install -m 755 "$SRC/password.sh" /usr/local/sbin/bukvitsa-password

write_unit() {   # пишет файл службы, только если он изменился
  local f="/etc/systemd/system/$1" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$f" ]] && cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  install -m 644 "$tmp" "$f"
  rm -f "$tmp"
}

write_unit bukvitsa-pull.service <<'UNIT'
[Unit]
Description=Буквица: веб-версия из ветки vps
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/bukvitsa-pull
UNIT

write_unit bukvitsa-pull.timer <<'UNIT'
[Unit]
Description=Буквица: проверять веб-сборку каждые 5 минут

[Timer]
OnBootSec=3min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
UNIT

echo "==> Буквица: nginx"
/usr/local/sbin/bukvitsa-nginx

systemctl daemon-reload
systemctl enable --now bukvitsa-pull.timer >/dev/null 2>&1

echo
echo "Буквица: машина настроена."
echo "  - ключ для CI: https://gornitsa.games/.well-known/bukvitsa-age.pub"
echo "    $(cat "$META/bukvitsa-age.pub")"
if [[ -s "$ETC/test.htpasswd" ]]; then
  echo "  - пароль задан; сменить или добавить вход — sudo bukvitsa-password"
else
  echo "  - пароля ещё нет, страница закрыта для всех; задать — sudo bukvitsa-password"
fi
echo "  - сборка появится в ветке vps после запуска «Веб-версия для сайта» (site.yml) в Nefeste/bukvitsa."
echo "Журнал: journalctl -u bukvitsa-pull -n 50"
