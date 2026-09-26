#!/usr/bin/env bash
# votchina-pull (таймер votchina-pull.timer, каждые 2 минуты; ставит deploy/votchina/setup.sh).
#
#   1. HTTPS для votchina.gornitsa.games, как только DNS укажет на сервер (votchina-nginx).
#   2. Ветка `vps` репозитория Nefeste/votchina — сборка сервера, прошедшая сквозной тест в CI.
#      Новая — в /opt/votchina/releases/<коммит>, ссылка current, перезапуск службы. Не ответила
#      на /v1/ping — возвращается прежняя, а эта сборка больше не пробуется.
#   3. Ветка `vps-import` — выгрузка D1, зашифрованная ключом этой машины (задание migrate.yml).
#      Новая — расшифровка, `serve.mjs import` в новый файл, копия текущей базы, подмена, запуск;
#      метка выгрузки ложится в votchina.db.mark, и /v1/ping отвечает ею в x-votchina-data.
#
# Репозиторий закрытый: читаем его ключом /etc/votchina/deploy_key (deploy key, только чтение).
# Пока ключ не добавлен в репозиторий, скрипт просто ждёт.

set -euo pipefail
umask 022

REPO="${VOTCHINA_REPO:-git@github.com:Nefeste/votchina.git}"   # VOTCHINA_REPO — только для проверки скрипта
BASE=/opt/votchina
STATE=/var/lib/votchina-deploy
DB=/var/lib/votchina/votchina.db
BACKUPS=/var/backups/votchina
PING="http://127.0.0.1:8787/v1/ping"
GIT=(git --git-dir="$BASE/repo.git")
# shellcheck source=/dev/null
source /etc/votchina/node   # NODE, FLAGS
export GIT_SSH_COMMAND="ssh -i /etc/votchina/deploy_key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/etc/votchina/known_hosts -o ConnectTimeout=20"

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

/usr/local/sbin/votchina-nginx || echo "nginx: не вышло, попробую через 2 минуты"

[[ -d "$BASE/repo.git" ]] || git init -q --bare "$BASE/repo.git"
if ! HEADS="$(git ls-remote "$REPO" refs/heads/vps refs/heads/vps-import 2>&1)"; then
  say_once no-access "Нет доступа к $REPO — ждём ключ (deploy key) в репозитории. Ответ: ${HEADS//$'\n'/ }"
  exit 0
fi
VPS="$(awk '$2 == "refs/heads/vps" {print $1}' <<< "$HEADS")"
IMP="$(awk '$2 == "refs/heads/vps-import" {print $1}' <<< "$HEADS")"
if [[ -z "$VPS" ]]; then
  say_once no-build "Доступ к репозиторию есть; ветки vps ещё нет — ждём слияния в main."
  exit 0
fi

# ——— сборка ———
if [[ "$VPS" != "$(cat "$STATE/build" 2>/dev/null)" && "$VPS" != "$(cat "$STATE/build-bad" 2>/dev/null)" ]]; then
  "${GIT[@]}" fetch -q --depth 1 "$REPO" "+refs/heads/vps:refs/heads/vps"
  REL="$BASE/releases/$VPS"
  rm -rf "$REL.tmp"
  mkdir -p "$REL.tmp"
  "${GIT[@]}" archive "$VPS" | tar -x -C "$REL.tmp"
  for f in worker.mjs serve.mjs d1.mjs vars.json migrations; do
    [[ -e "$REL.tmp/$f" ]] || { echo "В сборке ${VPS:0:7} нет $f — пропускаю её"; echo "$VPS" > "$STATE/build-bad"; rm -rf "$REL.tmp"; exit 1; }
  done
  rm -rf "$REL"
  mv "$REL.tmp" "$REL"
  PREV="$(readlink "$BASE/current" 2>/dev/null || true)"
  ln -sfn "$REL" "$BASE/current.new"
  mv -T "$BASE/current.new" "$BASE/current"
  systemctl restart votchina
  if healthy; then
    echo "$VPS" > "$STATE/build"
    echo "Сервер: сборка ${VPS:0:7} ($(sed -n 's/.*"commit": *"\([0-9a-f]\{7\}\).*/main \1/p' "$REL/build.json" 2>/dev/null))"
    # Храним три последние сборки.
    find "$BASE/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn | awk 'NR > 3 {print $2}' |
      while read -r old; do if [[ "$old" != "$(readlink "$BASE/current")" ]]; then rm -rf "$old"; fi; done
  else
    echo "Сборка ${VPS:0:7} не ответила на /v1/ping — возвращаю прежнюю"
    journalctl -u votchina -n 30 --no-pager || true
    echo "$VPS" > "$STATE/build-bad"
    if [[ -n "$PREV" && -d "$PREV" ]]; then
      ln -sfn "$PREV" "$BASE/current.new"
      mv -T "$BASE/current.new" "$BASE/current"
      systemctl restart votchina
    fi
    exit 1
  fi
fi

# ——— выгрузка базы ———
if [[ -n "$IMP" && "$IMP" != "$(cat "$STATE/import" 2>/dev/null)" && -e "$BASE/current/serve.mjs" ]]; then
  echo "$IMP" > "$STATE/import"   # одна попытка на выгрузку: не вышло — задание переезда откатит воркер
  "${GIT[@]}" fetch -q --depth 1 "$REPO" "+refs/heads/vps-import:refs/heads/vps-import"
  W=/var/lib/votchina/import
  rm -rf "$W"
  install -d -m 700 -o votchina -g votchina "$W"
  trap 'shred -u "$W/dump.sql" 2>/dev/null || true; rm -rf "$W"' EXIT
  "${GIT[@]}" archive "$IMP" dump.sql.age dump.id | tar -x -C "$W"
  ID="$(tr -d '\r\n\t ' < "$W/dump.id")"
  if [[ ! "$ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Выгрузка ${IMP:0:7}: странная метка — пропускаю"
    exit 1
  fi
  if [[ "$ID" == "$(cat "$DB.mark" 2>/dev/null)" ]]; then
    echo "Выгрузка $ID уже загружена"
    exit 0
  fi
  echo "Выгрузка $ID: расшифровываю и загружаю в новую базу"
  age -d -i /etc/votchina/age.key -o "$W/dump.sql" "$W/dump.sql.age"
  chown votchina:votchina "$W/dump.sql"
  chmod 600 "$W/dump.sql"
  rm -f "$DB.new" "$DB.new-wal" "$DB.new-shm"
  # shellcheck disable=SC2086
  if ! runuser -u votchina -- env VOTCHINA_DB="$DB.new" "$NODE" $FLAGS "$BASE/current/serve.mjs" import "$W/dump.sql"; then
    echo "Выгрузка $ID не загрузилась — база прежняя"
    rm -f "$DB.new" "$DB.new-wal" "$DB.new-shm"
    exit 1
  fi
  systemctl stop votchina
  if [[ -f "$DB" ]]; then
    runuser -u votchina -- sqlite3 "$DB" ".backup '$BACKUPS/before-import-$ID.db'" &&
      runuser -u votchina -- gzip -f "$BACKUPS/before-import-$ID.db" || echo "Копию прежней базы снять не вышло"
    for s in "" -wal -shm; do
      if [[ -e "$DB$s" ]]; then mv -f "$DB$s" "$DB.old$s"; fi
    done
  fi
  mv "$DB.new" "$DB"
  echo "$ID" > "$DB.mark"
  chown votchina:votchina "$DB" "$DB.mark"
  systemctl start votchina
  if healthy && [[ "$(curl -fsS -m 3 -D - -o /dev/null "$PING" | tr -d '\r' | sed -n 's/^x-votchina-data: //Ip')" == "$ID" ]]; then
    echo "База загружена из выгрузки $ID, сервер отвечает"
  else
    echo "Выгрузка $ID загружена, но сервер не отвечает меткой"
    journalctl -u votchina -n 30 --no-pager || true
    exit 1
  fi
fi
