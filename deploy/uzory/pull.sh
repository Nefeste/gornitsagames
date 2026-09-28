#!/usr/bin/env bash
# uzory-pull (таймер uzory-pull.timer, каждые 5 минут; ставит deploy/uzory/setup.sh).
#
#   1. /uzory/test/ в nginx сайта (uzory-nginx): пароль, HTTPS, заголовки.
#   2. Ветка `vps` открытого репозитория Nefeste/uzory — веб-сборка, прошедшая сценарий Playwright
#      в CI (android.yml, «Веб-версия для сайта»), зашифрованная открытым ключом этой машины (age):
#      в ней картинки «только для проверки», а ветку видят все. Новая — расшифровка
#      в /opt/uzory/releases/<коммит>/test, сжатые копии .gz для nginx, ссылка current.
#      Не расшифровалась или неполная — остаётся прежняя, а эта сборка больше не пробуется.
#
# Репозиторий открытый: ключ доступа не нужен.

set -euo pipefail
umask 022

REPO="${UZORY_REPO:-https://github.com/Nefeste/uzory.git}"   # UZORY_REPO — только для проверки скрипта
BASE=/opt/uzory
STATE=/var/lib/uzory-deploy
KEY=/etc/uzory/age.key
GIT=(git --git-dir="$BASE/repo.git")

say_once() {   # $1 — ключ состояния, $2 — сообщение: пишет в журнал один раз, пока состояние не сменится
  if [[ "$(cat "$STATE/said" 2>/dev/null)" != "$1" ]]; then echo "$2"; echo "$1" > "$STATE/said"; fi
}

/usr/local/sbin/uzory-nginx || echo "nginx: не вышло, попробую через 5 минут"

[[ -d "$BASE/repo.git" ]] || git init -q --bare "$BASE/repo.git"
if ! HEADS="$(git ls-remote "$REPO" refs/heads/vps 2>&1)"; then
  say_once no-access "Не достучался до $REPO: ${HEADS//$'\n'/ }"
  exit 0
fi
VPS="$(awk '$2 == "refs/heads/vps" {print $1}' <<< "$HEADS")"
if [[ -z "$VPS" ]]; then
  say_once no-build "Ветки vps в $REPO ещё нет — ждём слияния в main «Узоров»."
  exit 0
fi
if [[ "$VPS" == "$(cat "$STATE/build" 2>/dev/null)" || "$VPS" == "$(cat "$STATE/build-bad" 2>/dev/null)" ]]; then
  exit 0
fi

REL="$BASE/releases/$VPS"
bad() {   # сборка не годится: остаётся прежняя, эта больше не пробуется
  echo "Сборка ${VPS:0:7}: $1 — пропускаю её"
  echo "$VPS" > "$STATE/build-bad"
  rm -rf "$REL.tmp"
  exit 1
}

"${GIT[@]}" fetch -q --depth 1 "$REPO" "+refs/heads/vps:refs/heads/vps"
rm -rf "$REL.tmp"
mkdir -p "$REL.tmp/test"
"${GIT[@]}" archive "$VPS" build.json test.tar.gz.age | tar -x -C "$REL.tmp" || bad "нет build.json или test.tar.gz.age"
age -d -i "$KEY" "$REL.tmp/test.tar.gz.age" | tar -xz --no-same-owner -C "$REL.tmp/test" ||
  bad "не расшифровалась ключом этой машины (CI шифровал ключом, который был до переустановки?)"
rm -f "$REL.tmp/test.tar.gz.age"
for f in test/index.html test/canvaskit.wasm build.json; do
  [[ -s "$REL.tmp/$f" ]] || bad "нет $f"
done
# сжатые копии: nginx отдаёт их сам (gzip_static) и не жмёт 12 МБ на каждый запрос
find "$REL.tmp/test" -type f \( -name '*.js' -o -name '*.wasm' -o -name '*.html' -o -name '*.json' -o -name '*.ttf' -o -name '*.ico' \) -exec gzip -k -9 -f {} +
chmod -R a+rX "$REL.tmp"
rm -rf "$REL"
mv "$REL.tmp" "$REL"
ln -sfn "$REL" "$BASE/current.new"
mv -T "$BASE/current.new" "$BASE/current"
echo "$VPS" > "$STATE/build"
echo "Веб-версия: сборка ${VPS:0:7} ($(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$REL/build.json" | head -n1), main $(sed -n 's/.*"commit": *"\([0-9a-f]\{7\}\).*/\1/p' "$REL/build.json" | head -n1))"

# Храним три последние сборки; старые коммиты ветки (каждый — без истории) — из репозитория.
find "$BASE/releases" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -rn | awk 'NR > 3 {print $2}' |
  while read -r old; do if [[ "$old" != "$(readlink "$BASE/current")" ]]; then rm -rf "$old"; fi; done
"${GIT[@]}" gc -q --prune=now 2>/dev/null || true
