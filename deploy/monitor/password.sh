#!/usr/bin/env bash
# gornitsa-monitor-password — имя и пароль для сводок мониторинга
# (https://gornitsa.games/.well-known/monitor/latest.json). Ставит deploy/monitor/setup.sh;
# устроено как uzory-password (deploy/uzory/password.sh). Запускает владелец на сервере:
#
#   sudo gornitsa-monitor-password          спросит имя и пароль
#   sudo gornitsa-monitor-password misha    спросит пароль для имени misha
#
# Пароль вводится здесь же и не показывается; в /etc/gornitsa-monitor/htpasswd ложится только его хеш
# (SHA-512 crypt). То же имя — пароль меняется, другое — добавляется ещё один вход.
# Закрыть всем:  sudo rm /etc/gornitsa-monitor/htpasswd && sudo gornitsa-monitor-nginx

set -euo pipefail

FILE=/etc/gornitsa-monitor/htpasswd

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: sudo gornitsa-monitor-password" >&2
  exit 1
fi

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  read -r -p "Имя для входа (латиницей): " NAME
fi
if [[ ! "$NAME" =~ ^[A-Za-z0-9._-]{1,32}$ ]]; then
  echo "Имя — латинские буквы, цифры, точка, дефис или подчёркивание, до 32 знаков. Ничего не поменял." >&2
  exit 1
fi
read -r -s -p "Пароль (не короче 12 знаков): " P1
echo
read -r -s -p "Ещё раз: " P2
echo
if [[ "$P1" != "$P2" ]]; then
  echo "Пароли не совпали. Ничего не поменял." >&2
  exit 1
fi
if (( ${#P1} < 12 )); then
  echo "Короче 12 знаков. Ничего не поменял." >&2
  exit 1
fi
HASH="$(printf '%s' "$P1" | openssl passwd -6 -stdin)"
unset P1 P2

install -d -m 750 -o root -g www-data /etc/gornitsa-monitor
TMP="$(mktemp /etc/gornitsa-monitor/.htpasswd.XXXXXX)"
{
  if [[ -f "$FILE" ]]; then awk -F: -v n="$NAME" '$1 != n' "$FILE"; fi
  printf '%s:%s\n' "$NAME" "$HASH"
} > "$TMP"
chown root:www-data "$TMP"
chmod 640 "$TMP"
mv -f "$TMP" "$FILE"

/usr/local/sbin/gornitsa-monitor-nginx
echo "Готово: https://gornitsa.games/.well-known/monitor/latest.json — имя «$NAME» и этот пароль."
