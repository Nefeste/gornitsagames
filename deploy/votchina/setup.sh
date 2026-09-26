#!/usr/bin/env bash
# Сервер игры «Вотчина» на этой машине: https://votchina.gornitsa.games
# (ADR 0019 и спецификация 2026-09-server-ru в репозитории Nefeste/votchina).
#
# Запускает автообновление сайта (deploy/update-site.sh), когда эта папка меняется в репозитории;
# вручную — от root:  bash /opt/gornitsa/deploy/votchina/setup.sh
# Скрипт можно запускать сколько угодно раз: он доводит настройку и ничего не ломает.
#
# Что настраивает:
#   - Node с node:sqlite (из системы; если там старый — snap node 22 или сборка с nodejs.org);
#   - пользователь votchina, база /var/lib/votchina/votchina.db, настройки /etc/votchina/env;
#   - служба votchina (node serve.mjs на 127.0.0.1:8787) — стартует, когда появится сборка;
#   - votchina-pull каждые 2 минуты: сборка из ветки `vps`, выгрузка базы из `vps-import`,
#     сертификат HTTPS, как только DNS укажет на сервер (deploy/votchina/pull.sh, nginx.sh);
#   - копия базы раз в сутки, семь дней (/var/backups/votchina); журнал nginx — три дня;
#   - ключ доступа к репозиторию (deploy key, только чтение) и ключ шифрования выгрузки (age):
#     открытые части — https://votchina.gornitsa.games/.well-known/votchina-deploy.pub и
#     votchina-age.pub. Закрытые не покидают машину.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="votchina.gornitsa.games"
ETC=/etc/votchina
META=/var/www/votchina-meta/.well-known

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: bash $0" >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -q -y -o DPkg::Lock::Timeout=300)

echo "==> Вотчина: пакеты"
need=()
for p in git age sqlite3 curl openssl; do command -v "$p" >/dev/null || need+=("$p"); done
command -v ssh-keygen >/dev/null || need+=(openssh-client)
command -v xz >/dev/null || need+=(xz-utils)
if (( ${#need[@]} )); then
  "${APT[@]}" update
  "${APT[@]}" install "${need[@]}"
fi

# Node с node:sqlite без флагов (22.13 и новее). По порядку: из системы (apt, обновляется вместе
# с ней); snap «node» канала 22 от авторов Node (обновляется сам); официальная сборка с nodejs.org.
# Snap запускаем прямо из /snap/node/current, без `snap run`: так он работает и под защитой systemd.
node_ok() { [[ -x "$1" ]] && "$1" -e "require('node:sqlite')" >/dev/null 2>&1; }
NODE=""
for n in /usr/bin/node /snap/node/current/bin/node /opt/node/bin/node; do
  if node_ok "$n"; then NODE="$n"; break; fi
done
if [[ -z "$NODE" && ! -x /usr/bin/node ]]; then
  "${APT[@]}" update
  "${APT[@]}" install nodejs || true
  if node_ok /usr/bin/node; then NODE=/usr/bin/node; fi
fi
if [[ -z "$NODE" ]] && command -v snap >/dev/null; then
  echo "==> Node из системы старый — ставлю snap node (канал 22)"
  snap install node --channel=22/stable --classic || true
  if node_ok /snap/node/current/bin/node; then NODE=/snap/node/current/bin/node; fi
fi
if [[ -z "$NODE" ]]; then
  echo "==> Ставлю официальную сборку Node 22 с nodejs.org в /opt/node"
  case "$(uname -m)" in
    x86_64) ARCH=x64 ;;
    aarch64) ARCH=arm64 ;;
    *) echo "Неизвестная архитектура $(uname -m)" >&2; exit 1 ;;
  esac
  BASE="https://nodejs.org/dist/latest-v22.x"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL --retry 3 "$BASE/SHASUMS256.txt" -o "$TMP/SHASUMS256.txt"
  FILE="$(awk -v a="linux-${ARCH}.tar.xz" '$2 ~ a"$" {print $2; exit}' "$TMP/SHASUMS256.txt")"
  [[ -n "$FILE" ]] || { echo "Не нашёл сборку Node для linux-${ARCH}" >&2; exit 1; }
  curl -fsSL --retry 3 "$BASE/$FILE" -o "$TMP/$FILE"
  (cd "$TMP" && grep " ${FILE}\$" SHASUMS256.txt | sha256sum -c --quiet -)
  rm -rf /opt/node.new
  mkdir -p /opt/node.new
  tar -xJf "$TMP/$FILE" --strip-components=1 -C /opt/node.new
  rm -rf /opt/node
  mv /opt/node.new /opt/node
  node_ok /opt/node/bin/node || { echo "Node из /opt/node не видит node:sqlite" >&2; exit 1; }
  NODE=/opt/node/bin/node
fi
FLAGS=""
"$NODE" --disable-warning=ExperimentalWarning -e 0 >/dev/null 2>&1 && FLAGS="--disable-warning=ExperimentalWarning"
echo "   Node: $NODE $("$NODE" --version)"

echo "==> Вотчина: пользователь и папки"
id -u votchina >/dev/null 2>&1 || useradd --system --home-dir /var/lib/votchina --no-create-home --shell /usr/sbin/nologin votchina
install -d -m 750 -o votchina -g votchina /var/lib/votchina
install -d -m 700 -o votchina -g votchina /var/backups/votchina
install -d -m 750 -o root -g votchina "$ETC"
install -d -m 755 /opt/votchina /opt/votchina/releases
install -d -m 700 /var/lib/votchina-deploy
install -d -m 755 "$META"
install -d -m 755 -o root -g adm /var/log/nginx/votchina

# Какой Node и с какими флагами — для pull.sh.
printf 'NODE=%q\nFLAGS=%q\n' "$NODE" "$FLAGS" > "$ETC/node"
chmod 644 "$ETC/node"

echo "==> Вотчина: ключи"
if [[ ! -f "$ETC/deploy_key" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C "votchina-deploy@${NAME}" -f "$ETC/deploy_key"
fi
chmod 600 "$ETC/deploy_key"
if [[ ! -f "$ETC/age.key" ]]; then
  (umask 077 && age-keygen -o "$ETC/age.key" 2>/dev/null)
fi
chmod 600 "$ETC/age.key"
install -m 644 "$ETC/deploy_key.pub" "$META/votchina-deploy.pub"
age-keygen -y "$ETC/age.key" > "$META/votchina-age.pub"
chmod 644 "$META/votchina-age.pub"
# Ключи GitHub (https://api.github.com/meta → ssh_keys): подключаемся только к настоящему github.com.
cat > "$ETC/known_hosts" <<'KEYS'
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
KEYS
chmod 644 "$ETC/known_hosts"

echo "==> Вотчина: настройки службы"
ENV="$ETC/env"
if [[ ! -f "$ENV" ]]; then
  (umask 027 && : > "$ENV")
fi
setvar() { grep -q "^$1=" "$ENV" || echo "$1=$2" >> "$ENV"; }
setvar VOTCHINA_DB /var/lib/votchina/votchina.db
setvar HOST 127.0.0.1
setvar PORT 8787
setvar VOTCHINA_TRUST_PROXY 1
# Секрет для служебных запросов (server/tools/delete-by-tag.sh): посмотреть — grep ADMIN_TOKEN /etc/votchina/env
setvar ADMIN_TOKEN "$(openssl rand -hex 32)"
chown root:votchina "$ENV"
chmod 640 "$ENV"

echo "==> Вотчина: скрипты и службы"
install -m 755 "$SRC/pull.sh" /usr/local/sbin/votchina-pull
install -m 755 "$SRC/nginx.sh" /usr/local/sbin/votchina-nginx
install -m 755 "$SRC/backup.sh" /usr/local/sbin/votchina-backup

CHANGED=()
write_unit() {   # пишет файл службы, только если он изменился (тогда имя — в CHANGED)
  local f="/etc/systemd/system/$1" tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  if [[ -f "$f" ]] && cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  install -m 644 "$tmp" "$f"
  rm -f "$tmp"
  CHANGED+=("$1")
}

write_unit votchina.service <<UNIT
[Unit]
Description=Вотчина: сервер игры (votchina.gornitsa.games)
After=network-online.target
Wants=network-online.target
ConditionPathExists=/opt/votchina/current/serve.mjs

[Service]
User=votchina
Group=votchina
EnvironmentFile=$ENV
WorkingDirectory=/opt/votchina/current
ExecStart=$NODE $FLAGS /opt/votchina/current/serve.mjs
Restart=always
RestartSec=3
TimeoutStopSec=20
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
LockPersonality=yes
ReadWritePaths=/var/lib/votchina
MemoryMax=700M
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

write_unit votchina-pull.service <<'UNIT'
[Unit]
Description=Вотчина: сборка из ветки vps, выгрузка базы, HTTPS
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/votchina-pull
UNIT

write_unit votchina-pull.timer <<'UNIT'
[Unit]
Description=Вотчина: проверять сборку и выгрузку каждые 2 минуты

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
UNIT

write_unit votchina-backup.service <<'UNIT'
[Unit]
Description=Вотчина: копия базы

[Service]
Type=oneshot
User=votchina
Group=votchina
ExecStart=/usr/local/sbin/votchina-backup
UNIT

write_unit votchina-backup.timer <<'UNIT'
[Unit]
Description=Вотчина: копия базы раз в сутки

[Timer]
OnCalendar=*-*-* 03:40:00
RandomizedDelaySec=20min
Persistent=true

[Install]
WantedBy=timers.target
UNIT

# Журнал запросов nginx — три дня (общий /etc/logrotate.d/nginx эту папку не трогает).
cat > /etc/logrotate.d/votchina-nginx <<'ROT'
/var/log/nginx/votchina/*.log {
	daily
	rotate 3
	missingok
	notifempty
	compress
	delaycompress
	create 0640 www-data adm
	sharedscripts
	postrotate
		invoke-rc.d nginx rotate >/dev/null 2>&1 || true
	endscript
}
ROT

echo "==> Вотчина: nginx"
/usr/local/sbin/votchina-nginx

systemctl daemon-reload
systemctl enable votchina.service >/dev/null 2>&1
systemctl enable --now votchina-pull.timer votchina-backup.timer >/dev/null 2>&1
if [[ -e /opt/votchina/current/serve.mjs ]]; then
  if [[ " ${CHANGED[*]} " == *" votchina.service "* ]]; then systemctl restart votchina; else systemctl start votchina; fi
fi

echo
echo "Вотчина: машина настроена. Сервер поднимется сам, когда будут"
echo "  - DNS: A-запись ${NAME} -> этот сервер (HTTPS выпустится сам);"
echo "  - ключ только для чтения в Nefeste/votchina (Settings → Deploy keys):"
echo "    $(cat "$ETC/deploy_key.pub")"
echo "  - сборка в ветке vps (после слияния в main)."
echo "Журнал: journalctl -u votchina-pull -u votchina -n 50"
