#!/usr/bin/env bash
# Забирает папку store/ с main каждой игры из tools/games.json в games/<игра>/ (ADR студии 0015).
# Остальные файлы игр не скачиваются. Закрытые репозитории — токеном из GAMES_READ_TOKEN
# (fine-grained, только чтение содержимого nardy, votchina, skazy и durak); без токена или без права
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
    why=""
    if [[ $kind == private ]]; then
      # почему не пустили: 401 — токен не принят (истёк, отозван, другое значение), 404/403 — нет права на репозиторий
      code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $GAMES_READ_TOKEN" "https://api.github.com/repos/$repo" || true)
      case $code in
        401) why=" — GitHub не принял GAMES_READ_TOKEN (истёк или отозван): новый токен — в секрет, docs/game-pages.md" ;;
        403|404) why=" — у GAMES_READ_TOKEN нет права на $repo: Repository access токена, docs/game-pages.md" ;;
        *) why=" (ответ GitHub API: $code)" ;;
      esac
    fi
    echo "::warning::$slug: не удалось забрать $repo$why"
    rm -rf "$dir"
  fi
done <<< "$list"
