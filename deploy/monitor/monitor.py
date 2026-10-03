#!/usr/bin/env python3
"""Мониторинг ресурсов машины сайта и игр (решение владельца №16): хватает ли машине ресурсов
(решение №17 ждёт этих данных). Только стандартная библиотека Python.

  monitor.py collect          замер раз в минуту (gornitsa-monitor.timer)
  monitor.py daily [ДАТА]     сводка за прошедшие сутки (gornitsa-monitor-daily.timer); без даты —
                              за все прошедшие дни, у которых в базе есть замеры, а сводки ещё нет

Замеры — в SQLite /var/lib/gornitsa-monitor/monitor.db, хранятся 30 дней. Сводки —
/var/lib/gornitsa-monitor/daily/ГГГГ-ММ-ДД.json и latest.json (последняя сводка и неделя для
решения №17), хранятся год. Каждые 10 минут в latest.json обновляется раздел backup — копии баз
(deploy/backup/): время последнего снимка, integrity_check каждой базы, время последнего чтения
копий по SFTP; тревоги сторожа — ещё и в открытом status.json (без данных о людях). Ни адресов, ни имён, ни других данных о людях здесь нет: только числа
машины и служб; у событий OOM — только время и служба.
"""
import datetime as dt
import json
import os
import re
import sqlite3
import subprocess
import sys
import time

BASE = os.environ.get("MONITOR_DIR", "/var/lib/gornitsa-monitor")
DB = os.path.join(BASE, "monitor.db")
DAILY = os.path.join(BASE, "daily")
SERVICES = ("votchina", "nardy", "skazy", "nginx")
KEEP_SAMPLES = 30 * 86400
KEEP_DAILY_DAYS = 365
DISK = "/"

# Порог решения №17 (README, «Мониторинг машины»): машине нужны ресурсы, если неделю подряд
# каждый день RAM p95 выше 80 %, был swap или OOM, либо CPU p95 выше 70 %.
RAM_P95_LIMIT = 80.0
CPU_P95_LIMIT = 70.0
WEEK = 7

# Копии баз (deploy/backup/, docs/backup.md): состояние пишет gornitsa-backup, чтения — журнал SFTP.
BACKUP_STATUS = os.environ.get("BACKUP_STATUS", "/var/lib/gornitsa-backup/status.json")
SNAPSHOT_MAX_HOURS = 26
READ_MAX_DAYS = 3
SFTP_READ = re.compile(r'^close "/out/\d{4}-\d{2}-\d{2}/[^"]+\.age" bytes read ([1-9]\d*)')

SCHEMA = """
CREATE TABLE IF NOT EXISTS host (
  ts INTEGER PRIMARY KEY,         -- начало минуты, unix-время
  cpu_pct REAL, iowait_pct REAL, steal_pct REAL,
  load1 REAL, load5 REAL, load15 REAL,
  mem_total INTEGER, mem_used INTEGER, mem_avail INTEGER,   -- байты; used = total - available
  swap_total INTEGER, swap_used INTEGER,
  swap_in INTEGER, swap_out INTEGER,                        -- страниц за минуту (/proc/vmstat)
  disk_total INTEGER, disk_used INTEGER
);
CREATE TABLE IF NOT EXISTS svc (
  ts INTEGER, unit TEXT,
  mem INTEGER,                    -- MemoryCurrent, байты
  cpu_nsec INTEGER,               -- CPUUsageNSec с запуска службы
  cpu_pct REAL,                   -- доля всей машины за минуту
  PRIMARY KEY (ts, unit)
);
CREATE TABLE IF NOT EXISTS oom (ts INTEGER, unit TEXT);
CREATE INDEX IF NOT EXISTS oom_ts ON oom (ts);
CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value TEXT);
"""


def connect():
    os.makedirs(BASE, exist_ok=True)
    con = sqlite3.connect(DB, timeout=30)
    con.execute("PRAGMA journal_mode=WAL")
    con.executescript(SCHEMA)
    return con


def get_state(con, key):
    row = con.execute("SELECT value FROM state WHERE key = ?", (key,)).fetchone()
    return json.loads(row[0]) if row else None


def set_state(con, key, value):
    con.execute("INSERT OR REPLACE INTO state VALUES (?, ?)", (key, json.dumps(value)))


def read_cpu():
    with open("/proc/stat") as f:
        v = [int(x) for x in f.readline().split()[1:9]]
    # user nice system idle iowait irq softirq steal (guest уже входит в user)
    return {"total": sum(v), "idle": v[3] + v[4], "iowait": v[4], "steal": v[7]}


def read_meminfo():
    m = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, rest = line.split(":", 1)
            m[k] = int(rest.split()[0]) * 1024
    return m


def read_vmstat():
    v = {}
    with open("/proc/vmstat") as f:
        for line in f:
            k, val = line.split()
            if k in ("pswpin", "pswpout"):
                v[k] = int(val)
    return v


def systemd_number(value):
    # «[not set]» — службы нет или учёт выключен; 2^64-1 — то же самое
    if not value.isdigit() or int(value) >= 2**64 - 1:
        return None
    return int(value)


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as e:
        print(f"{cmd[0]}: {e}", file=sys.stderr)
        return subprocess.CompletedProcess(cmd, 1, "", "")


def read_services():
    out = run(["systemctl", "show", "-p", "Id,MemoryCurrent,CPUUsageNSec", *(s + ".service" for s in SERVICES)]).stdout
    res = {}
    for block in out.strip().split("\n\n"):
        p = dict(line.split("=", 1) for line in block.splitlines() if "=" in line)
        unit = p.get("Id", "").removesuffix(".service")
        if unit in SERVICES:
            res[unit] = (systemd_number(p.get("MemoryCurrent", "")), systemd_number(p.get("CPUUsageNSec", "")))
    return res


MEMCG = re.compile(r"task_memcg=([^,\s]*)")


def read_oom(con):
    """Новые события OOM из журнала ядра: только время и служба (по cgroup убитого процесса)."""
    cursor = get_state(con, "journal_cursor")
    base = ["journalctl", "-k", "-o", "json", "-q", "--no-pager"]
    p = run(base + (["--after-cursor", cursor] if cursor else ["--since", "-2min"]))
    if p.returncode != 0 and cursor:   # курсор устарел (журнал повернулся) — с последних минут
        p = run(base + ["--since", "-2min"])
    events = []
    for line in p.stdout.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        cursor = e.get("__CURSOR", cursor)
        msg = journal_text(e)
        if "oom-kill:" not in msg:
            continue
        m = MEMCG.search(msg)
        name = os.path.basename(m.group(1)) if m else ""
        unit = name.removesuffix(".service") if name.removesuffix(".service") in SERVICES else "other"
        ts = int(e.get("__REALTIME_TIMESTAMP", time.time() * 1e6)) // 1_000_000
        events.append((ts, unit))
    if cursor:
        set_state(con, "journal_cursor", cursor)
    return events


def journal_text(e):
    msg = e.get("MESSAGE", "")
    if isinstance(msg, list):  # не UTF-8 — journald отдаёт байты числами
        msg = bytes(b for b in msg if isinstance(b, int) and 0 <= b < 256).decode("utf-8", "replace")
    return msg


def read_sftp(con):
    """Время последнего чтения копии по SFTP (internal-sftp -l INFO, deploy/backup/sftp.sh).
    Из строки берётся только время: адрес и имя файла не сохраняются."""
    cursor = get_state(con, "sftp_cursor")
    base = ["journalctl", "-o", "json", "-q", "--no-pager", "SYSLOG_IDENTIFIER=internal-sftp"]
    p = run(base + (["--after-cursor", cursor] if cursor else ["--since", "-4d"]))
    if p.returncode != 0 and cursor:
        p = run(base + ["--since", "-4d"])
    last = get_state(con, "sftp_last_read") or 0
    for line in p.stdout.splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        cursor = e.get("__CURSOR", cursor)
        if SFTP_READ.match(journal_text(e)):
            last = max(last, int(e.get("__REALTIME_TIMESTAMP", time.time() * 1e6)) // 1_000_000)
    if cursor:
        set_state(con, "sftp_cursor", cursor)
    if last:
        set_state(con, "sftp_last_read", last)
    return last


def iso(ts):
    return dt.datetime.fromtimestamp(ts).astimezone().isoformat(timespec="seconds") if ts else None


def backup_state(con, now):
    """Раздел backup для latest.json и тревоги для сторожа."""
    last_read = get_state(con, "sftp_last_read") or 0
    try:
        with open(BACKUP_STATUS) as f:
            st = json.load(f)
    except (OSError, ValueError):
        st = None
    alarms = []
    if st is None:
        return {"configured": False, "alarms": []}
    snap_ts = dt.datetime.fromisoformat(st["time"]).timestamp()
    age_h = round((now - snap_ts) / 3600, 1)
    if age_h > SNAPSHOT_MAX_HOURS:
        alarms.append(f"снимок старше {SNAPSHOT_MAX_HOURS} ч")
    if st.get("result") != "ok":
        alarms.append(f"снимок с ошибкой: {st.get('note') or 'см. manifest.json'}")
    bad = [d["name"] for d in st.get("dbs", []) if d.get("integrity") not in ("ok", "нет файла")]
    if bad:
        alarms.append("integrity_check не ok: " + ", ".join(bad))
    read_age_d = round((now - last_read) / 86400, 1) if last_read else None
    if read_age_d is None or read_age_d > READ_MAX_DAYS:
        alarms.append(f"копии не забирали по SFTP больше {READ_MAX_DAYS} суток")
    return {
        "configured": True,
        "last_snapshot": st["time"],
        "snapshot_age_hours": age_h,
        "result": st.get("result"),
        "integrity": {d["name"]: d.get("integrity") for d in st.get("dbs", [])},
        "last_sftp_read": iso(last_read),
        "sftp_read_age_days": read_age_d,
        "alarms": alarms,
    }


def collect():
    con = connect()
    now = time.time()
    ts = int(now // 60 * 60)
    ncpu = os.cpu_count() or 1

    cpu = read_cpu()
    prev = get_state(con, "cpu")
    cpu_pct = iowait_pct = steal_pct = None
    if prev and cpu["total"] > prev["total"]:
        d = cpu["total"] - prev["total"]
        cpu_pct = round(100 * (1 - (cpu["idle"] - prev["idle"]) / d), 2)
        iowait_pct = round(100 * (cpu["iowait"] - prev["iowait"]) / d, 2)
        steal_pct = round(100 * (cpu["steal"] - prev["steal"]) / d, 2)
    set_state(con, "cpu", cpu)

    vm = read_vmstat()
    pv = get_state(con, "vmstat")
    swap_in = swap_out = None
    if pv and vm.get("pswpin", 0) >= pv.get("pswpin", 0) and vm.get("pswpout", 0) >= pv.get("pswpout", 0):
        swap_in, swap_out = vm.get("pswpin", 0) - pv.get("pswpin", 0), vm.get("pswpout", 0) - pv.get("pswpout", 0)
    set_state(con, "vmstat", vm)

    mem = read_meminfo()
    load = os.getloadavg()
    st = os.statvfs(DISK)
    disk_total = st.f_blocks * st.f_frsize
    disk_used = (st.f_blocks - st.f_bfree) * st.f_frsize
    con.execute("INSERT OR REPLACE INTO host VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
        ts, cpu_pct, iowait_pct, steal_pct, *(round(x, 2) for x in load),
        mem["MemTotal"], mem["MemTotal"] - mem["MemAvailable"], mem["MemAvailable"],
        mem.get("SwapTotal", 0), mem.get("SwapTotal", 0) - mem.get("SwapFree", 0), swap_in, swap_out,
        disk_total, disk_used))

    svc_prev = get_state(con, "svc") or {}
    svc_now = {}
    for unit, (mem_b, nsec) in read_services().items():
        pct = None
        p = svc_prev.get(unit)
        if nsec is not None and p and nsec >= p[1] and now > p[0]:   # меньше — служба перезапускалась
            pct = round(100 * (nsec - p[1]) / ((now - p[0]) * 1e9) / ncpu, 2)
        if nsec is not None:
            svc_now[unit] = [now, nsec]
        con.execute("INSERT OR REPLACE INTO svc VALUES (?,?,?,?,?)", (ts, unit, mem_b, nsec, pct))
    set_state(con, "svc", svc_now)

    con.executemany("INSERT INTO oom VALUES (?, ?)", read_oom(con))

    if ts % 600 == 0 or not os.path.exists(os.path.join(DAILY, "status.json")):   # раз в 10 минут
        read_sftp(con)
        con.commit()
        write_latest(backup_state(con, now))

    old = ts - KEEP_SAMPLES
    for table in ("host", "svc", "oom"):
        con.execute(f"DELETE FROM {table} WHERE ts < ?", (old,))
    con.commit()
    con.close()


def pct(values, q):
    """Перцентиль с линейной интерполяцией (как numpy по умолчанию)."""
    v = sorted(x for x in values if x is not None)
    if not v:
        return None
    k = (len(v) - 1) * q / 100
    lo = int(k)
    hi = min(lo + 1, len(v) - 1)
    return round(v[lo] + (v[hi] - v[lo]) * (k - lo), 2)


def stats(values):
    values = [x for x in values if x is not None]
    if not values:
        return None
    return {"p50": pct(values, 50), "p95": pct(values, 95), "max": round(max(values), 2)}


def mb(x):
    return None if x is None else round(x / 2**20, 1)


def day_bounds(day):
    start = dt.datetime.combine(day, dt.time()).astimezone()   # сутки — по часам машины
    end = dt.datetime.combine(day + dt.timedelta(days=1), dt.time()).astimezone()
    return int(start.timestamp()), int(end.timestamp())


def summarize(con, day):
    a, b = day_bounds(day)
    rows = con.execute("SELECT * FROM host WHERE ts >= ? AND ts < ? ORDER BY ts", (a, b)).fetchall()
    if not rows:
        return None
    cols = [c[0] for c in con.execute("SELECT * FROM host LIMIT 0").description]
    h = [dict(zip(cols, r)) for r in rows]
    last = h[-1]

    ram_pct = [100 * r["mem_used"] / r["mem_total"] for r in h if r["mem_total"]]
    swap_events = sum(1 for r in h if (r["swap_in"] or 0) + (r["swap_out"] or 0) > 0)
    oom_rows = con.execute("SELECT unit, COUNT(*) FROM oom WHERE ts >= ? AND ts < ? GROUP BY unit", (a, b)).fetchall()
    oom_by_unit = dict(oom_rows)
    oom_total = sum(oom_by_unit.values())

    services = {}
    for unit in SERVICES:
        s = con.execute("SELECT mem, cpu_pct FROM svc WHERE unit = ? AND ts >= ? AND ts < ?", (unit, a, b)).fetchall()
        mem_stats = stats([mb(m) for m, _ in s])
        cpu_stats = stats([c for _, c in s])
        if mem_stats or cpu_stats or oom_by_unit.get(unit):
            services[unit] = {"memory_mb": mem_stats, "cpu_pct": cpu_stats, "oom": oom_by_unit.get(unit, 0)}

    cpu_stats = stats(r["cpu_pct"] for r in h)
    ram_stats = stats(ram_pct)
    reasons = []
    if ram_stats and ram_stats["p95"] > RAM_P95_LIMIT:
        reasons.append(f"RAM p95 > {RAM_P95_LIMIT:g} %")
    if swap_events:
        reasons.append("swap")
    if oom_total:
        reasons.append("OOM")
    if cpu_stats and cpu_stats["p95"] > CPU_P95_LIMIT:
        reasons.append(f"CPU p95 > {CPU_P95_LIMIT:g} %")

    return {
        "date": day.isoformat(),
        "generated": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "samples": len(h),   # замеров за сутки; полные сутки — 1440
        "machine": {
            "cpus": os.cpu_count(),
            "ram_total_mb": mb(last["mem_total"]),
            "swap_total_mb": mb(last["swap_total"]),
            "disk_total_gb": round(last["disk_total"] / 2**30, 1),
        },
        "cpu_pct": cpu_stats,
        "cpu_iowait_pct": stats(r["iowait_pct"] for r in h),
        "cpu_steal_pct": stats(r["steal_pct"] for r in h),
        "load1": stats(r["load1"] for r in h),
        "load5": stats(r["load5"] for r in h),
        "ram_used_pct": ram_stats,
        "ram_used_mb": stats(mb(r["mem_used"]) for r in h),
        "ram_available_mb": stats(mb(r["mem_avail"]) for r in h),
        "swap_used_mb": stats(mb(r["swap_used"]) for r in h),
        "disk_used_pct": stats(100 * r["disk_used"] / r["disk_total"] for r in h if r["disk_total"]),
        "disk_free_gb": round((last["disk_total"] - last["disk_used"]) / 2**30, 1),
        "swap_events": swap_events,   # минут, когда страницы уходили в swap или возвращались
        "swap_in_pages": sum(r["swap_in"] or 0 for r in h),
        "swap_out_pages": sum(r["swap_out"] or 0 for r in h),
        "oom": oom_total,
        "services": services,
        "over_threshold": bool(reasons),
        "reasons": reasons,
    }


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.replace(tmp, path)


DAY_FILE = re.compile(r"^(\d{4}-\d{2}-\d{2})\.json$")


def write_latest(backup=None):
    os.makedirs(DAILY, exist_ok=True)
    if backup is None:
        con = connect()
        backup = backup_state(con, time.time())
        con.close()
    # Открытый файл для сторожа: только тревоги и время, без чисел машины и данных о людях.
    write_json(os.path.join(DAILY, "status.json"), {
        "generated": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "backup": {k: backup.get(k) for k in
                   ("configured", "last_snapshot", "snapshot_age_hours", "integrity",
                    "last_sftp_read", "sftp_read_age_days")},
        "alarms": backup["alarms"],
        "ok": not backup["alarms"],
    })
    days = sorted(m.group(1) for m in map(DAY_FILE.match, os.listdir(DAILY)) if m)
    if not days:
        write_json(os.path.join(DAILY, "latest.json"), {"backup": backup})
        return
    summaries = []
    for d in days[-WEEK:]:
        with open(os.path.join(DAILY, d + ".json")) as f:
            summaries.append(json.load(f))
    # дни подряд, которые выше порога, считая от последнего; пропущенный день прерывает счёт
    streak, expect = 0, dt.date.fromisoformat(days[-1])
    for s in reversed(summaries):
        if s["date"] != expect.isoformat() or not s["over_threshold"]:
            break
        streak += 1
        expect -= dt.timedelta(days=1)
    latest = dict(summaries[-1])
    latest["decision17"] = {
        "rule": f"{WEEK} дней подряд: RAM p95 > {RAM_P95_LIMIT:g} %, swap или OOM, либо CPU p95 > {CPU_P95_LIMIT:g} %",
        "days_in_a_row": streak,
        "met": streak >= WEEK,
        "last_days": [{"date": s["date"], "samples": s["samples"], "over": s["over_threshold"], "reasons": s["reasons"]}
                      for s in summaries],
    }
    latest["backup"] = backup
    write_json(os.path.join(DAILY, "latest.json"), latest)


def daily(arg=None):
    con = connect()
    os.makedirs(DAILY, exist_ok=True)
    today = dt.date.today()
    if arg:
        days = [dt.date.fromisoformat(arg)]
    else:
        first = con.execute("SELECT MIN(ts) FROM host").fetchone()[0]
        days = []
        if first is not None:
            d = dt.date.fromtimestamp(first)
            while d < today:
                if not os.path.exists(os.path.join(DAILY, d.isoformat() + ".json")):
                    days.append(d)
                d += dt.timedelta(days=1)
    for d in days:
        s = summarize(con, d)
        if s:
            write_json(os.path.join(DAILY, d.isoformat() + ".json"), s)
            print(f"Сводка за {d}: замеров {s['samples']}, выше порога: {', '.join(s['reasons']) or 'нет'}")
    con.close()

    cutoff = (today - dt.timedelta(days=KEEP_DAILY_DAYS)).isoformat()
    for name in os.listdir(DAILY):
        m = DAY_FILE.match(name)
        if m and m.group(1) < cutoff:
            os.remove(os.path.join(DAILY, name))
    write_latest()


def main():
    os.umask(0o027)   # сводки читает nginx (группа www-data), остальным — нет
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "collect":
        collect()
    elif cmd == "daily":
        daily(sys.argv[2] if len(sys.argv) > 2 else None)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
