#!/usr/bin/env python3
"""Посещаемость сайта без слежки (поручение 06, решение №30: Яндекс Метрику не ставим).
Только стандартная библиотека Python; ни cookie, ни счётчиков на страницах.

  sitestats.py daily [ДАТА]   суммы за сутки из журнала nginx сайта; без даты — за все прошедшие
                              дни последней недели, у которых суммы ещё нет, а журнал ещё есть
  sitestats.py week           сводка за последнюю полную неделю (пн–вс) — site-week.json

Что считается (журнал /var/log/nginx/gornitsa.access.log и его ротации):
- просмотры страниц — GET с ответом 200 или 304 на страницу, которая есть на сайте;
- переходы /go/<игра> — нажатия ссылки на игру в RuStore (tools/seo.py);
- источники — только имя сайта, с которого пришли на страницу (поле Referer), без адреса страницы;
- запросы ботов и программ — одним числом.

IP-адреса, браузеры, время с точностью до секунды и адреса страниц-источников не сохраняются
нигде: из журнала берутся только эти суммы. Суммы за сутки — /var/lib/gornitsa-monitor/site/
ГГГГ-ММ-ДД.json, 14 дней. Неделя — /var/lib/gornitsa-monitor/daily/site-week.json (открыт по адресу
https://gornitsa.games/.well-known/monitor/site-week.json: его читает утренняя сводка по понедельникам)
и архив недель в site/weeks/, год. В неделе источник показывается, только если с него пришли
не меньше трёх раз (политика конфиденциальности, раздел 2).
"""
import datetime as dt
import gzip
import json
import os
import re
import sys
from urllib.parse import unquote, urlsplit

BASE = os.environ.get("MONITOR_DIR", "/var/lib/gornitsa-monitor")
LOGS = os.environ.get("SITE_LOG", "/var/log/nginx/gornitsa.access.log")
WEBROOT = os.environ.get("WEBROOT", "/var/www/gornitsa.games")
HOST = "gornitsa.games"
SITE_DIR = os.path.join(BASE, "site")
WEEKS = os.path.join(SITE_DIR, "weeks")
PUBLIC = os.path.join(BASE, "daily", "site-week.json")
KEEP_DAYS = 14
KEEP_WEEKS = 53
MIN_REFERRER = 3      # источник в недельной сводке — от трёх переходов
TOP_PAGES = 30
TOP_REFERRERS = 20

# Формат combined: адрес - пользователь [время] "запрос" код размер "referer" "user-agent".
# Адрес из первого поля не читается вовсе — группа его пропускает.
LINE = re.compile(r'^\S+ \S+ \S+ \[([^\]]+)\] "(\S+) (\S+)[^"]*" (\d{3}) \S+ "([^"]*)" "([^"]*)"')
BOT = re.compile(r"bot|crawl|spider|slurp|yandex(?!.*yabrowser)|bingpreview|curl|wget|python|go-http|java/|okhttp|"
                 r"httpclient|monitor|uptime|headless|preview|facebookexternalhit|vkshare|whatsapp|"
                 r"lighthouse|pagespeed|scanner|zgrab|masscan|nmap", re.I)
GO = re.compile(r"^/go/([a-z]+)/?$")
SKIP = ("/assets/", "/.well-known/", "/go/", "/uzory/test/")


def page_file(path):
    """Есть ли такая страница на сайте (try_files $uri $uri.html $uri/)."""
    p = os.path.join(WEBROOT, path.lstrip("/"))
    if path.endswith("/"):
        p = os.path.join(p, "index.html")
    for c in (p, p + ".html"):
        if os.path.isfile(c) and c.endswith(".html"):
            return True
    return False


def canonical(path):
    """Один адрес на страницу: /support и /support.html — одно и то же, /index.html — это /."""
    if path.endswith("/index.html"):
        return path[: -len("index.html")]
    if not path.endswith("/") and "." not in path.rsplit("/", 1)[-1]:
        return path + ".html"
    return path


def referrer(ref):
    if not ref or ref == "-":
        return None
    parts = urlsplit(ref)
    if parts.scheme == "android-app":
        return "android-app:" + parts.netloc.lower()
    host = (parts.hostname or "").lower()
    if host.startswith("www."):
        host = host[4:]
    if not host or host == HOST or host.endswith("." + HOST):
        return None
    return host


def log_files():
    """Журнал и его ротации: .1, .2.gz … (logrotate nginx по умолчанию)."""
    base = os.path.basename(LOGS)
    folder = os.path.dirname(LOGS)
    out = []
    for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
        if name == base or re.fullmatch(re.escape(base) + r"\.\d+(\.gz)?", name):
            out.append(os.path.join(folder, name))
    return out


def lines(path):
    opener = gzip.open if path.endswith(".gz") else open
    try:
        with opener(path, "rt", encoding="utf-8", errors="replace") as f:
            yield from f
    except OSError as e:
        print(f"{path}: {e}", file=sys.stderr)


def log_days():
    """Какие сутки (по времени машины в журнале) в журналах вообще есть."""
    days = set()
    for p in log_files():
        for line in lines(p):
            m = LINE.match(line)
            if m:
                days.add(dt.datetime.strptime(m.group(1), "%d/%b/%Y:%H:%M:%S %z").date())
    return days


def count(day):
    s = {"date": day.isoformat(), "views": 0, "pages": {}, "go": {}, "referrers": {}, "bots": 0, "other": 0}
    for p in log_files():
        for line in lines(p):
            m = LINE.match(line)
            if not m:
                continue
            when = dt.datetime.strptime(m.group(1), "%d/%b/%Y:%H:%M:%S %z").date()
            if when != day:
                continue
            method, target, status, ref, agent = m.group(2), m.group(3), int(m.group(4)), m.group(5), m.group(6)
            if method != "GET":
                continue
            if BOT.search(agent) or not agent or agent == "-":
                s["bots"] += 1
                continue
            path = unquote(urlsplit(target).path or "/")
            g = GO.match(path)
            if g and status in (200, 301, 302):
                s["go"][g.group(1)] = s["go"].get(g.group(1), 0) + 1
                continue
            if status not in (200, 304) or path.startswith(SKIP):
                continue
            if not page_file(path):
                s["other"] += 1
                continue
            page = canonical(path)
            s["views"] += 1
            s["pages"][page] = s["pages"].get(page, 0) + 1
            r = referrer(ref)
            if r:
                s["referrers"][r] = s["referrers"].get(r, 0) + 1
    return s


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.chmod(tmp, 0o640)
    os.replace(tmp, path)


def cleanup(today):
    for name in os.listdir(SITE_DIR) if os.path.isdir(SITE_DIR) else []:
        m = re.fullmatch(r"(\d{4}-\d{2}-\d{2})\.json", name)
        if m and (today - dt.date.fromisoformat(m.group(1))).days > KEEP_DAYS:
            os.remove(os.path.join(SITE_DIR, name))
    weeks = sorted(n for n in os.listdir(WEEKS) if n.endswith(".json")) if os.path.isdir(WEEKS) else []
    for name in weeks[:-KEEP_WEEKS]:
        os.remove(os.path.join(WEEKS, name))


def daily(arg=None):
    today = dt.date.today()
    if arg:
        days = [dt.date.fromisoformat(arg)]
    else:
        have = log_days()
        days = [today - dt.timedelta(days=i) for i in range(7, 0, -1)]
        days = [d for d in days if d in have and not os.path.exists(os.path.join(SITE_DIR, f"{d}.json"))]
    for d in days:
        write_json(os.path.join(SITE_DIR, f"{d}.json"), count(d))
        print(f"сутки {d}: готово")
    cleanup(today)


def merge(into, part):
    for k, v in part.items():
        into[k] = into.get(k, 0) + v


def load_week(monday):
    days, missing, total = [], [], {"views": 0, "pages": {}, "go": {}, "referrers": {}, "bots": 0, "other": 0}
    for i in range(7):
        d = monday + dt.timedelta(days=i)
        p = os.path.join(SITE_DIR, f"{d}.json")
        if not os.path.exists(p):
            missing.append(d.isoformat())
            continue
        with open(p) as f:
            s = json.load(f)
        days.append(d.isoformat())
        for k in ("views", "bots", "other"):
            total[k] += s.get(k, 0)
        for k in ("pages", "go", "referrers"):
            merge(total[k], s.get(k, {}))
    return days, missing, total


def top(d, n, minimum=1):
    return dict(sorted(((k, v) for k, v in d.items() if v >= minimum), key=lambda kv: (-kv[1], kv[0]))[:n])


def week():
    today = dt.date.today()
    monday = today - dt.timedelta(days=today.weekday() + 7)  # понедельник прошлой недели
    days, missing, t = load_week(monday)
    _, _, prev = load_week(monday - dt.timedelta(days=7))
    year, num, _ = monday.isocalendar()
    out = {
        "week": f"{year}-W{num:02d}",
        "from": monday.isoformat(),
        "to": (monday + dt.timedelta(days=6)).isoformat(),
        "days_counted": len(days),
        "days_missing": missing,
        "views": t["views"],
        "views_prev_week": prev["views"],
        "go": dict(sorted(t["go"].items())),
        "go_total": sum(t["go"].values()),
        "go_total_prev_week": sum(prev["go"].values()),
        "pages": top(t["pages"], TOP_PAGES),
        "referrers": top(t["referrers"], TOP_REFERRERS, MIN_REFERRER),
        "bots": t["bots"],
        "note": "Без IP-адресов и браузеров: суммы из журнала nginx сайта. go — нажатия /go/<игра> "
                "(у вышедшей игры — переход в RuStore, у игры в разработке — на её страницу). "
                "Источник показан, если с него пришли не меньше трёх раз за неделю.",
        "generated": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
    }
    write_json(os.path.join(WEEKS, f"{out['week']}.json"), out)
    write_json(PUBLIC, out)
    print(f"неделя {out['week']}: просмотров {out['views']}, переходов /go/ {out['go_total']}")
    cleanup(today)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "daily":
        daily(sys.argv[2] if len(sys.argv) > 2 else None)
    elif cmd == "week":
        week()
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
