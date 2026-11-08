#!/usr/bin/env bash
# durak-pull (таймер durak-pull.timer, каждые 2 минуты; ставит deploy/durak/setup.sh).
#
#   1. HTTPS для durak.gornitsa.games, как только DNS укажет на сервер (durak-nginx).
#   2. Ветка `vps` репозитория Nefeste/durak — сборка сервера, прошедшая тесты в CI (server.yml).
#      Новая — в /opt/durak/releases/<коммит>, ссылка current, перезапуск службы. Не ответила
#      на /v1/ping — возвращается прежняя, а эта сборка больше не пробуется.
#
# Репозиторий закрытый: читаем его ключом /etc/durak/deploy_key (deploy key, только чтение).
# Пока ключ не добавлен в репозиторий, скрипт просто ждёт.

set -euo pipefail
umask 022

REPO="${DURAK_REPO:-git@github.com:Nefeste/durak.git}"   # DURAK_REPO — только для проверки скрипта
BASE=/opt/durak
STATE=/var/lib/durak-deploy
PING="http://127.0.0.1:8792/v1/ping"
GIT=(git --git-dir="$BASE/repo.git")
export GIT_SSH_COMMAND="ssh -i /etc/durak/deploy_key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/etc/durak/known_hosts -o ConnectTimeout=20"

say_once() {   # $1 — ключ состояния, $2 — сообщение: пишет в журнал один раз, пока состояние не сменится
  if [[ "$(cat "$STATE/said" 2>/dev/null)" != "$1" ]]; then echo "$2"; echo "$1" > "$STATE/said"; fi
}

healthy() {   # служба отвечает на /v1/ping (до 30 секунд)
  for _ in $(seq 1 30); do
    curl -fsS -m 2 -o /dev/null "$PING" 2>/dev/null && return 0
    sleep 1
  done
  return 1
}

/usr/local/sbin/durak-nginx || echo "nginx: не вышло, попробую через 2 минуты"

[[ -d "$BASE/repo.git" ]] || git init -q --bare "$BASE/repo.git"
if ! HEADS="$(git ls-remote "$REPO" refs/heads/vps 2>&1)"; then
  say_once no-access "Нет доступа к $REPO — ждём ключ (deploy key) в репозитории. Ответ: ${HEADS//$'\n'/ }"
  exit 0
fi
VPS="$(awk '$2 == "refs/heads/vps" {print $1}' <<< "$HEADS")"
if [[ -z "$VPS" ]]; then
  say_once no-build "Доступ к репозиторию есть; ветки vps ещё нет — ждём слияния в main."
  exit 0
fi

if [[ "$VPS" == "$(cat "$STATE/build" 2>/dev/null)" || "$VPS" == "$(cat "$STATE/build-bad" 2>/dev/null)" ]]; then
  exit 0
fi

"${GIT[@]}" fetch -q --depth 1 "$REPO" "+refs/heads/vps:refs/heads/vps"
REL="$BASE/releases/$VPS"
rm -rf "$REL.tmp"
mkdir -p "$REL.tmp"
"${GIT[@]}" archive "$VPS" | tar -x -C "$REL.tmp"
for f in server.js build.json; do
  [[ -e "$REL.tmp/$f" ]] || { echo "В сборке ${VPS:0:7} нет $f — пропускаю её"; echo "$VPS" > "$STATE/build-bad"; rm -rf "$REL.tmp"; exit 1; }
done
rm -rf "$REL"
mv "$REL.tmp" "$REL"
PREV="$(readlink "$BASE/current" 2>/dev/null || true)"
ln -sfn "$REL" "$BASE/current.new"
mv -T "$BASE/current.new" "$BASE/current"
systemctl restart durak
if healthy; then
  echo "$VPS" > "$STATE/build"
  echo "Сервер: сборка ${VPS:0:7} ($(sed -n 's/.*"commit": *"\([0-9a-f]\{7\}\).*/main \1/p' "$REL/build.json" 2>/dev/null))"
  # Храним три последние сборки.
  find "$BASE/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn | awk 'NR > 3 {print $2}' |
    while read -r old; do if [[ "$old" != "$(readlink "$BASE/current")" ]]; then rm -rf "$old"; fi; done
else
  echo "Сборка ${VPS:0:7} не ответила на /v1/ping — возвращаю прежнюю"
  journalctl -u durak -n 30 --no-pager || true
  echo "$VPS" > "$STATE/build-bad"
  if [[ -n "$PREV" && -d "$PREV" ]]; then
    ln -sfn "$PREV" "$BASE/current.new"
    mv -T "$BASE/current.new" "$BASE/current"
    systemctl restart durak
  fi
  exit 1
fi
