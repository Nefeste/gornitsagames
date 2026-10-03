#!/usr/bin/env bash
# gornitsa-ssh: вход на сервер только по ключам, root — без входа (аудит 03.10.2026, раздел 4).
# Ставит и запускает deploy/setup-server.sh; порядок для владельца — README, «Вход на сервер».
#
#   gornitsa-ssh        довести настройку: пароли выключены, root входит только по ключу
#   gornitsa-ssh ok     владелец вошёл по SSH как ADMIN_USER и у него работает sudo — теперь root
#                       не входит совсем (запускать из этой самой сессии: sudo gornitsa-ssh ok)
#
# Чтобы не потерять доступ:
#   - ничего не меняется, если ни у root, ни у ADMIN_USER нет ни одного ключа;
#   - вход root закрывается только после `gornitsa-ssh ok` — доказательства, что вход владельца
#     по ключу и sudo уже работают;
#   - новый конфиг проверяется `sshd -t`, не прошёл — возвращается прежний; открытые сессии
#     не рвутся (reload, а не restart);
#   - выключить всё это: touch /etc/gornitsa/ssh-hardening-off && gornitsa-ssh.

set -euo pipefail

ADMIN_USER="${ADMIN_USER:-$(cat /etc/gornitsa/ssh-admin 2>/dev/null || echo gornitsa)}"
CONF=/etc/ssh/sshd_config.d/00-gornitsa.conf   # 00- — раньше 50-cloud-init.conf: в sshd побеждает первое значение
STATE=/etc/gornitsa
OK="${STATE}/ssh-admin-ok"
OFF="${STATE}/ssh-hardening-off"

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: sudo gornitsa-ssh${1:+ $1}" >&2
  exit 1
fi
install -d -m 755 "$STATE"

has_keys() {   # у пользователя есть хотя бы один читаемый ключ
  local home
  home="$(getent passwd "$1" | cut -d: -f6)"
  [[ -n "$home" && -s "$home/.ssh/authorized_keys" ]] && ssh-keygen -l -f "$home/.ssh/authorized_keys" >/dev/null 2>&1
}

if [[ "${1:-}" == ok ]]; then
  # Доказательство: у ADMIN_USER сейчас открыта SSH-сессия (пароли уже выключены, значит — по ключу),
  # и он дошёл сюда через sudo.
  if [[ "${SUDO_USER:-}" != "$ADMIN_USER" ]]; then
    echo "Запустите из SSH-сессии пользователя ${ADMIN_USER}: ssh ${ADMIN_USER}@<сервер>, затем sudo gornitsa-ssh ok" >&2
    exit 1
  fi
  # процесс сессии — «sshd: имя@pts/0» (OpenSSH 9.6) или sshd-session (новее) от имени пользователя
  if ! pgrep -u "$ADMIN_USER" -f '^sshd' >/dev/null; then
    echo "Не вижу SSH-сессии ${ADMIN_USER}. Войдите по SSH (не через консоль панели) и повторите." >&2
    exit 1
  fi
  if ! grep -q '^PasswordAuthentication no' "$CONF" 2>/dev/null; then
    echo "Сначала основная настройка: sudo gornitsa-ssh (или deploy/setup-server.sh)" >&2
    exit 1
  fi
  date -Iseconds > "$OK"
  echo "Вход владельца проверен — закрываю вход root."
fi

if [[ -f "$OFF" ]]; then
  if [[ -f "$CONF" ]]; then
    rm -f "$CONF"
    sshd -t && { systemctl is-active --quiet ssh && systemctl reload ssh || true; }
  fi
  echo "SSH: усиление выключено ($OFF) — настройки sshd как у системы"
  exit 0
fi

if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
  echo "SSH: в /etc/ssh/sshd_config нет «Include /etc/ssh/sshd_config.d/*.conf» — ничего не меняю" >&2
  exit 0
fi
if ! has_keys root && ! has_keys "$ADMIN_USER"; then
  echo "SSH: ни у root, ни у ${ADMIN_USER} нет SSH-ключей — пароли НЕ выключаю, чтобы не потерять доступ." >&2
  echo "     Добавьте ключ (ssh-copy-id root@<сервер>) и запустите sudo gornitsa-ssh ещё раз." >&2
  exit 0
fi

ROOT_LOGIN=prohibit-password
ROOT_NOTE="root входит только по ключу, пока владелец не проверил свой вход (gornitsa-ssh ok)"
if [[ -f "$OK" ]] && has_keys "$ADMIN_USER"; then
  ROOT_LOGIN=no
  ROOT_NOTE="root не входит; владелец входит как ${ADMIN_USER} и пользуется sudo"
fi

tmp="$(mktemp)"
cat > "$tmp" <<CONF
# Вход на сервер: только по ключам; ${ROOT_NOTE}.
# Файл пишет /usr/local/sbin/gornitsa-ssh (репозиторий gornitsagames, deploy/ssh.sh) — правки здесь затрутся.
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PermitRootLogin ${ROOT_LOGIN}
MaxAuthTries 4
LoginGraceTime 30
CONF
if [[ -f "$CONF" ]] && cmp -s "$tmp" "$CONF"; then
  rm -f "$tmp"
  echo "SSH: только ключи; root — ${ROOT_LOGIN} (без изменений)"
  exit 0
fi
old=""
if [[ -f "$CONF" ]]; then old="$(mktemp)"; cp -p "$CONF" "$old"; fi
install -m 644 "$tmp" "$CONF"
rm -f "$tmp"
install -d -m 755 /run/sshd   # без неё sshd -t не проходит, когда sshd запускается по сокету
if ! sshd -t; then
  if [[ -n "$old" ]]; then mv -f "$old" "$CONF"; else rm -f "$CONF"; fi
  echo "SSH: новый конфиг не прошёл sshd -t — оставил прежний" >&2
  exit 1
fi
rm -f "$old"
# Ubuntu 24.04 запускает sshd по сокету: тогда каждое новое подключение и так читает свежий конфиг.
if systemctl is-active --quiet ssh; then systemctl reload ssh; fi
echo "SSH: только ключи; root — ${ROOT_LOGIN}"
if [[ "$ROOT_LOGIN" != no ]]; then
  echo "     Дальше: НЕ закрывая эту сессию, войдите в новом окне: ssh ${ADMIN_USER}@<сервер>,"
  echo "     проверьте sudo whoami (ответ — root) и там же: sudo gornitsa-ssh ok — тогда вход root закроется."
fi
