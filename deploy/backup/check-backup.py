#!/usr/bin/env python3
"""check-backup — проверка восстановления копий баз на компьютере владельца (docs/backup.md, шаг 6).
Раз в месяц: берёт самую свежую папку копий, расшифровывает каждую базу закрытым ключом age во
временную папку, сверяет sha256 с manifest.json, делает PRAGMA integrity_check, считает строки
в таблицах и удаляет расшифрованное. Архив настроек машины (*.tar.gz.age) расшифровывается так же,
сверяется по sha256 и читается целиком; показывается только число файлов и верхние папки — не
содержимое (там секреты служб). Нужны Python 3.8+ и программа age; больше ничего.

  python3 check-backup.py --key <файл ключа age> <папка с копиями>
  python3 check-backup.py --key ~/gornitsa-age.txt ~/GornitsaBackup/out

Пишет только числа строк и результат проверки — содержимое баз не выводится.
"""
import argparse
import gzip
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import tempfile


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def newest_day(root):
    days = sorted(d for d in os.listdir(root) if re.fullmatch(r"\d{4}-\d{2}-\d{2}", d)
                  and os.path.isfile(os.path.join(root, d, "manifest.json")))
    if not days:
        sys.exit(f"В {root} нет папок ГГГГ-ММ-ДД с manifest.json")
    return os.path.join(root, days[-1])


def check_files(entry, enc, key, tmp):
    name = entry["name"]
    arc = os.path.join(tmp, name + ".tar.gz")
    p = subprocess.run(["age", "-d", "-i", key, "-o", arc, enc], capture_output=True, text=True)
    if p.returncode != 0:
        print(f"{name}: age не расшифровал: {p.stderr.strip()}")
        return False
    if entry.get("archive_sha256") and sha256(arc) != entry["archive_sha256"]:
        print(f"{name}: sha256 архива не совпал с manifest.json")
        return False
    try:
        with tarfile.open(arc, "r:gz") as t:
            members = t.getmembers()   # читает архив до конца: битый — исключение
    except (tarfile.TarError, OSError, EOFError) as e:
        print(f"{name}: архив не читается: {e}")
        return False
    tops = sorted({"/" + "/".join(m.name.split("/")[:2]) for m in members})
    print(f"{name}: архив настроек читается; файлов и папок {len(members)}"
          + (f" (на сервере было {entry['files']})" if entry.get("files") is not None else ""))
    print("    " + ", ".join(tops))
    return entry.get("files") in (None, len(members))


def check_db(entry, day_dir, key, tmp):
    name = entry["name"]
    if entry.get("missing"):
        print(f"{name}: базы на сервере не было — пропуск")
        return True
    enc = os.path.join(day_dir, entry["file"])
    if not os.path.isfile(enc):
        print(f"{name}: нет файла {entry['file']}")
        return False
    if entry.get("file_sha256") and sha256(enc) != entry["file_sha256"]:
        print(f"{name}: sha256 файла не совпал с manifest.json — файл повреждён при передаче")
        return False
    if entry.get("kind") == "files":
        return check_files(entry, enc, key, tmp)
    gz = os.path.join(tmp, name + ".db.gz")
    db = os.path.join(tmp, name + ".db")
    p = subprocess.run(["age", "-d", "-i", key, "-o", gz, enc], capture_output=True, text=True)
    if p.returncode != 0:
        print(f"{name}: age не расшифровал: {p.stderr.strip()}")
        return False
    with gzip.open(gz, "rb") as src, open(db, "wb") as dst:
        shutil.copyfileobj(src, dst)
    os.remove(gz)
    if entry.get("db_sha256") and sha256(db) != entry["db_sha256"]:
        print(f"{name}: sha256 базы не совпал с manifest.json")
        return False
    con = sqlite3.connect(db)
    try:
        check = con.execute("PRAGMA integrity_check").fetchone()[0]
        tables = [r[0] for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
        counts = {t: con.execute(f'SELECT COUNT(*) FROM "{t.replace(chr(34), chr(34) * 2)}"').fetchone()[0]
                  for t in tables}
    finally:
        con.close()
    size = os.path.getsize(db)
    print(f"{name}: integrity_check — {check}; {size // 1024} КБ; таблиц {len(tables)}")
    for t, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"    {t}: {n}")
    if entry.get("integrity") not in (None, "ok"):
        print(f"    на сервере проверка снимка была: {entry['integrity']}")
    return check == "ok"


def main():
    ap = argparse.ArgumentParser(description="Проверка восстановления копий баз «Горницы»")
    ap.add_argument("--key", required=True, help="файл закрытого ключа age (из age-keygen)")
    ap.add_argument("root", help="папка с копиями: в ней папки ГГГГ-ММ-ДД")
    a = ap.parse_args()
    if shutil.which("age") is None:
        sys.exit("Не найдена программа age — см. docs/backup.md, шаг 1")
    day_dir = newest_day(a.root)
    with open(os.path.join(day_dir, "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    print(f"Копия {manifest['day']} ({manifest.get('host', '')}), снята {manifest['time']}")
    tmp = tempfile.mkdtemp(prefix="gornitsa-check-")
    ok = True
    try:
        for entry in manifest["dbs"]:
            ok = check_db(entry, day_dir, a.key, tmp) and ok
    finally:
        shutil.rmtree(tmp, ignore_errors=True)   # расшифрованное не остаётся на диске
    print("Итог: всё восстанавливается" if ok else "Итог: ЕСТЬ ОШИБКИ — напишите в сессию агенту")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
