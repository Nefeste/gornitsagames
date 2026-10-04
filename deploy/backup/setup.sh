#!/usr/bin/env bash
# Копии баз на компьютер владельца по SFTP (решение владельца №15; инструкция — docs/backup.md).
#
# Запускает автообновление сайта (deploy/update-site.sh), когда эта папка меняется в репозитории;
# вручную — от root:  bash /opt/gornitsa/deploy/backup/setup.sh
# На машине «Сеней» — тот же скрипт из клона этого репозитория (docs/backup.md, «Машина „Сеней“»).
# Скрипт можно запускать сколько угодно раз: он доводит настройку и ничего не ломает.
#
# Что настраивает:
#   - пакеты sqlite3 и age;
#   - /etc/gornitsa-backup/targets.conf — что снимать: базы и архив настроек машины с секретами
#     служб (из targets.conf.example: только то, что есть на этой машине; дальше файл правится
#     на машине, архив настроек дописывается и в старый список);
#   - gornitsa-backup.timer в 03:30 по Москве: снимок, проверка, gzip и age в
#     /srv/backup/out/ГГГГ-ММ-ДД/, 14 дней (deploy/backup/snapshot.sh);
#   - пользователь backup: без пароля и shell, только SFTP на чтение в chroot /srv/backup,
#     только по ключу владельца (deploy/backup/sftp.sh); журнал чтений — через /srv/backup/dev/log;
#   - sudo gornitsa-backup-keys — владелец вставляет свои открытые ключи SSH и age (keys.sh);
#   - gornitsa-backup-status.timer раз в 10 минут: тревоги для «Сторожа» в
#     /var/lib/gornitsa-backup/public/status.json (status.py), без данных о людях.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETC=/etc/gornitsa-backup

[[ $EUID -eq 0 ]] || { echo "Запустите от root: bash $0" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -q -y -o DPkg::Lock::Timeout=300)

echo "==> Копии баз: пакеты"
need=()
for p in sqlite3 age gzip python3; do command -v "$p" >/dev/null || need+=("$p"); done
if (( ${#need[@]} )); then
  "${APT[@]}" update
  "${APT[@]}" install "${need[@]}"
fi

echo "==> Копии баз: пользователь backup и папки"
# В Debian и Ubuntu системный пользователь backup уже есть (uid 34, без пароля); иначе — создаём.
id -u backup >/dev/null 2>&1 || useradd --system --home-dir /var/backups --no-create-home --shell /usr/sbin/nologin backup
usermod -s /usr/sbin/nologin backup
passwd -l backup >/dev/null 2>&1 || true
# chroot: /srv/backup — только root и без записи для остальных (иначе sshd не пустит);
# out/ — backup читает, писать не может.
install -d -m 755 -o root -g root /srv /srv/backup
install -d -m 750 -o root -g backup /srv/backup/out
install -d -m 755 -o root -g root "$ETC" /var/lib/gornitsa-backup

# Строки примера, подходящие этой машине: база — если есть её папка, архив файлов — если есть
# первый путь (/etc/votchina на машине сайта, /etc/seni у «Сеней»).
fitting() {
  sed -E 's/^# (seni(-config)?[[:space:]])/\1/' "$SRC/targets.conf.example" | while read -r name first rest; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    if [[ -z "$rest" && "$first" == *.db ]]; then
      if [[ -d "$(dirname "$first")" ]]; then printf 'db %s %s\n' "$name" "$first"; fi
    elif [[ -e "$first" ]]; then
      printf 'files %s %s %s\n' "$name" "$first" "$rest"
    fi
  done
}
if [[ ! -f "$ETC/targets.conf" ]]; then
  {
    echo "# Что снимает gornitsa-backup. Пример и пояснения — deploy/backup/targets.conf.example."
    fitting | cut -d' ' -f2-
  } > "$ETC/targets.conf"
  chmod 644 "$ETC/targets.conf"
  echo "   Список копий: $(grep -cv '^#' "$ETC/targets.conf" || true) — $ETC/targets.conf"
else
  # Архивы настроек появились позже баз: в уже заведённый список дописываются, если их там нет.
  while read -r kind name line; do
    [[ "$kind" == files ]] || continue
    if ! awk -v n="$name" '$1 == n { found = 1 } END { exit !found }' "$ETC/targets.conf"; then
      echo "$name $line" >> "$ETC/targets.conf"
      echo "   В список копий добавлен архив настроек: $name"
    fi
  done < <(fitting)
fi

echo "==> Копии баз: скрипты и таймер"
install -m 755 "$SRC/snapshot.sh" /usr/local/sbin/gornitsa-backup
install -m 755 "$SRC/keys.sh" /usr/local/sbin/gornitsa-backup-keys
install -m 755 "$SRC/sftp.sh" /usr/local/sbin/gornitsa-backup-sftp
install -d -m 755 /usr/local/lib/gornitsa-backup /var/lib/gornitsa-backup/public
install -m 755 "$SRC/status.py" /usr/local/lib/gornitsa-backup/status.py

cat > /etc/systemd/system/gornitsa-backup.service <<'UNIT'
[Unit]
Description=Копии баз: снимок, проверка, шифрование ключом владельца

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/gornitsa-backup
# Пишет только в /srv/backup и /var/lib/gornitsa-backup; базы читает от имени их владельцев.
ProtectHome=yes
PrivateTmp=yes
Nice=10
IOSchedulingClass=idle
UNIT

cat > /etc/systemd/system/gornitsa-backup-status.service <<'UNIT'
[Unit]
Description=Копии баз: тревоги для «Сторожа» (status.json без данных о людях)

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/lib/gornitsa-backup/status.py
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/lib/gornitsa-backup
UNIT

cat > /etc/systemd/system/gornitsa-backup-status.timer <<'UNIT'
[Unit]
Description=Тревоги копий баз раз в 10 минут

[Timer]
OnCalendar=*:0/10
OnBootSec=2min

[Install]
WantedBy=timers.target
UNIT

cat > /etc/systemd/system/gornitsa-backup.timer <<'UNIT'
[Unit]
Description=Копии баз раз в сутки, 03:30 по Москве

[Timer]
OnCalendar=*-*-* 03:30:00 Europe/Moscow
Persistent=true
RandomizedDelaySec=5min

[Install]
WantedBy=timers.target
UNIT

# Журнал SFTP: internal-sftp в chroot пишет в /dev/log внутри chroot — туда подключается сокет
# journald. По строкам «close … bytes read» мониторинг видит, что владелец забирает копии.
install -d -m 755 -o root -g root /srv/backup/dev
[[ -e /srv/backup/dev/log ]] || touch /srv/backup/dev/log
cat > /etc/systemd/system/srv-backup-dev-log.mount <<'UNIT'
[Unit]
Description=Журнал SFTP копий баз: /dev/log внутри chroot /srv/backup
After=systemd-journald-dev-log.socket

[Mount]
What=/run/systemd/journal/dev-log
Where=/srv/backup/dev/log
Type=none
Options=bind

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now gornitsa-backup.timer gornitsa-backup-status.timer srv-backup-dev-log.mount
systemctl start gornitsa-backup-status.service || true

echo "==> Копии баз: SFTP только для чтения"
/usr/local/sbin/gornitsa-backup-sftp

if ! grep -q '^age1' "$ETC/recipients.txt" 2>/dev/null || [[ ! -s "$ETC/owner-ssh.pub" ]]; then
  echo "Копии не делаются и не выдаются, пока владелец не вставит открытые ключи: sudo gornitsa-backup-keys"
fi
