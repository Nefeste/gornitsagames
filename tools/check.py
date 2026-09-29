#!/usr/bin/env python3
"""Проверка собранного сайта (после build.py): ссылки внутри сайта ведут на существующие
страницы, файлы и якоря, а у картинок игр пропорции в разметке (width и height) совпадают
с файлом — иначе картинка растянется. Файл может быть крупнее разметки (для чётких экранов).
Разметка для поисковиков (application/ld+json) — правильный JSON, и адреса сайта в ней есть.

    python3 build.py && python3 tools/check.py
"""
import datetime, json, pathlib, re, sys
from urllib.parse import urljoin, urlsplit

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "site"


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
