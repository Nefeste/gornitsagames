#!/usr/bin/env bash
# uzory-stats (таймер uzory-stats.timer, раз в сутки в 00:20 по Москве; ставит deploy/uzory/setup.sh):
# свёртка журнала каталога «Узоров» в суммы — /srv/gornitsa/uzory/stats/stats.csv (server/stats/README.md
# в репозитории Nefeste/uzory, ADR 0012 «Узоров»). Скрипт fold.ts приходит в ветке packs — его кладёт
# uzory-packs. Журнал /var/log/uzory/catalog.log пишет nginx (uzory-nginx) без адресов; свёртка сама
# держит в нём строки семи последних дней, поэтому logrotate его не трогает.
# Нужен bun — тот же, что у «Нард» (/opt/bun/<версия>/bun, deploy/nardy/setup.sh), или bun в PATH.

set -euo pipefail

FOLD=/srv/gornitsa/uzory/stats/fold.ts
LOG=/var/log/uzory/catalog.log
CSV=/srv/gornitsa/uzory/stats/stats.csv

if [[ ! -f "$FOLD" ]]; then echo "uzory-stats: fold.ts ещё нет — каталог не выложен"; exit 0; fi
if [[ ! -f "$LOG" ]]; then echo "uzory-stats: журнала каталога ещё нет"; exit 0; fi
BUN="$(command -v bun || true)"
if [[ -z "$BUN" ]]; then
  # самая новая версия из /opt/bun/<версия>/bun
  shopt -s nullglob
  found=(/opt/bun/*/bun)
  shopt -u nullglob
  if (( ${#found[@]} )); then BUN="$(printf '%s\n' "${found[@]}" | sort -V | tail -n1)"; fi
fi
if [[ ! -x "$BUN" ]]; then
  echo "uzory-stats: нет bun (его ставит deploy/nardy/setup.sh) — журнал копится, свёртки нет" >&2
  exit 1
fi
"$BUN" "$FOLD" --log "$LOG" --csv "$CSV"
# журнал переписан — nginx открывает файл заново
nginx -s reopen
