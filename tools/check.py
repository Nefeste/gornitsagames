#!/usr/bin/env python3
"""Проверка собранного сайта (после build.py): ссылки внутри сайта ведут на существующие
страницы, файлы и якоря, а у картинок игр пропорции в разметке (width и height) совпадают
с файлом — иначе картинка растянется. Файл может быть крупнее разметки (для чётких экранов).
Разметка для поисковиков (application/ld+json) — правильный JSON, и адреса сайта в ней есть.
Новости (news/) — по формату tools/news.py, ленты news.atom — правильный XML.
Поиск (поручение 06): у каждой страницы для поисковиков <title> до 60 знаков и описание
120–160 знаков, оба не повторяются на другой странице; страницы и sitemap.xml совпадают;
ссылки llms.txt ведут на страницы сайта. У страниц игр (их тексты — в store/site/ игры)
описание вне 120–160 — напоминание, а не ошибка: правка — PR в игру.

    python3 build.py && python3 tools/check.py
"""
import datetime, html, json, pathlib, re, sys
import xml.dom.minidom
import xml.etree.ElementTree as ET
from urllib.parse import urljoin, urlsplit

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "src"))
import news  # noqa: E402
import partials  # noqa: E402

TITLE_MAX = 60
DESC_MIN, DESC_MAX = 120, 160


def target(path):
    """Файл, который nginx отдаст по адресу (try_files $uri $uri.html $uri/)."""
    p = SITE / path.lstrip("/")
    if path.endswith("/"):
        p = p / "index.html"
    for c in (p, p.with_name(p.name + ".html")):
        if c.is_file():
            return c
    return None


def image_size(p):
    try:
        from PIL import Image
    except ImportError:
        return None
    with Image.open(p) as im:
        return im.size


def indexable(text):
    """Страница для поисковиков: не 404, не переадресация и без noindex."""
    return not re.search(r'name="robots" content="[^"]*noindex|http-equiv="refresh"', text)


def search_meta(pages):
    """Заголовки и описания под поиск: длины и уникальность (поручение 06)."""
    errors, notes, seen_t, seen_d, urls = [], [], {}, {}, set()
    for page in pages:
        text = page.read_text(encoding="utf-8")
        name = page.relative_to(ROOT).as_posix()
        rel = page.relative_to(SITE).as_posix()
        if rel == "404.html" or not indexable(text):
            continue
        urls.add("https://gornitsa.games/" + (rel[: -len("index.html")] if rel.endswith("index.html") else rel))
        from_store = "Собрано tools/games.py" in text
        t = re.search(r"<title>(.*?)</title>", text, re.S)
        d = re.search(r'<meta name="description" content="([^"]*)"', text)
        title = html.unescape(t.group(1).strip()) if t else ""
        desc = html.unescape(d.group(1)) if d else ""
        if not title:
            errors.append(f"{name}: нет <title>")
        elif len(title) > TITLE_MAX:
            errors.append(f"{name}: длина <title> — {len(title)}, можно до {TITLE_MAX} знаков")
        if not desc:
            errors.append(f"{name}: нет <meta name=\"description\">")
        elif not DESC_MIN <= len(desc) <= DESC_MAX:
            msg = f"{name}: длина описания — {len(desc)}, для поиска нужно {DESC_MIN}–{DESC_MAX} знаков"
            if from_store:
                notes.append(msg + " — правится в store/site/page.*.md игры (поле description)")
            else:
                errors.append(msg)
        for value, seen, what in ((title, seen_t, "<title>"), (desc, seen_d, "описание")):
            if value and value in seen:
                errors.append(f"{name}: {what} такой же, как у {seen[value]}")
            elif value:
                seen[value] = name
    # sitemap.xml: все страницы для поисковиков — в нём, и в нём нет лишнего
    sm = SITE / "sitemap.xml"
    listed = {(l.text or "").strip() for l in ET.parse(sm).getroot().iter("{http://www.sitemaps.org/schemas/sitemap/0.9}loc")}
    for u in sorted(urls - listed):
        errors.append(f"site/sitemap.xml: нет страницы {u}")
    for u in sorted(listed - urls):
        errors.append(f"site/sitemap.xml: {u} — такой страницы для поисковиков нет")
    return errors, notes


def llms_links():
    errors = []
    for name in ("llms.txt", "en/llms.txt"):
        f = SITE / name
        if not f.is_file():
            errors.append(f"site/{name}: нет файла — его пишет build.py")
            continue
        for u in re.findall(r"\]\((https://gornitsa\.games/[^)]*)\)", f.read_text(encoding="utf-8")):
            if target(urlsplit(u).path) is None:
                errors.append(f"site/{name}: ссылка {u} — такой страницы нет")
    return errors


def main():
    errors, pages = [], sorted(SITE.rglob("*.html"))
    if not pages:
        sys.exit("Нет site/*.html: сначала python3 build.py")
    ids = {}
    for page in pages:
        ids[page] = set(re.findall(r'\bid="([^"]+)"', page.read_text(encoding="utf-8")))
    for page in pages:
        text = page.read_text(encoding="utf-8")
        text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
        url = "/" + page.relative_to(SITE).as_posix()
        name = page.relative_to(ROOT).as_posix()
        for tag in re.finditer(r"<(?:a|img|link|script)\b[^>]*>", text):
            t = tag.group(0)
            refs = [m.group(1) for m in re.finditer(r'\b(?:href|src)="([^"]*)"', t)]
            for m in re.finditer(r'\bsrcset="([^"]*)"', t):
                refs += [c.split()[0] for c in m.group(1).split(",") if c.strip()]
            for ref in refs:
                if re.match(r"(https?:|mailto:|tel:|data:)", ref) or ref == "":
                    continue
                parts = urlsplit(urljoin(url, ref))
                if parts.path.startswith("/assets/fonts/"):
                    continue  # шрифты скачивает на сервере deploy/fetch-fonts.sh, в git их нет
                dest = target(parts.path) if parts.path else page
                if dest is None:
                    errors.append(f"{name}: нет {ref}")
                    continue
                if parts.fragment and dest.suffix == ".html" and parts.fragment not in ids.get(dest, set()):
                    errors.append(f"{name}: нет якоря #{parts.fragment} в {dest.relative_to(ROOT).as_posix()}")
            if t.startswith("<img") and "/assets/games/" in t:
                src = re.search(r'src="([^"]+)"', t).group(1)
                w, h = re.search(r'width="(\d+)"', t), re.search(r'height="(\d+)"', t)
                dest = target(urlsplit(urljoin(url, src)).path)
                size = dest and image_size(dest)
                if size and w and h and abs(size[0] * int(h.group(1)) - size[1] * int(w.group(1))) > 0.01 * size[1] * int(w.group(1)):
                    errors.append(f"{name}: {src} — в разметке {w.group(1)} × {h.group(1)}, в файле {size[0]} × {size[1]}: пропорции другие")
        for m in re.finditer(r'<script type="application/ld\+json">(.*?)</script>', text, re.S):
            try:
                data = json.loads(m.group(1))
            except ValueError as e:
                errors.append(f"{name}: разметка ld+json — не JSON: {e}")
                continue
            for ref in re.findall(r'"(https://gornitsa\.games/[^"#]*)', json.dumps(data, ensure_ascii=False)):
                if target(urlsplit(ref).path) is None:
                    errors.append(f"{name}: в ld+json адрес {ref} — такого файла нет")
    for lang in ("ru", "en"):
        errors += news.load(lang)[1]
    found, notes = search_meta(pages)
    errors += found + llms_links() + partials.seller_errors()
    for n in notes:
        print("Напоминание: " + n)
    for lang in ("ru", "en"):
        for d in news.drafts(lang):
            print(f"Напоминание: {d} — черновик (review: draft), на сайт не идёт")
    for feed in sorted(SITE.rglob("*.atom")):
        try:
            xml.dom.minidom.parse(str(feed))
        except Exception as e:
            errors.append(f"{feed.relative_to(ROOT).as_posix()}: лента — не XML: {e}")
    # security.txt действует до даты Expires (RFC 9116): просрочен — ошибка, меньше 60 дней — напоминание
    sec = SITE / ".well-known" / "security.txt"
    if sec.is_file():
        m = re.search(r"^Expires:\s*(\S+)", sec.read_text(encoding="utf-8"), re.M)
        if not m:
            errors.append("site/.well-known/security.txt: нет строки Expires")
        else:
            left = (datetime.datetime.fromisoformat(m.group(1).replace("Z", "+00:00")) - datetime.datetime.now(datetime.timezone.utc)).days
            if left < 0:
                errors.append(f"site/.well-known/security.txt: срок Expires вышел — продлите на год")
            elif left < 60:
                print(f"Напоминание: site/.well-known/security.txt действует ещё {left} дн. — продлите Expires на год")
    for e in errors:
        print(e)
    print(f"Проверено страниц: {len(pages)}; ошибок: {len(errors)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
