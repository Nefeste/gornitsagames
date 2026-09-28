#!/usr/bin/env bash
# skazy-restore-check (таймер skazy-restore-check.timer, раз в месяц; от пользователя skazy):
# «непроверенная копия — не копия» (docs/05-process.md «Сказов», раздел «Сервер»).
# Поднимает последнюю копию во временную папку, проверяет целостность, что в ней есть все
# таблицы живой базы, и пишет число строк: в копии и в базе. Строк не обязано быть поровну:
# за сутки база выросла, а уборка сроков хранения (retention.ts) и удаление профилей что-то
# стёрли, — поэтому числа только записываются в журнал, а не сравниваются.
# Итог — в журнале: journalctl -u skazy-restore-check -n 30

set -euo pipefail
umask 077

DB=/var/lib/skazy/skazy.db
OUT=/var/backups/skazy

LAST="$(find "$OUT" -maxdepth 1 -name 'skazy-*.db.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk 'NR == 1 {print $2}')"
if [[ -z "$LAST" ]]; then
  [[ -f "$DB" ]] || { echo "Базы и копий ещё нет — проверять нечего"; exit 0; }
  echo "База есть, а копий нет — проверьте skazy-backup.timer" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
gunzip -c "$LAST" > "$TMP/restore.db"
[[ "$(sqlite3 "$TMP/restore.db" 'PRAGMA integrity_check')" == ok ]] || { echo "Копия $LAST не восстанавливается: integrity_check" >&2; exit 1; }

TABLES="$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")"
BAD=0
while read -r t; do
  [[ -n "$t" ]] || continue
  live="$(sqlite3 "$DB" "SELECT count(*) FROM \"$t\"")"
  if ! copy="$(sqlite3 "$TMP/restore.db" "SELECT count(*) FROM \"$t\"" 2>/dev/null)"; then
    echo "В копии нет таблицы $t" >&2; BAD=1; continue
  fi
  echo "  $t: в копии $copy, в базе $live"
done <<< "$TABLES"
(( BAD == 0 )) || exit 1
echo "Копия $(basename "$LAST") восстанавливается: целостность в порядке, таблиц — $(wc -l <<< "$TABLES")"
