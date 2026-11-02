#!/usr/bin/env bash
# Закрытая веб-версия «Узоров» на этой машине: https://gornitsa.games/uzory/test/
# (спецификация docs/specs/2026-09-web.md в репозитории Nefeste/uzory). Решение владельца
# от 28.09.2026: сначала — только для владельца, все картинки сборки, под паролем.
#
# Запускает автообновление сайта (deploy/update-site.sh), когда эта папка меняется в репозитории;
# вручную — от root:  bash /opt/gornitsa/deploy/uzory/setup.sh
# Скрипт можно запускать сколько угодно раз: он доводит настройку и ничего не ломает.
# Службы нет: это статические файлы, их отдаёт nginx сайта.
#
# Что настраивает:
#   - папки: сборки /opt/uzory, состояние /var/lib/uzory-deploy, пароли и ключ /etc/uzory;
#   - ключ шифрования машины (age): открытая часть — https://gornitsa.games/.well-known/uzory-age.pub,
#     ею CI «Узоров» шифрует сборку в открытой ветке vps; закрытая (/etc/uzory/age.key) не покидает
#     машину;
#   - uzory-pull каждые 5 минут: новая сборка из ветки vps → /opt/uzory/releases/<коммит>, ссылка current;
#   - uzory-nginx: /uzory/test/ в nginx сайта — только HTTPS и только с паролем; пока пароля нет — 403;
#   - uzory-password: имя и пароль задаёт владелец — sudo uzory-password;
#   - uzory-packs каждые 5 минут: новые картинки по сети из ветки packs «Узоров» — сверка подписи каталога
#     ключом из catalog.pub и SHA-256 наборов, потом /srv/gornitsa/uzory/v1/ (сначала наборы, потом подпись
#     и каталог); их отдаёт uzory-nginx по /uzory/v1/. Входа на машину у CI «Узоров» нет;
#   - uzory-stats раз в сутки: свёртка журнала каталога без адресов в счётчики (нужен bun «Нард»).

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETC=/etc/uzory
META=/var/www/uzory-meta

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: bash $0" >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -q -y -o DPkg::Lock::Timeout=300)

echo "==> Узоры: пакеты"
need=()
for p in git age openssl gzip; do command -v "$p" >/dev/null || need+=("$p"); done
if (( ${#need[@]} )); then
  "${APT[@]}" update
  "${APT[@]}" install "${need[@]}"
fi

echo "==> Узоры: папки"
install -d -m 755 /opt/uzory /opt/uzory/releases "$META"
install -d -m 700 /var/lib/uzory-deploy
install -d -m 750 -o root -g www-data "$ETC"
install -d -m 755 /srv/gornitsa /srv/gornitsa/uzory /srv/gornitsa/uzory/v1 /srv/gornitsa/uzory/v1/packs /srv/gornitsa/uzory/stats
install -d -m 755 /var/lib/uzory-packs /var/log/uzory
install -m 644 "$SRC/catalog.pub" "$ETC/catalog.pub"

echo "==> Узоры: ключ шифрования сборки"
if [[ ! -f "$ETC/age.key" ]]; then
  (umask 077 && age-keygen -o "$ETC/age.key" 2>/dev/null)
fi
chmod 600 "$ETC/age.key"
age-keygen -y "$ETC/age.key" > "$META/uzory-age.pub"
chmod 644 "$META/uzory-age.pub"

echo "==> Узоры: скрипты и таймер"
install -m 755 "$SRC/pull.sh" /usr/local/sbin/uzory-pull
install -m 755 "$SRC/nginx.sh" /usr/local/sbin/uzory-nginx
install -m 755 "$SRC/password.sh" /usr/local/sbin/uzory-password
install -m 755 "$SRC/packs.sh" /usr/local/sbin/uzory-packs
install -m 755 "$SRC/stats.sh" /usr/local/sbin/uzory-stats

write_unit() {   # пишет файл службы, только если он изменился
  local f="/etc/systemd/system/$1" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$f" ]] && cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  install -m 644 "$tmp" "$f"
  rm -f "$tmp"
}

write_unit uzory-pull.service <<'UNIT'
[Unit]
Description=Узоры: веб-версия из ветки vps
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/uzory-pull
UNIT

write_unit uzory-pull.timer <<'UNIT'
[Unit]
Description=Узоры: проверять веб-сборку каждые 5 минут

[Timer]
OnBootSec=3min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
UNIT

write_unit uzory-packs.service <<'UNIT'
[Unit]
Description=Узоры: новые картинки по сети из ветки packs
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/uzory-packs
UNIT

write_unit uzory-packs.timer <<'UNIT'
[Unit]
Description=Узоры: проверять ветку packs каждые 5 минут

[Timer]
OnBootSec=4min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
UNIT

write_unit uzory-stats.service <<'UNIT'
[Unit]
Description=Узоры: свёртка журнала каталога в счётчики

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/uzory-stats
UNIT

write_unit uzory-stats.timer <<'UNIT'
[Unit]
Description=Узоры: свёртка счётчиков раз в сутки

[Timer]
OnCalendar=*-*-* 00:20:00 Europe/Moscow
Persistent=true

[Install]
WantedBy=timers.target
UNIT

echo "==> Узоры: nginx"
/usr/local/sbin/uzory-nginx

systemctl daemon-reload
systemctl enable --now uzory-pull.timer >/dev/null 2>&1
systemctl enable --now uzory-packs.timer >/dev/null 2>&1
systemctl enable --now uzory-stats.timer >/dev/null 2>&1

echo
echo "Узоры: машина настроена."
echo "  - ключ для CI: https://gornitsa.games/.well-known/uzory-age.pub"
echo "    $(cat "$META/uzory-age.pub")"
if [[ -s "$ETC/test.htpasswd" ]]; then
  echo "  - пароль задан; сменить или добавить вход — sudo uzory-password"
else
  echo "  - пароля ещё нет, страница закрыта для всех; задать — sudo uzory-password"
fi
echo "  - сборка появится в ветке vps после слияния в main «Узоров»."
echo "  - новые картинки по сети — из ветки packs «Узоров», когда CI выложит первый каталог: https://gornitsa.games/uzory/v1/catalog.json"
echo "Журнал: journalctl -u uzory-pull -n 50; journalctl -u uzory-packs -n 50"
