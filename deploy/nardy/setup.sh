#!/usr/bin/env bash
# Сервер игры «Длинные нарды» на этой машине: https://nardy.gornitsa.games
# (ADR 0018 и спецификация 2026-09-server-vps в репозитории Nefeste/nardy).
#
# Запускает автообновление сайта (deploy/update-site.sh), когда эта папка меняется в репозитории;
# вручную — от root:  bash /opt/gornitsa/deploy/nardy/setup.sh
# Скрипт можно запускать сколько угодно раз: он доводит настройку и ничего не ломает.
# Устроено как сервер «Вотчины» (deploy/votchina/), только среда — Bun, а не Node.
#
# Что настраивает:
#   - Bun — официальная сборка с GitHub, версия закреплена (та же, что в CI нард), SHA-256 сверяется;
#   - пользователь nardy, база /var/lib/nardy/nardy.db, настройки /etc/nardy/env;
#   - служба nardy (bun server.js на 127.0.0.1:8790) — стартует, когда появится сборка;
#   - nardy-pull каждые 2 минуты: сборка из ветки `vps` репозитория Nefeste/nardy и сертификат
#     HTTPS, как только DNS укажет на сервер (deploy/nardy/pull.sh, nginx.sh);
#   - копия базы раз в сутки, семь дней (/var/backups/nardy); журнал nginx — три дня;
#   - ключ доступа к репозиторию (deploy key, только чтение): открытая часть —
#     https://nardy.gornitsa.games/.well-known/nardy-deploy.pub. Закрытая не покидает машину.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="nardy.gornitsa.games"
ETC=/etc/nardy
META=/var/www/nardy-meta/.well-known

# Версия Bun — та же, что в .github/workflows/server.yml и server/package.json репозитория нард.
BUN_VERSION=1.3.11
declare -A BUN_SHA256=(
  [bun-linux-x64.zip]=8611ba935af886f05a6f38740a15160326c15e5d5d07adef966130b4493607ed
  [bun-linux-x64-baseline.zip]=abe346f63414547cdf6b35b7a649a490c728b93d006226156923918a84c0e59b
  [bun-linux-aarch64.zip]=d13944da12a53ecc74bf6a720bd1d04c4555c038dfe422365356a7be47691fdf
)

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: bash $0" >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -q -y -o DPkg::Lock::Timeout=300)

echo "==> Нарды: пакеты"
need=()
for p in git sqlite3 curl openssl unzip; do command -v "$p" >/dev/null || need+=("$p"); done
command -v ssh-keygen >/dev/null || need+=(openssh-client)
if (( ${#need[@]} )); then
  "${APT[@]}" update
  "${APT[@]}" install "${need[@]}"
fi

# Bun: /opt/bun/<версия>/bun. Прежние версии остаются, пока их не удалить руками.
BUN="/opt/bun/${BUN_VERSION}/bun"
if [[ ! -x "$BUN" ]] || [[ "$("$BUN" --version 2>/dev/null)" != "$BUN_VERSION" ]]; then
  case "$(uname -m)" in
    # без AVX2 обычная сборка падает — тогда «baseline»
    x86_64) if grep -qw avx2 /proc/cpuinfo; then ZIP=bun-linux-x64.zip; else ZIP=bun-linux-x64-baseline.zip; fi ;;
    aarch64) ZIP=bun-linux-aarch64.zip ;;
    *) echo "Неизвестная архитектура $(uname -m)" >&2; exit 1 ;;
  esac
  echo "==> Ставлю Bun ${BUN_VERSION} (${ZIP})"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL --retry 3 "https://github.com/oven-sh/bun/releases/download/bun-v${BUN_VERSION}/${ZIP}" -o "$TMP/$ZIP"
  echo "${BUN_SHA256[$ZIP]}  $TMP/$ZIP" | sha256sum -c --quiet -
  unzip -q "$TMP/$ZIP" -d "$TMP"
  install -d -m 755 "/opt/bun/${BUN_VERSION}"
  install -m 755 "$TMP/${ZIP%.zip}/bun" "$BUN"
  [[ "$("$BUN" --version)" == "$BUN_VERSION" ]] || { echo "Bun из $BUN не запускается" >&2; exit 1; }
fi
echo "   Bun: $BUN $("$BUN" --version)"

echo "==> Нарды: пользователь и папки"
id -u nardy >/dev/null 2>&1 || useradd --system --home-dir /var/lib/nardy --no-create-home --shell /usr/sbin/nologin nardy
install -d -m 750 -o nardy -g nardy /var/lib/nardy
install -d -m 700 -o nardy -g nardy /var/backups/nardy
install -d -m 750 -o root -g nardy "$ETC"
install -d -m 755 /opt/nardy /opt/nardy/releases
install -d -m 700 /var/lib/nardy-deploy
install -d -m 755 "$META"
install -d -m 755 -o root -g adm /var/log/nginx/nardy

# Какой Bun — для pull.sh.
printf 'BUN=%q\n' "$BUN" > "$ETC/bun"
chmod 644 "$ETC/bun"

echo "==> Нарды: ключ доступа к репозиторию"
if [[ ! -f "$ETC/deploy_key" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C "nardy-deploy@${NAME}" -f "$ETC/deploy_key"
fi
chmod 600 "$ETC/deploy_key"
install -m 644 "$ETC/deploy_key.pub" "$META/nardy-deploy.pub"
# Ключи GitHub (https://api.github.com/meta → ssh_keys): подключаемся только к настоящему github.com.
cat > "$ETC/known_hosts" <<'KEYS'
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
KEYS
chmod 644 "$ETC/known_hosts"

echo "==> Нарды: настройки службы"
ENV="$ETC/env"
if [[ ! -f "$ENV" ]]; then
  (umask 027 && : > "$ENV")
fi
setvar() { grep -q "^$1=" "$ENV" || echo "$1=$2" >> "$ENV"; }
setvar NARDY_DB /var/lib/nardy/nardy.db
setvar HOST 127.0.0.1
setvar PORT 8790
setvar NARDY_TRUST_PROXY 1
# Секрет для удаления профиля по просьбе (POST /v1/admin/delete): посмотреть — grep ADMIN_TOKEN /etc/nardy/env
setvar ADMIN_TOKEN "$(openssl rand -hex 32)"
chown root:nardy "$ENV"
chmod 640 "$ENV"

echo "==> Нарды: скрипты и службы"
install -m 755 "$SRC/pull.sh" /usr/local/sbin/nardy-pull
install -m 755 "$SRC/nginx.sh" /usr/local/sbin/nardy-nginx
install -m 755 "$SRC/backup.sh" /usr/local/sbin/nardy-backup

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

write_unit nardy.service <<UNIT
[Unit]
Description=Нарды: сервер игры (nardy.gornitsa.games)
After=network-online.target
Wants=network-online.target
ConditionPathExists=/opt/nardy/current/server.js

[Service]
User=nardy
Group=nardy
EnvironmentFile=$ENV
# Кэш разобранного кода Bun не нужен: сборка — один файл, запуск раз в выкладку.
Environment=BUN_RUNTIME_TRANSPILER_CACHE_PATH=0
WorkingDirectory=/opt/nardy/current
ExecStart=$BUN /opt/nardy/current/server.js
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
ReadWritePaths=/var/lib/nardy
MemoryMax=300M
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

write_unit nardy-pull.service <<'UNIT'
[Unit]
Description=Нарды: сборка из ветки vps, HTTPS
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/nardy-pull
UNIT

write_unit nardy-pull.timer <<'UNIT'
[Unit]
Description=Нарды: проверять сборку каждые 2 минуты

[Timer]
OnBootSec=90s
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
UNIT

write_unit nardy-backup.service <<'UNIT'
[Unit]
Description=Нарды: копия базы

[Service]
Type=oneshot
User=nardy
Group=nardy
ExecStart=/usr/local/sbin/nardy-backup
UNIT

write_unit nardy-backup.timer <<'UNIT'
[Unit]
Description=Нарды: копия базы раз в сутки

[Timer]
OnCalendar=*-*-* 03:55:00
RandomizedDelaySec=20min
Persistent=true

[Install]
WantedBy=timers.target
UNIT

# Журнал запросов nginx — три дня (общий /etc/logrotate.d/nginx эту папку не трогает).
cat > /etc/logrotate.d/nardy-nginx <<'ROT'
/var/log/nginx/nardy/*.log {
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

echo "==> Нарды: nginx"
/usr/local/sbin/nardy-nginx

systemctl daemon-reload
systemctl enable nardy.service >/dev/null 2>&1
systemctl enable --now nardy-pull.timer nardy-backup.timer >/dev/null 2>&1
if [[ -e /opt/nardy/current/server.js ]]; then
  if [[ " ${CHANGED[*]} " == *" nardy.service "* ]]; then systemctl restart nardy; else systemctl start nardy; fi
fi

echo
echo "Нарды: машина настроена. Сервер поднимется сам, когда будут"
echo "  - DNS: A-запись ${NAME} -> этот сервер (HTTPS выпустится сам);"
echo "  - ключ только для чтения в Nefeste/nardy (Settings → Deploy keys):"
echo "    $(cat "$ETC/deploy_key.pub")"
echo "  - сборка в ветке vps (после слияния в main)."
echo "Журнал: journalctl -u nardy-pull -u nardy -n 50"
