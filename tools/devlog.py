#!/usr/bin/env python3
"""Черновик «Дневника разработки» — новости раз в две недели по STATUS.md игр (поручение 06;
шаблон и порядок — docs/devlog.md). Только стандартная библиотека Python.

    python3 tools/devlog.py --games ../ [--date ГГГГ-ММ-ДД] [--force]

--games — папка, где лежат клоны игр: <папка>/<игра>/STATUS.md (игры и порядок — tools/games.json).
Пишет news/<дата>-devlog.ru.md с полем review: draft: сайт такую новость не публикует, пока
владелец не перепишет её голосом студии и не поставит review: checked. Если прошлый дневник
моложе 13 дней — ничего не делает (без --force).

Из STATUS.md берётся строка «Версия», «Этап» и первый пункт «Что дальше» — это заготовка:
в STATUS.md пишут для команды (номера PR, ADR, теги), а не для игроков. Черновик правится
вручную; правила — docs/devlog.md и голос студии (устав, docs/09-voice.md).
"""
import argparse, datetime as dt, json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
NEWS = ROOT / "news"
MONTHS = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября",
          "октября", "ноября", "декабря"]
EVERY_DAYS = 13


def names():
    """Названия игр — из <h1> их страниц на сайте, порядок — tools/games.json."""
    out = []
    for g in json.loads((ROOT / "tools" / "games.json").read_text(encoding="utf-8"))["games"]:
        page = ROOT / "src" / g["slug"] / "index.html"
        m = re.search(r"<h1[^>]*>(.*?)</h1>", page.read_text(encoding="utf-8"), re.S) if page.is_file() else None
        out.append((g["slug"], re.sub(r"<[^>]+>", "", m.group(1)).strip() if m else g["slug"]))
    return out


def clean(s):
    """Строку для команды — в строку для игрока: без ссылок на документы, кода, PR и ADR."""
    s = re.sub(r"<https?://[^>]+>", "", s)
    s = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", s)
    s = re.sub(r"\((?:[^()]*(?:ADR|PR|#\d|docs/|\.md|versionCode|спецификац)[^()]*)\)", "", s)
    s = re.sub(r"`[^`]*`", "", s)
    s = re.sub(r"\*\*|\*", "", s)
    s = re.sub(r"\s+([,.;:])", r"\1", re.sub(r"\s{2,}", " ", s))
    return s.strip(" ;,—-")


def first(s):
    """Первое предложение — остальное в STATUS.md подробности для команды."""
    s = re.split(r"(?<=[.;])\s+(?=[А-ЯЁA-Z«])|;\s+", s)[0]
    return s.rstrip(" .;,—-")


def field(text, label):
    """«**Версия:** …» вместе со строками-продолжениями до пустой строки или следующего поля."""
    m = re.search(rf"^\s*(?:- )?\*\*{label}:\*\*\s*(.*)$", text, re.M)
    if not m:
        return ""
    out = [m.group(1)]
    for line in text[m.end():].splitlines()[1:]:
        if not line.strip() or re.match(r"\s*(?:- )?\*\*|#", line):
            break
        out.append(line.strip())
    return clean(" ".join(out))


def next_item(text):
    m = re.search(r"^(?:##\s*|\*\*)Что дальше.*$", text, re.M)
    if not m:
        return ""
    for line in text[m.end():].splitlines():
        line = line.strip()
        if line.startswith("#"):
            break
        item = re.match(r"(?:-|\d+\.)\s+(.*)", line)
        if item:
            return clean(item.group(1))
    return ""


def last_devlog():
    dates = [p.name[:10] for p in NEWS.glob("*-devlog*.ru.md")]
    return max((dt.date.fromisoformat(d) for d in dates), default=None)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--games", type=pathlib.Path, required=True, help="папка с клонами игр")
    ap.add_argument("--date", default=dt.date.today().isoformat())
    ap.add_argument("--force", action="store_true", help="даже если прошлый дневник моложе 13 дней")
    a = ap.parse_args()
    day = dt.date.fromisoformat(a.date)
    last = last_devlog()
    if last and (day - last).days < EVERY_DAYS and not a.force:
        print(f"Прошлый дневник — {last}, следующий не раньше {last + dt.timedelta(days=EVERY_DAYS)}")
        return 0
    rows = []
    for slug, name in names():
        status = a.games / slug / "STATUS.md"
        if not status.is_file():
            print(f"{slug}: нет {status} — игра пропущена", file=sys.stderr)
            continue
        text = status.read_text(encoding="utf-8")
        parts = [f"Версия {first(v)}" if (v := field(text, "Версия")) else ""]
        if (stage := field(text, "Этап")):
            parts.append(f"Сейчас: {first(stage)}")
        if (nxt := next_item(text)):
            parts.append(f"Дальше: {first(nxt)}")
        parts = [p for p in parts if p]
        if parts:
            rows.append(f"- «{name}». " + ". ".join(parts) + ".")
    if not rows:
        print("Ни одного STATUS.md — черновик не написан", file=sys.stderr)
        return 1
    out = NEWS / f"{day}-devlog.ru.md"
    out.write_text(f"""---
date: {day}
title: Дневник разработки: {day.day} {MONTHS[day.month - 1]}
review: draft
---
Что изменилось в играх «Горницы» за две недели.

{chr(10).join(rows)}
""", encoding="utf-8")
    print(f"Черновик: {out.relative_to(ROOT)} (review: draft — перепишите по docs/devlog.md)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
