#!/usr/bin/env bash
# Открывает или обновляет PR «Сайт: обновления игр» из того, что собрал tools/games.py
# (workflow «Страницы игр»). Ветка games/sync каждый раз собирается заново от main.
#   bash tools/games-pr.sh <отчёт games.py>
set -euo pipefail
cd "$(dirname "$0")/.."
report=${1:?нужен отчёт tools/games.py}
branch=games/sync
title="Сайт: обновления игр"

open=$(gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty')

git add -A src site/assets/games
[[ -f games.lock.json ]] && git add games.lock.json
if git diff --cached --quiet; then
  echo "Страницы игр совпадают с main — PR не нужен"
  if [[ -n $open ]]; then
    gh pr close "$open" --delete-branch --comment "Страницы игр снова совпадают с main — закрываю."
  fi
  exit 0
fi

git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -q -m "$title" -m "$(cat "$report")"
git push -q -f origin "HEAD:refs/heads/$branch"

body="Страницы игр из \`store/site/\` их репозиториев (ADR студии 0015). Собрал workflow «Страницы игр» $(date -u '+%d.%m.%Y %H:%M') UTC; до слияния PR обновляется сам каждую ночь.

$(cat "$report")

\`python3 build.py && python3 tools/check.py\` — без ошибок."

if [[ -n $open ]]; then
  gh pr edit "$open" --body "$body"
  echo "PR #$open обновлён"
else
  gh pr create --base main --head "$branch" --title "$title" --body "$body"
fi
