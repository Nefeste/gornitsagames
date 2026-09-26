#!/usr/bin/env bash
# votchina-backup (таймер votchina-backup.timer, раз в сутки; от пользователя votchina):
# копия базы средствами SQLite (безопасно при работающем сервере), хранится семь дней.
# Восстановить: systemctl stop votchina; gunzip -c <копия>.db.gz > /var/lib/votchina/votchina.db;
# chown votchina: /var/lib/votchina/votchina.db; rm -f /var/lib/votchina/votchina.db-{wal,shm}; systemctl start votchina

set -euo pipefail
umask 077

DB=/var/lib/votchina/votchina.db
OUT=/var/backups/votchina

[[ -f "$DB" ]] || exit 0
F="$OUT/votchina-$(date -u +%Y%m%d).db"
rm -f "$F.tmp"
sqlite3 "$DB" ".backup '$F.tmp'"
[[ "$(sqlite3 "$F.tmp" 'PRAGMA integrity_check')" == ok ]] || { echo "Копия $F не прошла проверку" >&2; rm -f "$F.tmp"; exit 1; }
mv -f "$F.tmp" "$F"
gzip -f "$F"
find "$OUT" -maxdepth 1 -name 'votchina-*.db.gz' -mtime +6 -delete
echo "Копия базы: $F.gz ($(du -h "$F.gz" | cut -f1))"
