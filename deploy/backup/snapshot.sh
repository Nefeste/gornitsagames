#!/usr/bin/env bash
# gornitsa-backup: снимок баз SQLite раз в сутки, сжатый и зашифрованный открытым ключом владельца
# (решение владельца №15; инструкция владельцу — docs/backup.md). Запускает gornitsa-backup.timer
# в 03:30 по Москве; вручную — sudo gornitsa-backup.
#
# Для каждой строки /etc/gornitsa-backup/targets.conf («имя путь.db» — база, «имя путь путь…» —
# архив файлов: настройки машины и секреты служб, чтобы поднять машину заново, docs/restore.md):
#   1. sqlite3 «.backup» от имени владельца файла базы — согласованный снимок без остановки службы
#      (и без файлов -wal/-shm от root рядом с базой);
#   2. PRAGMA integrity_check снимка;
#   3. gzip | age -R recipients.txt → /srv/backup/out/ГГГГ-ММ-ДД/<имя>.db.gz.age;
# архив файлов — tar.gz с правами и владельцами, проверка чтением, age → <имя>.tar.gz.age.
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
sha_json() {   # $1 name, $2 kind, $3 открытый файл (до шифрования), $4 зашифрованный, $5 проверка, $6 файлов в архиве
  python3 - "$@" <<'PY'
import hashlib, json, os, sys
name, kind, data, enc, check, count = sys.argv[1:]
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()
e = {"name": name, "kind": kind, "file": os.path.basename(enc)}
if kind == "db":
    e.update({"db_size": os.path.getsize(data), "db_sha256": sha(data)})
else:
    e.update({"files": int(count), "archive_size": os.path.getsize(data), "archive_sha256": sha(data)})
e.update({"file_size": os.path.getsize(enc), "file_sha256": sha(enc), "integrity": check})
print(json.dumps(e, ensure_ascii=False))
PY
}

encrypt() {   # $1 name, $2 что шифровать (уже сжатое или нет — решает $3), $3 gzip|plain, $4 итоговый файл
  local tmp="${4}.tmp"
  if [[ "$3" == gzip ]]; then
    gzip -c -9 "$2" | age -R "$RECIPIENTS" -o "$tmp" || { rm -f "$tmp"; return 1; }
  else
    age -R "$RECIPIENTS" -o "$tmp" "$2" || { rm -f "$tmp"; return 1; }
  fi
  mv -f "$tmp" "$4"
  chown root:backup "$4"
  chmod 640 "$4"
}

fail_entry() {   # $1 name, $2 текст
  printf '{"name":"%s","integrity":"%s"}\n' "$1" "$2" >> "$ENTRIES"
  failed=1
}

snap_db() {   # $1 name, $2 путь к базе SQLite
  local name="$1" path="$2" owner work snap check enc
  if [[ ! -f "$path" ]]; then
    echo "${name}: базы ${path} нет — пропускаю"
    printf '{"name":"%s","kind":"db","missing":true,"integrity":"нет файла"}\n' "$name" >> "$ENTRIES"
    return
  fi
  owner="$(stat -c %U "$path")"
  work="${TMP}/${name}"
  install -d -m 700 -o "$owner" "$work"
  snap="${work}/${name}.db"
  if ! setpriv --reuid="$owner" --regid="$(stat -c %G "$path")" --init-groups \
       sqlite3 "$path" ".backup '${snap}'"; then
    echo "${name}: снимок не удался" >&2
    fail_entry "$name" "снимок не удался"
    return
  fi
  check="$(sqlite3 "$snap" 'PRAGMA integrity_check' 2>&1 | head -c 2000 || true)"
  [[ "$check" == ok ]] || failed=1
  enc="${DEST}/${name}.db.gz.age"
  if ! encrypt "$name" "$snap" gzip "$enc"; then
    echo "${name}: сжатие или шифрование не удалось" >&2
    fail_entry "$name" "шифрование не удалось"
    return
  fi
  sha_json "$name" db "$snap" "$enc" "$check" 0 >> "$ENTRIES"
  rm -rf "$work"
  echo "${name}: $(du -h "$enc" | cut -f1), проверка — ${check:0:60}"
}

snap_files() {   # $1 name, дальше — пути (можно с * : /etc/ssh/ssh_host_*); настройки машины и секреты служб
  local name="$1" p q work arc enc count
  shift
  local rel=()
  shopt -s nullglob
  for p in "$@"; do
    # shellcheck disable=SC2086  # звёздочка в пути из targets.conf раскрывается нарочно
    for q in $p; do
      if [[ -e "$q" ]]; then rel+=("${q#/}"); fi
    done
  done
  shopt -u nullglob
  if (( ${#rel[@]} == 0 )); then
    echo "${name}: ни одного пути нет — пропускаю"
    printf '{"name":"%s","kind":"files","missing":true,"integrity":"нет файла"}\n' "$name" >> "$ENTRIES"
    return
  fi
  work="${TMP}/${name}"
  install -d -m 700 "$work"
  arc="${work}/${name}.tar.gz"
  # права и владельцы — как на машине (числами: на новой машине имена могут получить другие id)
  if ! tar --numeric-owner --ignore-failed-read --warning=no-file-changed -czpf "$arc" -C / "${rel[@]}"; then
    echo "${name}: архив не удался" >&2
    fail_entry "$name" "архив не удался"
    return
  fi
  if count="$(tar -tzf "$arc" | wc -l)" && (( count > 0 )); then check=ok; else check="архив не читается"; failed=1; fi
  enc="${DEST}/${name}.tar.gz.age"
  if ! encrypt "$name" "$arc" plain "$enc"; then
    echo "${name}: шифрование не удалось" >&2
    fail_entry "$name" "шифрование не удалось"
    return
  fi
  sha_json "$name" files "$arc" "$enc" "$check" "$count" >> "$ENTRIES"
  rm -rf "$work"
  echo "${name}: $(du -h "$enc" | cut -f1), файлов ${count}, проверка — ${check}"
}

while read -r name rest; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  if [[ ! "$name" =~ ^[a-z0-9_-]{1,32}$ ]]; then
    echo "targets.conf: имя «$name» — только латиница, цифры, - и _" >&2
    failed=1
    continue
  fi
  read -ra paths <<< "$rest"
  # одна строка — один путь *.db: база SQLite; иначе — архив файлов (настройки, ключи служб)
  if (( ${#paths[@]} == 1 )) && [[ "${paths[0]}" == *.db ]]; then
    snap_db "$name" "${paths[0]}"
  else
    snap_files "$name" "${paths[@]}"
  fi
done < "$TARGETS"

python3 - "$ENTRIES" "${DEST}/manifest.json" "$DAY" "$NOW" "$(hostname -f 2>/dev/null || hostname)" <<'PY'
import json, os, sys
entries, path, day, now, host = sys.argv[1:]
with open(entries) as f:
    dbs = [json.loads(line) for line in f if line.strip()]
data = {"day": day, "time": now, "host": host, "encrypted": "age, открытый ключ владельца",
        "dbs": dbs}  # и базы, и архивы файлов: поле kind
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
