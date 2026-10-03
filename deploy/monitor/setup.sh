#!/usr/bin/env bash
# Мониторинг ресурсов машины сайта и игр (решение владельца №16; порог для решения №17 — в README,
# раздел «Мониторинг машины»).
#
# Запускает автообновление сайта (deploy/update-site.sh), когда эта папка меняется в репозитории;
# вручную — от root:  bash /opt/gornitsa/deploy/monitor/setup.sh
# Скрипт можно запускать сколько угодно раз: он доводит настройку и ничего не ломает.
#
# Что настраивает:
#   - пользователь gornitsa-monitor (читает журнал ядра — группа systemd-journal), без входа;
#   - gornitsa-monitor.timer раз в минуту: CPU и load average, RAM, swap, диск, MemoryCurrent и
#     CPUUsageNSec служб votchina, nardy, skazy, nginx, события OOM из журнала ядра — в SQLite
#     /var/lib/gornitsa-monitor/monitor.db, 30 дней (deploy/monitor/monitor.py);
#   - gornitsa-monitor-daily.timer в 00:05: сводка за сутки в /var/lib/gornitsa-monitor/daily/
#     ГГГГ-ММ-ДД.json и latest.json — год;
#   - https://gornitsa.games/.well-known/monitor/latest.json (и сводки по датам) — только по HTTPS
#     и только с именем и паролем владельца: sudo gornitsa-monitor-password (deploy/monitor/nginx.sh);
#   - gornitsa-sitestats.timer в 00:20: посещаемость сайта без IP из журнала nginx — суммы за сутки
#     и неделя в site-week.json, открыто: .well-known/monitor/site-week.json (deploy/monitor/sitestats.py,
#     поручение 06, решение №30).

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_=gornitsa-monitor
BASE=/var/lib/gornitsa-monitor
LIB=/usr/local/lib/gornitsa-monitor

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: bash $0" >&2
  exit 1
fi
command -v python3 >/dev/null || { echo "Нужен python3 (его ставит deploy/bootstrap.sh)" >&2; exit 1; }

echo "==> Мониторинг: пользователь и папки"
id -u "$USER_" >/dev/null 2>&1 || useradd --system --home-dir "$BASE" --no-create-home --shell /usr/sbin/nologin "$USER_"
# База — только сборщику; сводки — ещё и nginx (группа www-data), чтобы отдать их по паролю.
install -d -m 750 -o "$USER_" -g www-data "$BASE"
install -d -m 2750 -o "$USER_" -g www-data "$BASE/daily"
install -d -m 750 -o root -g www-data /etc/gornitsa-monitor
install -d -m 755 "$LIB"
install -m 755 "$SRC/monitor.py" "$LIB/monitor.py"
install -m 755 "$SRC/sitestats.py" "$LIB/sitestats.py"
install -m 755 "$SRC/nginx.sh" /usr/local/sbin/gornitsa-monitor-nginx
install -m 755 "$SRC/password.sh" /usr/local/sbin/gornitsa-monitor-password

echo "==> Мониторинг: службы и таймеры"
# Общие ограничения: читать машину можно, писать — только в свою папку.
read -r -d '' SANDBOX <<'UNIT' || true
User=gornitsa-monitor
Group=gornitsa-monitor
SupplementaryGroups=systemd-journal
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/lib/gornitsa-monitor
Nice=10
MemoryMax=96M
UNIT

cat > /etc/systemd/system/gornitsa-monitor.service <<UNIT
[Unit]
Description=Мониторинг машины: замер раз в минуту

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 ${LIB}/monitor.py collect
TimeoutStartSec=50
${SANDBOX}
UNIT

cat > /etc/systemd/system/gornitsa-monitor.timer <<'UNIT'
[Unit]
Description=Мониторинг машины раз в минуту

[Timer]
OnCalendar=minutely
AccuracySec=5s

[Install]
WantedBy=timers.target
UNIT

cat > /etc/systemd/system/gornitsa-monitor-daily.service <<UNIT
[Unit]
Description=Мониторинг машины: сводка за сутки

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 ${LIB}/monitor.py daily
${SANDBOX}
UNIT

cat > /etc/systemd/system/gornitsa-monitor-daily.timer <<'UNIT'
[Unit]
Description=Сводка мониторинга машины раз в сутки

[Timer]
OnCalendar=*-*-* 00:05:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT

# Посещаемость сайта: журнал nginx читает группа adm; пишет — только в свою папку, сеть не нужна.
cat > /etc/systemd/system/gornitsa-sitestats.service <<UNIT
[Unit]
Description=Посещаемость сайта без IP: суммы за сутки и неделя

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 ${LIB}/sitestats.py daily
ExecStart=/usr/bin/python3 ${LIB}/sitestats.py week
User=gornitsa-monitor
Group=gornitsa-monitor
SupplementaryGroups=adm www-data
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateNetwork=yes
ReadOnlyPaths=/var/log/nginx /var/www
ReadWritePaths=/var/lib/gornitsa-monitor
Nice=10
MemoryMax=128M
UNIT

cat > /etc/systemd/system/gornitsa-sitestats.timer <<'UNIT'
[Unit]
Description=Посещаемость сайта раз в сутки

[Timer]
OnCalendar=*-*-* 00:20:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now gornitsa-monitor.timer gornitsa-monitor-daily.timer gornitsa-sitestats.timer

echo "==> Мониторинг: сводки по адресу .well-known/monitor/"
/usr/local/sbin/gornitsa-monitor-nginx

echo "Мониторинг включён. Замеры: journalctl -u gornitsa-monitor -n 20; сводки — ${BASE}/daily/"
if [[ ! -s /etc/gornitsa-monitor/htpasswd ]]; then
  echo "Сводки по сети закрыты, пока владелец не задаст пароль: sudo gornitsa-monitor-password"
fi
