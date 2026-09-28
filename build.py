#!/usr/bin/env python3
"""Собирает страницы из src/ в site/: подставляет общую шапку, подвал и <head>."""
import hashlib, pathlib, re, sys
root = pathlib.Path(__file__).parent
sys.path.insert(0, str(root / "src"))
import partials

SITE = "https://gornitsa.games"

# страница: (раздел в шапке, основа ссылок, язык, та же страница на другом языке).
# Страницы во вложенных папках, английские и 404 ссылаются на общие файлы от корня
# сайта ("/"), русские в корне — относительно ("").
pages = {
    "index.html": ("home", "", "ru", "en/index.html"),
    "about.html": ("about", "", "ru", "en/about.html"),
    "brand.html": ("brand", "", "ru", "en/brand.html"),
    "support.html": ("support", "", "ru", "en/support.html"),
    "privacy.html": ("privacy", "", "ru", "en/privacy.html"),
    "404.html": ("404", "/", "ru", "en/index.html"),
    "votchina/index.html": ("games", "/", "ru", "en/votchina/index.html"),
    "votchina/tournaments.html": ("games", "/", "ru", "en/votchina/tournaments.html"),
    "votchina/delete.html": ("games", "/", "ru", "en/votchina/delete.html"),
    "nardy/index.html": ("games", "/", "ru", "en/nardy/index.html"),
    "skazy/index.html": ("games", "/", "ru", "en/skazy/index.html"),
    "anamnez/index.html": ("games", "/", "ru", "en/anamnez/index.html"),
    "uzory/index.html": ("games", "/", "ru", "en/uzory/index.html"),
    "en/index.html": ("home", "/", "en", "index.html"),
    "en/about.html": ("about", "/", "en", "about.html"),
    "en/brand.html": ("brand", "/", "en", "brand.html"),
    "en/support.html": ("support", "/", "en", "support.html"),
    "en/privacy.html": ("privacy", "/", "en", "privacy.html"),
    "en/votchina/index.html": ("games", "/", "en", "votchina/index.html"),
    "en/votchina/tournaments.html": ("games", "/", "en", "votchina/tournaments.html"),
    "en/votchina/delete.html": ("games", "/", "en", "votchina/delete.html"),
    "en/nardy/index.html": ("games", "/", "en", "nardy/index.html"),
    "en/skazy/index.html": ("games", "/", "en", "skazy/index.html"),
    "en/anamnez/index.html": ("games", "/", "en", "anamnez/index.html"),
    "en/uzory/index.html": ("games", "/", "en", "uzory/index.html"),
}

# Старые адреса: страница копируется как есть и сразу переадресует на новый адрес.
raw = ["votchina/privacy.html"]


def url(name):
    return "/" + (name[: -len("index.html")] if name.endswith("index.html") else name)


# Браузеры кэшируют стили и скрипты на неделю (см. nginx), поэтому к ссылкам на них
# добавляется отпечаток содержимого: после правки site.css адрес меняется сам.
ver = {name: hashlib.sha256((root / "site" / "assets" / name).read_bytes()).hexdigest()[:8] for name in ("site.css", "site.js", "brand.css")}


def write(name, html):
    html = re.sub(r'(assets/((?:site|brand)\.(?:css|js)))"', lambda m: f'{m.group(1)}?v={ver[m.group(2)]}"', html)
    out = root / "site" / name
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
    print("site/" + name)


for name, (key, base, lang, pair) in pages.items():
    html = (root / "src" / name).read_text(encoding="utf-8")
    alternates = ""
    if key != "404":
        ru, en = (name, pair) if lang == "ru" else (pair, name)
        alternates = f'\n<link rel="alternate" hreflang="ru" href="{SITE}{url(ru)}">\n<link rel="alternate" hreflang="en" href="{SITE}{url(en)}">'
    html = (html.replace("{{HEAD}}", partials.head(base, lang, alternates))
                .replace("{{HEADER}}", partials.header(key, base, lang, url(pair)))
                .replace("{{FOOTER}}", partials.footer(base, lang))
                .replace("{{MARK}}", partials.BRAND))
    write(name, html)

for name in raw:
    write(name, (root / "src" / name).read_text(encoding="utf-8"))
