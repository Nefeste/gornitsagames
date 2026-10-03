#!/usr/bin/env bash
# gornitsa-backup-sftp: вход backup по SFTP только для чтения копий (docs/backup.md).
# Ставит deploy/backup/setup.sh; вызывает gornitsa-backup-keys после смены ключа.
#
#   - /etc/gornitsa-backup/authorized_keys — из owner-ssh.pub, с «restrict» (без пересылок, без tty);
#     нет ключа владельца — файл пустой, войти нельзя никому;
#   - /etc/ssh/sshd_config.d/backup.conf — Match User backup: chroot в /srv/backup, только
#     internal-sftp -R (чтение) с журналом -l INFO — по нему мониторинг видит, что копии забирают.
# Новый конфиг проверяется sshd -t, не прошёл — возвращается прежний; открытые сессии не рвутся.

set -euo pipefail

ETC=/etc/gornitsa-backup
CONF=/etc/ssh/sshd_config.d/backup.conf
KEYS="${ETC}/authorized_keys"

[[ $EUID -eq 0 ]] || { echo "Запустите от root" >&2; exit 1; }

tmp="$(mktemp)"
if [[ -s "${ETC}/owner-ssh.pub" ]] && ssh-keygen -l -f "${ETC}/owner-ssh.pub" >/dev/null 2>&1; then
  grep -E '^(ssh-|ecdsa-|sk-)' "${ETC}/owner-ssh.pub" | sed 's/^/restrict /' > "$tmp"
fi
install -m 644 -o root -g root "$tmp" "$KEYS"
rm -f "$tmp"

tmp="$(mktemp)"
cat > "$tmp" <<CONF
# SFTP только для чтения копий баз. Файл пишет /usr/local/sbin/gornitsa-backup-sftp
# (репозиторий gornitsagames, deploy/backup/sftp.sh) — правки здесь затрутся.
Match User backup
    ChrootDirectory /srv/backup
    ForceCommand internal-sftp -R -l INFO
    AuthorizedKeysFile ${KEYS}
    AuthenticationMethods publickey
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AllowTcpForwarding no
    AllowAgentForwarding no
    AllowStreamLocalForwarding no
    X11Forwarding no
    PermitTunnel no
    PermitTTY no
    PermitUserRC no
    GatewayPorts no
CONF
if [[ -f "$CONF" ]] && cmp -s "$tmp" "$CONF"; then
  rm -f "$tmp"
  exit 0
fi
old=""
if [[ -f "$CONF" ]]; then old="$(mktemp)"; cp -p "$CONF" "$old"; fi
install -m 644 "$tmp" "$CONF"
rm -f "$tmp"
install -d -m 755 /run/sshd   # без неё sshd -t не проходит, когда sshd запускается по сокету
if ! sshd -t; then
  if [[ -n "$old" ]]; then mv -f "$old" "$CONF"; else rm -f "$CONF"; fi
  echo "SSH: конфиг backup не прошёл sshd -t — оставил прежний" >&2
  exit 1
fi
rm -f "$old"
if systemctl is-active --quiet ssh; then systemctl reload ssh; fi
echo "SSH: backup — только SFTP на чтение, chroot /srv/backup"
