#!/usr/bin/env bash
# uzory-password — имя и пароль для закрытой веб-версии «Узоров» (https://gornitsa.games/uzory/test/).
# Ставит deploy/uzory/setup.sh. Запускает владелец на сервере:
#
#   sudo uzory-password            спросит имя и пароль
#   sudo uzory-password misha      спросит пароль для имени misha
#
# Пароль вводится здесь же и не показывается; в /etc/uzory/test.htpasswd ложится только его хеш
# (SHA-512 crypt). То же имя — пароль меняется, другое — добавляется ещё один вход.
# Закрыть всем:  sudo rm /etc/uzory/test.htpasswd && sudo uzory-nginx

set -euo pipefail

FILE=/etc/uzory/test.htpasswd

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: sudo uzory-password" >&2
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
read -r -s -p "Пароль (не короче 10 знаков): " P1
echo
read -r -s -p "Ещё раз: " P2
echo
if [[ "$P1" != "$P2" ]]; then
  echo "Пароли не совпали. Ничего не поменял." >&2
  exit 1
fi
if (( ${#P1} < 10 )); then
  echo "Короче 10 знаков. Ничего не поменял." >&2
  exit 1
fi
HASH="$(printf '%s' "$P1" | openssl passwd -6 -stdin)"
unset P1 P2

install -d -m 750 -o root -g www-data /etc/uzory
TMP="$(mktemp /etc/uzory/.htpasswd.XXXXXX)"
{
  if [[ -f "$FILE" ]]; then awk -F: -v n="$NAME" '$1 != n' "$FILE"; fi
  printf '%s:%s\n' "$NAME" "$HASH"
} > "$TMP"
chown root:www-data "$TMP"
chmod 640 "$TMP"
mv -f "$TMP" "$FILE"

/usr/local/sbin/uzory-nginx
echo "Готово: https://gornitsa.games/uzory/test/ — имя «$NAME» и этот пароль."
