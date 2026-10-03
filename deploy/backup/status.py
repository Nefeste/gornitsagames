#!/usr/bin/env python3
"""gornitsa-backup-status — тревоги копий баз для регламентной задачи «Сторож» (раз в 10 минут,
gornitsa-backup-status.timer; ставит deploy/backup/setup.sh). Одна и та же логика на машине сайта
и на машине «Сеней».

Читает состояние последнего снимка (/var/lib/gornitsa-backup/status.json, пишет gornitsa-backup)
и журнал SFTP (internal-sftp -l INFO: строки «close "/out/…/*.age" bytes read N»), пишет открытый
/var/lib/gornitsa-backup/public/status.json. В нём только время, итог integrity_check по базам и
тревоги — без адресов, имён файлов и данных о людях. Отдают его: на машине сайта — мониторинг
(https://gornitsa.games/.well-known/monitor/status.json), на машине «Сеней» — seni-nginx
(https://seni.gornitsa.games/.well-known/backup-status.json).

Тревога, если копии включены (владелец вставил ключи) и:
  - снимок старше 26 часов;
  - снимок с ошибкой или integrity_check не ok;
  - копии не забирали по SFTP больше 3 суток.
"""
import datetime as dt
import json
import os
import re
import socket
import subprocess
import sys
import time

BASE = os.environ.get("BACKUP_STATE", "/var/lib/gornitsa-backup")
SNAPSHOT = os.path.join(BASE, "status.json")
SFTP_STATE = os.path.join(BASE, "sftp.json")
PUBLIC = os.path.join(BASE, "public", "status.json")
SNAPSHOT_MAX_HOURS = 26
READ_MAX_DAYS = 3
SFTP_READ = re.compile(r'^close "/out/\d{4}-\d{2}-\d{2}/[^"]+\.age" bytes read [1-9]\d*')


def write_json(path, data, mode=0o644):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def journal(args):
    try:
        return subprocess.run(["journalctl", "-o", "json", "-q", "--no-pager",
                               "SYSLOG_IDENTIFIER=internal-sftp", *args],
                              capture_output=True, text=True, check=False, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"journalctl: {e}", file=sys.stderr)
        return subprocess.CompletedProcess(args, 1, "", "")


def last_sftp_read():
    """Время последнего чтения копии по SFTP. Сохраняется только время — журнал живёт три дня."""
    try:
        with open(SFTP_STATE) as f:
            st = json.load(f)
    except (OSError, ValueError):
        st = {}
    cursor, last = st.get("cursor"), st.get("last_read", 0)
    p = journal(["--after-cursor", cursor] if cursor else ["--since", "-4d"])
    if p.returncode != 0 and cursor:   # курсор устарел — журнал повернулся
        p = journal(["--since", "-4d"])
    for line in p.stdout.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        cursor = e.get("__CURSOR", cursor)
        msg = e.get("MESSAGE", "")
        if isinstance(msg, list):
            msg = bytes(b for b in msg if isinstance(b, int) and 0 <= b < 256).decode("utf-8", "replace")
        if SFTP_READ.match(msg):
            last = max(last, int(e.get("__REALTIME_TIMESTAMP", time.time() * 1e6)) // 1_000_000)
    write_json(SFTP_STATE, {"cursor": cursor, "last_read": last}, 0o600)
    return last


def iso(ts):
    return dt.datetime.fromtimestamp(ts).astimezone().isoformat(timespec="seconds") if ts else None


def main():
    now = time.time()
    last_read = last_sftp_read()
    try:
        with open(SNAPSHOT) as f:
            snap = json.load(f)
    except (OSError, ValueError):
        snap = None
    out = {
        "generated": iso(now),
        "host": socket.getfqdn(),
        "configured": False,
        "alarms": [],
    }
    # Копии не включены, пока владелец не вставил ключи (gornitsa-backup-keys) — это не тревога.
    if snap and snap.get("result") != "nokeys":
        alarms = []
        snap_ts = dt.datetime.fromisoformat(snap["time"]).timestamp()
        age_h = round((now - snap_ts) / 3600, 1)
        if age_h > SNAPSHOT_MAX_HOURS:
            alarms.append(f"снимок старше {SNAPSHOT_MAX_HOURS} ч")
        if snap.get("result") != "ok":
            alarms.append(f"снимок с ошибкой: {snap.get('note') or 'см. manifest.json'}")
        bad = [d["name"] for d in snap.get("dbs", []) if d.get("integrity") not in ("ok", "нет файла")]
        if bad:
            alarms.append("integrity_check не ok: " + ", ".join(bad))
        read_age_d = round((now - last_read) / 86400, 1) if last_read else None
        if read_age_d is None or read_age_d > READ_MAX_DAYS:
            alarms.append(f"копии не забирали по SFTP больше {READ_MAX_DAYS} суток")
        out.update({
            "configured": True,
            "last_snapshot": snap["time"],
            "snapshot_age_hours": age_h,
            "result": snap.get("result"),
            "integrity": {d["name"]: d.get("integrity") for d in snap.get("dbs", [])},
            "last_sftp_read": iso(last_read),
            "sftp_read_age_days": read_age_d,
            "alarms": alarms,
        })
    out["ok"] = not out["alarms"]
    write_json(PUBLIC, out)


if __name__ == "__main__":
    main()
