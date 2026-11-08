#!/usr/bin/env bash
# durak-backup (таймер durak-backup.timer, раз в сутки; от пользователя durak):
# копия базы средствами SQLite (безопасно при работающем сервере), хранится семь дней.
# Восстановить: systemctl stop durak; gunzip -c <копия>.db.gz > /var/lib/durak/durak.db;
# chown durak: /var/lib/durak/durak.db; rm -f /var/lib/durak/durak.db-{wal,shm}; systemctl start durak

set -euo pipefail
umask 077

DB=/var/lib/durak/durak.db
OUT=/var/backups/durak

[[ -f "$DB" ]] || exit 0
F="$OUT/durak-$(date -u +%Y%m%d).db"
rm -f "$F.tmp"
sqlite3 "$DB" ".backup '$F.tmp'"
[[ "$(sqlite3 "$F.tmp" 'PRAGMA integrity_check')" == ok ]] || { echo "Копия $F не прошла проверку" >&2; rm -f "$F.tmp"; exit 1; }
mv -f "$F.tmp" "$F"
gzip -f "$F"
find "$OUT" -maxdepth 1 -name 'durak-*.db.gz' -mtime +6 -delete
echo "Копия базы: $F.gz ($(du -h "$F.gz" | cut -f1))"
