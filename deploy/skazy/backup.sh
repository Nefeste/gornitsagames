#!/usr/bin/env bash
# skazy-backup (таймер skazy-backup.timer, раз в сутки; от пользователя skazy):
# копия базы средствами SQLite (безопасно при работающем сервере), хранится семь дней.
# Восстановить: systemctl stop skazy; gunzip -c <копия>.db.gz > /var/lib/skazy/skazy.db;
# chown skazy: /var/lib/skazy/skazy.db; rm -f /var/lib/skazy/skazy.db-{wal,shm}; systemctl start skazy

set -euo pipefail
umask 077

DB=/var/lib/skazy/skazy.db
OUT=/var/backups/skazy

[[ -f "$DB" ]] || exit 0
F="$OUT/skazy-$(date -u +%Y%m%d).db"
rm -f "$F.tmp"
sqlite3 "$DB" ".backup '$F.tmp'"
[[ "$(sqlite3 "$F.tmp" 'PRAGMA integrity_check')" == ok ]] || { echo "Копия $F не прошла проверку" >&2; rm -f "$F.tmp"; exit 1; }
mv -f "$F.tmp" "$F"
gzip -f "$F"
find "$OUT" -maxdepth 1 -name 'skazy-*.db.gz' -mtime +6 -delete
echo "Копия базы: $F.gz ($(du -h "$F.gz" | cut -f1))"
