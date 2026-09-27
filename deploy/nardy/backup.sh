#!/usr/bin/env bash
# nardy-backup (таймер nardy-backup.timer, раз в сутки; от пользователя nardy):
# копия базы средствами SQLite (безопасно при работающем сервере), хранится семь дней.
# Восстановить: systemctl stop nardy; gunzip -c <копия>.db.gz > /var/lib/nardy/nardy.db;
# chown nardy: /var/lib/nardy/nardy.db; rm -f /var/lib/nardy/nardy.db-{wal,shm}; systemctl start nardy

set -euo pipefail
umask 077

DB=/var/lib/nardy/nardy.db
OUT=/var/backups/nardy

[[ -f "$DB" ]] || exit 0
F="$OUT/nardy-$(date -u +%Y%m%d).db"
rm -f "$F.tmp"
sqlite3 "$DB" ".backup '$F.tmp'"
[[ "$(sqlite3 "$F.tmp" 'PRAGMA integrity_check')" == ok ]] || { echo "Копия $F не прошла проверку" >&2; rm -f "$F.tmp"; exit 1; }
mv -f "$F.tmp" "$F"
gzip -f "$F"
find "$OUT" -maxdepth 1 -name 'nardy-*.db.gz' -mtime +6 -delete
echo "Копия базы: $F.gz ($(du -h "$F.gz" | cut -f1))"
