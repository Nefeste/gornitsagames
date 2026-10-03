#!/usr/bin/env bash
# Забор копий баз «Горницы» на компьютер владельца — macOS (docs/backup.md, шаг 4).
# Запускает launchd раз в сутки (games.gornitsa.backup.plist); вручную: bash ~/Gornitsa/pull-backup.sh
# Забирает папки копий за последние 3 дня (rclone copy --max-age 3d; уже забранное не качает
# повторно), а свои папки старше 14 дней удаляет: удалённый профиль игрока не должен жить в копиях
# дольше, чем обещает политика (удаление в течение 30 дней).
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # rclone из Homebrew

DEST="${DEST:-$HOME/GornitsaBackup}"   # не в «Рабочем столе» и «Документах», если они в iCloud
REMOTE="${REMOTE:-gornitsa-backup:out}"
KEEP_DAYS="${KEEP_DAYS:-14}"
mkdir -p "$DEST"
LOG="$DEST/pull.log"

rclone copy "$REMOTE" "$DEST" --max-age 3d --log-file "$LOG" --log-level INFO

cutoff="$(date -v-"${KEEP_DAYS}"d +%F)"
for d in "$DEST"/????-??-??; do
  [[ -d "$d" ]] || continue
  if [[ "$(basename "$d")" < "$cutoff" ]]; then
    rm -rf "$d"
    echo "$(date '+%F %T') удалена старая копия $(basename "$d")" >> "$LOG"
  fi
done
