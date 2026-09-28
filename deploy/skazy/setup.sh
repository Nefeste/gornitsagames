#!/usr/bin/env bash
# Сервер заставы «Сказов» на этой машине: https://skazy.gornitsa.games
# (ADR 0024 и docs/05-process.md, раздел «Сервер», в репозитории Nefeste/skazy).
#
# Запускает автообновление сайта (deploy/update-site.sh), когда эта папка меняется в репозитории;
# вручную — от root:  bash /opt/gornitsa/deploy/skazy/setup.sh
# Скрипт можно запускать сколько угодно раз: он доводит настройку и ничего не ломает.
# Устроено как сервер «Длинных нард» (deploy/nardy/), отличия — в docs/05-process.md «Сказов»:
# без WebSocket; тело запроса до 260 КБ (копия хозяйства — до 256 КБ); журнал запросов
# поддомена — без адресов; раз в месяц — проверка, что копия базы восстанавливается.
#
# Что настраивает:
#   - Bun — официальная сборка с GitHub, версия закреплена (та же, что в CI «Сказов»), SHA-256 сверяется;
#   - пользователь skazy, база /var/lib/skazy/skazy.db, настройки /etc/skazy/env;
#   - служба skazy (bun server.js на 127.0.0.1:8791) — стартует, когда появится сборка;
#   - skazy-pull каждые 2 минуты: сборка из ветки `vps` репозитория Nefeste/skazy и сертификат
#     HTTPS, как только DNS укажет на сервер (deploy/skazy/pull.sh, nginx.sh);
#   - копия базы раз в сутки, семь дней (/var/backups/skazy); раз в месяц — проверка
#     восстановления (deploy/skazy/restore-check.sh); журнал nginx — три дня;
#   - ключ доступа к репозиторию (deploy key, только чтение): открытая часть —
#     https://skazy.gornitsa.games/.well-known/skazy-deploy.pub. Закрытая не покидает машину.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="skazy.gornitsa.games"
ETC=/etc/skazy
META=/var/www/skazy-meta/.well-known

# Версия Bun — та же, что в .github/workflows/server.yml и server/package.json «Сказов»
# (и у «Нард»: deploy/nardy/setup.sh).
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

echo "==> Сказы: пакеты"
need=()
for p in git sqlite3 curl openssl unzip; do command -v "$p" >/dev/null || need+=("$p"); done
command -v ssh-keygen >/dev/null || need+=(openssh-client)
if (( ${#need[@]} )); then
  "${APT[@]}" update
  "${APT[@]}" install "${need[@]}"
fi

# Bun: /opt/bun/<версия>/bun — общий с «Нардами»: та же версия ставится один раз.
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

echo "==> Сказы: пользователь и папки"
id -u skazy >/dev/null 2>&1 || useradd --system --home-dir /var/lib/skazy --no-create-home --shell /usr/sbin/nologin skazy
install -d -m 750 -o skazy -g skazy /var/lib/skazy
install -d -m 700 -o skazy -g skazy /var/backups/skazy
install -d -m 750 -o root -g skazy "$ETC"
install -d -m 755 /opt/skazy /opt/skazy/releases
install -d -m 700 /var/lib/skazy-deploy
install -d -m 755 "$META"
install -d -m 755 -o root -g adm /var/log/nginx/skazy

# Какой Bun — для pull.sh.
printf 'BUN=%q\n' "$BUN" > "$ETC/bun"
chmod 644 "$ETC/bun"

echo "==> Сказы: ключ доступа к репозиторию"
if [[ ! -f "$ETC/deploy_key" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C "skazy-deploy@${NAME}" -f "$ETC/deploy_key"
fi
chmod 600 "$ETC/deploy_key"
install -m 644 "$ETC/deploy_key.pub" "$META/skazy-deploy.pub"
# Ключи GitHub (https://api.github.com/meta → ssh_keys): подключаемся только к настоящему github.com.
cat > "$ETC/known_hosts" <<'KEYS'
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
KEYS
chmod 644 "$ETC/known_hosts"

echo "==> Сказы: настройки службы"
ENV="$ETC/env"
if [[ ! -f "$ENV" ]]; then
  (umask 027 && : > "$ENV")
fi
setvar() { grep -q "^$1=" "$ENV" || echo "$1=$2" >> "$ENV"; }
setvar SKAZY_DB /var/lib/skazy/skazy.db
setvar HOST 127.0.0.1
setvar PORT 8791
setvar SKAZY_TRUST_PROXY 1
# Секрет для удаления профиля по просьбе (POST /v1/admin/delete, server/tools/delete-by-tag.sh
# в «Сказах»): посмотреть — grep ADMIN_TOKEN /etc/skazy/env
setvar ADMIN_TOKEN "$(openssl rand -hex 32)"
chown root:skazy "$ENV"
chmod 640 "$ENV"

echo "==> Сказы: скрипты и службы"
install -m 755 "$SRC/pull.sh" /usr/local/sbin/skazy-pull
install -m 755 "$SRC/nginx.sh" /usr/local/sbin/skazy-nginx
install -m 755 "$SRC/backup.sh" /usr/local/sbin/skazy-backup
install -m 755 "$SRC/restore-check.sh" /usr/local/sbin/skazy-restore-check

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

write_unit skazy.service <<UNIT
[Unit]
Description=Сказы: сервер заставы (skazy.gornitsa.games)
After=network-online.target
Wants=network-online.target
ConditionPathExists=/opt/skazy/current/server.js

[Service]
User=skazy
Group=skazy
EnvironmentFile=$ENV
# Кэш разобранного кода Bun не нужен: сборка — один файл, запуск раз в выкладку.
Environment=BUN_RUNTIME_TRANSPILER_CACHE_PATH=0
WorkingDirectory=/opt/skazy/current
ExecStart=$BUN /opt/skazy/current/server.js
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
ReadWritePaths=/var/lib/skazy
# Застава не должна уронить соседей по машине (ADR 0024 «Сказов»).
MemoryMax=300M
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

write_unit skazy-pull.service <<'UNIT'
[Unit]
Description=Сказы: сборка из ветки vps, HTTPS
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/skazy-pull
UNIT

write_unit skazy-pull.timer <<'UNIT'
[Unit]
Description=Сказы: проверять сборку каждые 2 минуты

[Timer]
OnBootSec=100s
OnUnitActiveSec=2min

[Install]
WantedBy=timers.target
UNIT

write_unit skazy-backup.service <<'UNIT'
[Unit]
Description=Сказы: копия базы

[Service]
Type=oneshot
User=skazy
Group=skazy
ExecStart=/usr/local/sbin/skazy-backup
UNIT

write_unit skazy-backup.timer <<'UNIT'
[Unit]
Description=Сказы: копия базы раз в сутки

[Timer]
OnCalendar=*-*-* 04:10:00
RandomizedDelaySec=20min
Persistent=true

[Install]
WantedBy=timers.target
UNIT

write_unit skazy-restore-check.service <<'UNIT'
[Unit]
Description=Сказы: проверка восстановления базы из копии

[Service]
Type=oneshot
User=skazy
Group=skazy
PrivateTmp=yes
ExecStart=/usr/local/sbin/skazy-restore-check
UNIT

write_unit skazy-restore-check.timer <<'UNIT'
[Unit]
Description=Сказы: проверка восстановления раз в месяц

[Timer]
OnCalendar=*-*-01 05:20:00
RandomizedDelaySec=30min
Persistent=true

[Install]
WantedBy=timers.target
UNIT

# Журнал запросов nginx — три дня (общий /etc/logrotate.d/nginx эту папку не трогает).
cat > /etc/logrotate.d/skazy-nginx <<'ROT'
/var/log/nginx/skazy/*.log {
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

echo "==> Сказы: nginx"
/usr/local/sbin/skazy-nginx

systemctl daemon-reload
systemctl enable skazy.service >/dev/null 2>&1
systemctl enable --now skazy-pull.timer skazy-backup.timer skazy-restore-check.timer >/dev/null 2>&1
if [[ -e /opt/skazy/current/server.js ]]; then
  if [[ " ${CHANGED[*]} " == *" skazy.service "* ]]; then systemctl restart skazy; else systemctl start skazy; fi
fi

echo
echo "Сказы: машина настроена. Сервер поднимется сам, когда будут"
echo "  - DNS: A-запись ${NAME} -> этот сервер (HTTPS выпустится сам);"
echo "  - ключ только для чтения в Nefeste/skazy (Settings → Deploy keys):"
echo "    $(cat "$ETC/deploy_key.pub")"
echo "  - сборка в ветке vps (после слияния в main)."
echo "Журнал: journalctl -u skazy-pull -u skazy -n 50"
