#!/usr/bin/env bash
# skazy-pull (таймер skazy-pull.timer, каждые 2 минуты; ставит deploy/skazy/setup.sh).
# Как nardy-pull (deploy/nardy/pull.sh), с именами «Сказов» и портом 8791.
#
#   1. HTTPS для skazy.gornitsa.games, как только DNS укажет на сервер (skazy-nginx).
#   2. Ветка `vps` репозитория Nefeste/skazy — сборка сервера, прошедшая тесты в CI (server.yml);
#      рядом с server.js может лежать cert.sha256 — отпечаток для App Links.
#      Новая — в /opt/skazy/releases/<коммит>, ссылка current, перезапуск службы. Не ответила
#      на /v1/ping — возвращается прежняя, а эта сборка больше не пробуется.
#
# Читаем репозиторий ключом /etc/skazy/deploy_key (deploy key, только чтение) — так же, открыт
# репозиторий или закрыт. Пока ключ не добавлен в репозиторий, скрипт просто ждёт.

set -euo pipefail
umask 022

REPO="${SKAZY_REPO:-git@github.com:Nefeste/skazy.git}"   # SKAZY_REPO — только для проверки скрипта
BASE=/opt/skazy
STATE=/var/lib/skazy-deploy
PING="http://127.0.0.1:8791/v1/ping"
GIT=(git --git-dir="$BASE/repo.git")
export GIT_SSH_COMMAND="ssh -i /etc/skazy/deploy_key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/etc/skazy/known_hosts -o ConnectTimeout=20"

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

/usr/local/sbin/skazy-nginx || echo "nginx: не вышло, попробую через 2 минуты"

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
systemctl restart skazy
if healthy; then
  echo "$VPS" > "$STATE/build"
  echo "Сервер: сборка ${VPS:0:7} ($(sed -n 's/.*"commit": *"\([0-9a-f]\{7\}\).*/main \1/p' "$REL/build.json" 2>/dev/null))"
  # Храним три последние сборки.
  find "$BASE/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn | awk 'NR > 3 {print $2}' |
    while read -r old; do if [[ "$old" != "$(readlink "$BASE/current")" ]]; then rm -rf "$old"; fi; done
else
  echo "Сборка ${VPS:0:7} не ответила на /v1/ping — возвращаю прежнюю"
  journalctl -u skazy -n 30 --no-pager || true
  echo "$VPS" > "$STATE/build-bad"
  if [[ -n "$PREV" && -d "$PREV" ]]; then
    ln -sfn "$PREV" "$BASE/current.new"
    mv -T "$BASE/current.new" "$BASE/current"
    systemctl restart skazy
  fi
  exit 1
fi
