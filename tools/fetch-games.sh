#!/usr/bin/env bash
# Забирает папку store/ с main каждой игры из tools/games.json в games/<игра>/ (ADR студии 0015).
# Остальные файлы игр не скачиваются. Закрытые репозитории — токеном из GAMES_READ_TOKEN
# (fine-grained, только чтение содержимого nardy, votchina и skazy); без токена или без права
# на репозиторий он пропускается, и страница игры на сайте остаётся прежней.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf games
mkdir games

list=$(python3 -c 'import json
for g in json.load(open("tools/games.json"))["games"]:
    print(g["slug"], g["repo"], "private" if g.get("private") else "public")')

while read -r slug repo kind; do
  auth=()
  if [[ $kind == private ]]; then
    if [[ -z "${GAMES_READ_TOKEN:-}" ]]; then
      echo "::warning::$slug: нет GAMES_READ_TOKEN — закрытый $repo пропущен"
      continue
    fi
    basic=$(printf 'x-access-token:%s' "$GAMES_READ_TOKEN" | base64 -w0)
    echo "::add-mask::$basic"
    auth=(-c "http.https://github.com/.extraheader=AUTHORIZATION: basic $basic")
  fi
  dir="games/$slug"
  if git "${auth[@]}" clone -q --depth 1 --filter=blob:none --no-checkout "https://github.com/$repo.git" "$dir" \
    && git "${auth[@]}" -C "$dir" sparse-checkout set --no-cone '/store/' \
    && git "${auth[@]}" -C "$dir" checkout -q; then
    echo "$slug: $(git -C "$dir" rev-parse --short HEAD), файлов в store/: $(git -C "$dir" ls-files store | wc -l)"
  else
    echo "::warning::$slug: не удалось забрать $repo"
    rm -rf "$dir"
  fi
done <<< "$list"
