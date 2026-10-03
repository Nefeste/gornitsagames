#!/usr/bin/env bash
# gornitsa-backup: снимок баз SQLite раз в сутки, сжатый и зашифрованный открытым ключом владельца
# (решение владельца №15; инструкция владельцу — docs/backup.md). Запускает gornitsa-backup.timer
# в 03:30 по Москве; вручную — sudo gornitsa-backup.
#
# Для каждой строки /etc/gornitsa-backup/targets.conf («имя путь»):
#   1. sqlite3 «.backup» от имени владельца файла базы — согласованный снимок без остановки службы
#      (и без файлов -wal/-shm от root рядом с базой);
#   2. PRAGMA integrity_check снимка;
#   3. gzip | age -R recipients.txt → /srv/backup/out/ГГГГ-ММ-ДД/<имя>.db.gz.age.
# Открытого снимка нигде не остаётся: он живёт во временной папке root и удаляется сразу.
# Без открытого ключа владельца (recipients.txt) копии не делаются вовсе — незашифрованных нет.
# manifest.json рядом: имя, размеры и sha256 снимка и файла, результат проверки. Копии — 14 дней.
# Состояние (без данных о людях) — /var/lib/gornitsa-backup/status.json; из него и журнала SFTP
# gornitsa-backup-status (status.py) раз в 10 минут считает тревоги для «Сторожа».

set -euo pipefail
umask 077

ETC=/etc/gornitsa-backup
TARGETS="${ETC}/targets.conf"
RECIPIENTS="${ETC}/recipients.txt"
OUT=/srv/backup/out
STATE=/var/lib/gornitsa-backup
KEEP_DAYS=14

DAY="$(TZ=Europe/Moscow date +%F)"
NOW="$(date -Iseconds)"
DEST="${OUT}/${DAY}"

status() {   # $1: ok | error | nokeys (копии не включены: нет ключа владельца), $2: пояснение
  python3 - "$1" "$2" "${STATE}/status.json" "${DEST}/manifest.json" "$NOW" <<'PY'
import json, os, sys
result, note, path, manifest, now = sys.argv[1:]
data = {"time": now, "result": result, "note": note, "dbs": []}
if os.path.exists(manifest):
    with open(manifest) as f:
        m = json.load(f)
    data["day"] = m["day"]
    data["dbs"] = [{"name": d["name"], "integrity": d["integrity"]} for d in m["dbs"]]
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=1)
os.chmod(tmp, 0o644)
os.replace(tmp, path)
PY
}

[[ $EUID -eq 0 ]] || { echo "Запустите от root: sudo gornitsa-backup" >&2; exit 1; }
install -d -m 755 "$STATE"

if ! grep -q '^age1' "$RECIPIENTS" 2>/dev/null; then
  echo "Нет открытого ключа age владельца в ${RECIPIENTS} — копии не делаю (sudo gornitsa-backup-keys)" >&2
  status nokeys "нет открытого ключа age владельца"
  exit 1
fi
if [[ ! -s "$TARGETS" ]]; then
  echo "Нет списка баз ${TARGETS}" >&2
  status error "нет списка баз"
  exit 1
fi

TMP="$(mktemp -d "${STATE}/tmp.XXXXXX")"
chmod 711 "$TMP"
trap 'rm -rf "$TMP"' EXIT
install -d -m 750 -o root -g backup "$DEST"

ENTRIES="${TMP}/entries.jsonl"
: > "$ENTRIES"
failed=0
while read -r name path _; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  if [[ ! "$name" =~ ^[a-z0-9_-]{1,32}$ ]]; then
    echo "targets.conf: имя «$name» — только латиница, цифры, - и _" >&2
    failed=1
    continue
  fi
  if [[ ! -f "$path" ]]; then
    echo "${name}: базы ${path} нет — пропускаю"
    printf '{"name":"%s","missing":true,"integrity":"нет файла"}\n' "$name" >> "$ENTRIES"
    continue
  fi
  owner="$(stat -c %U "$path")"
  work="${TMP}/${name}"
  install -d -m 700 -o "$owner" "$work"
  snap="${work}/${name}.db"
  if ! setpriv --reuid="$owner" --regid="$(stat -c %G "$path")" --init-groups \
       sqlite3 "$path" ".backup '${snap}'"; then
    echo "${name}: снимок не удался" >&2
    printf '{"name":"%s","integrity":"снимок не удался"}\n' "$name" >> "$ENTRIES"
    failed=1
    continue
  fi
  check="$(sqlite3 "$snap" 'PRAGMA integrity_check' 2>&1 | head -c 2000 || true)"
  [[ "$check" == ok ]] || failed=1
  enc="${DEST}/${name}.db.gz.age"
  if ! gzip -c -9 "$snap" | age -R "$RECIPIENTS" -o "${enc}.tmp"; then
    echo "${name}: сжатие или шифрование не удалось" >&2
    rm -f "${enc}.tmp"
    printf '{"name":"%s","integrity":"шифрование не удалось"}\n' "$name" >> "$ENTRIES"
    failed=1
    continue
  fi
  mv -f "${enc}.tmp" "$enc"
  chown root:backup "$enc"
  chmod 640 "$enc"
  python3 - "$name" "$snap" "$enc" "$check" >> "$ENTRIES" <<'PY'
import hashlib, json, os, sys
name, snap, enc, check = sys.argv[1:]
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()
print(json.dumps({"name": name, "file": os.path.basename(enc),
                  "db_size": os.path.getsize(snap), "db_sha256": sha(snap),
                  "file_size": os.path.getsize(enc), "file_sha256": sha(enc),
                  "integrity": check}, ensure_ascii=False))
PY
  rm -rf "$work"
  echo "${name}: $(du -h "$enc" | cut -f1), проверка — ${check:0:60}"
done < "$TARGETS"

python3 - "$ENTRIES" "${DEST}/manifest.json" "$DAY" "$NOW" "$(hostname -f 2>/dev/null || hostname)" <<'PY'
import json, os, sys
entries, path, day, now, host = sys.argv[1:]
with open(entries) as f:
    dbs = [json.loads(line) for line in f if line.strip()]
data = {"day": day, "time": now, "host": host, "encrypted": "age, открытый ключ владельца",
        "dbs": dbs}
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, ensure_ascii=False, indent=1)
    f.write("\n")
os.replace(tmp, path)
PY
chown root:backup "${DEST}/manifest.json"
chmod 640 "${DEST}/manifest.json"

# Хранение — 14 дней по дате в имени папки.
cutoff="$(TZ=Europe/Moscow date -d "-${KEEP_DAYS} days" +%F)"
for d in "${OUT}"/????-??-??; do
  [[ -d "$d" ]] || continue
  if [[ "$(basename "$d")" < "$cutoff" ]]; then rm -rf "$d"; fi
done

if (( failed )); then
  status error "есть ошибки — см. manifest.json"
  echo "Снимок ${DAY}: есть ошибки" >&2
  exit 1
fi
status ok ""
echo "Снимок ${DAY} готов: ${DEST}"
