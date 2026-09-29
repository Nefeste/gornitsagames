#!/usr/bin/env python3
"""Проверка собранного сайта (после build.py): ссылки внутри сайта ведут на существующие
страницы, файлы и якоря, а у картинок игр пропорции в разметке (width и height) совпадают
с файлом — иначе картинка растянется. Файл может быть крупнее разметки (для чётких экранов).

    python3 build.py && python3 tools/check.py
"""
import pathlib, re, sys
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
            for m in re.finditer(r'\b(?:href|src)="([^"]*)"', t):
                ref = m.group(1)
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
    for e in errors:
        print(e)
    print(f"Проверено страниц: {len(pages)}; ошибок: {len(errors)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
