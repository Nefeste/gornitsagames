#!/usr/bin/env bash
# gornitsa-backup-keys — открытые ключи владельца для копий баз (docs/backup.md, шаг 2).
# Ставит deploy/backup/setup.sh. Запускает владелец на сервере:
#
#   sudo gornitsa-backup-keys        спросит открытый ключ SSH и открытый ключ age
#
# Принимаются только ОТКРЫТЫЕ ключи: строка «ssh-ed25519 AAAA… имя» из файла .pub и строка
# «age1…» из вывода age-keygen. Закрытые ключи на сервер не попадают никогда.
#   /etc/gornitsa-backup/owner-ssh.pub   — им пользователь backup входит по SFTP;
#   /etc/gornitsa-backup/recipients.txt  — им шифруются копии (можно несколько строк age1…).
# Повторный запуск заменяет ключи: так меняют потерянный или новый компьютер.

set -euo pipefail

ETC=/etc/gornitsa-backup
[[ $EUID -eq 0 ]] || { echo "Запустите от root: sudo gornitsa-backup-keys" >&2; exit 1; }
install -d -m 755 "$ETC"

echo "Открытый ключ SSH — одна строка из файла gornitsa_backup.pub (начинается с ssh-ed25519)."
read -r -p "Ключ SSH (Enter — оставить прежний): " SSH_KEY
if [[ -n "$SSH_KEY" ]]; then
  if [[ "$SSH_KEY" == *PRIVATE* ]]; then
    echo "Это закрытый ключ — его никуда отправлять нельзя. Ничего не поменял." >&2
    exit 1
  fi
  tmp="$(mktemp)"
  printf '%s\n' "$SSH_KEY" > "$tmp"
  if ! ssh-keygen -l -f "$tmp" >/dev/null 2>&1 || [[ "$SSH_KEY" != ssh-* ]]; then
    rm -f "$tmp"
    echo "Это не открытый ключ SSH. Ничего не поменял." >&2
    exit 1
  fi
  install -m 644 "$tmp" "$ETC/owner-ssh.pub"
  rm -f "$tmp"
  echo "Ключ SSH: $(ssh-keygen -l -f "$ETC/owner-ssh.pub")"
fi

echo "Открытый ключ age — строка «Public key: age1…» из вывода age-keygen (вставьте только age1…)."
read -r -p "Ключ age (Enter — оставить прежний): " AGE_KEY
if [[ -n "$AGE_KEY" ]]; then
  if [[ "$AGE_KEY" == AGE-SECRET-KEY-* ]]; then
    echo "Это закрытый ключ age — его никуда отправлять нельзя. Ничего не поменял." >&2
    exit 1
  fi
  if [[ ! "$AGE_KEY" =~ ^age1[02-9ac-hj-np-z]{58}$ ]]; then
    echo "Это не открытый ключ age (age1… из 62 знаков). Ничего не поменял." >&2
    exit 1
  fi
  # проверка на деле: этим ключом можно зашифровать
  if ! echo test | age -r "$AGE_KEY" >/dev/null; then
    echo "age не принял ключ. Ничего не поменял." >&2
    exit 1
  fi
  printf '%s\n' "$AGE_KEY" > "$ETC/recipients.txt"
  chmod 644 "$ETC/recipients.txt"
  echo "Ключ age: ${AGE_KEY:0:16}…"
fi

/usr/local/sbin/gornitsa-backup-sftp
# Отпечаток ключа сервера: при первом входе по SFTP сверьте его с тем, что покажет компьютер.
for k in /etc/ssh/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ecdsa_key.pub; do
  if [[ -f "$k" ]]; then echo "Отпечаток сервера: $(ssh-keygen -l -f "$k" | awk '{print $2, $NF}')"; fi
done
echo "Готово. Первая копия — сегодня в 03:30 по Москве; сразу — sudo systemctl start gornitsa-backup"
