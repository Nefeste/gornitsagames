#!/usr/bin/env python3
"""Собирает страницы из src/ в site/: подставляет общую шапку, подвал и <head>."""
import hashlib, json, pathlib, re, sys
root = pathlib.Path(__file__).parent
sys.path.insert(0, str(root / "src"))
sys.path.insert(0, str(root / "tools"))
import news, partials

SITE = "https://gornitsa.games"

# страница: (раздел в шапке, основа ссылок, язык, та же страница на другом языке).
# Страницы во вложенных папках, английские и 404 ссылаются на общие файлы от корня
# сайта ("/"), русские в корне — относительно ("").
pages = {
    "index.html": ("home", "", "ru", "en/index.html"),
    "about.html": ("about", "", "ru", "en/about.html"),
    "brand.html": ("brand", "", "ru", "en/brand.html"),
    "news.html": ("news", "", "ru", "en/news.html"),
    "press.html": ("press", "", "ru", "en/press.html"),
    "support.html": ("support", "", "ru", "en/support.html"),
    "privacy.html": ("privacy", "", "ru", "en/privacy.html"),
    "404.html": ("404", "/", "ru", "en/index.html"),
    "votchina/index.html": ("games", "/", "ru", "en/votchina/index.html"),
    "votchina/tournaments.html": ("games", "/", "ru", "en/votchina/tournaments.html"),
    "votchina/delete.html": ("games", "/", "ru", "en/votchina/delete.html"),
    "nardy/index.html": ("games", "/", "ru", "en/nardy/index.html"),
    "skazy/index.html": ("games", "/", "ru", "en/skazy/index.html"),
    "skazy/delete.html": ("games", "/", "ru", "en/skazy/delete.html"),
    "anamnez/index.html": ("games", "/", "ru", "en/anamnez/index.html"),
    "uzory/index.html": ("games", "/", "ru", "en/uzory/index.html"),
    "en/index.html": ("home", "/", "en", "index.html"),
    "en/about.html": ("about", "/", "en", "about.html"),
    "en/brand.html": ("brand", "/", "en", "brand.html"),
    "en/news.html": ("news", "/", "en", "news.html"),
    "en/press.html": ("press", "/", "en", "press.html"),
    "en/support.html": ("support", "/", "en", "support.html"),
    "en/privacy.html": ("privacy", "/", "en", "privacy.html"),
    "en/votchina/index.html": ("games", "/", "en", "votchina/index.html"),
    "en/votchina/tournaments.html": ("games", "/", "en", "votchina/tournaments.html"),
    "en/votchina/delete.html": ("games", "/", "en", "votchina/delete.html"),
    "en/nardy/index.html": ("games", "/", "en", "nardy/index.html"),
    "en/skazy/index.html": ("games", "/", "en", "skazy/index.html"),
    "en/skazy/delete.html": ("games", "/", "en", "skazy/delete.html"),
    "en/anamnez/index.html": ("games", "/", "en", "anamnez/index.html"),
    "en/uzory/index.html": ("games", "/", "en", "uzory/index.html"),
}

# Игры в подвале — в порядке tools/games.json, названия — из <h1> страниц игр:
# новая игра появится в подвале сама, как только у неё будет страница.
def game_names(lang):
    out = []
    for g in json.loads((root / "tools" / "games.json").read_text(encoding="utf-8"))["games"]:
        page = root / "src" / ("en" if lang == "en" else "") / g["slug"] / "index.html"
        if page.is_file():
            m = re.search(r"<h1[^>]*>(.*?)</h1>", page.read_text(encoding="utf-8"), re.S)
            if m:
                out.append((g["slug"], re.sub(r"<[^>]+>", "", m.group(1)).strip()))
    return out


GAMES = {lang: game_names(lang) for lang in ("ru", "en")}


def og_defaults(html, lang):
    """Страницам без своей карточки для ссылок (все, кроме страниц игр) — поля og: из <title>,
    описания и canonical и картинка студии 1200 × 630: в Telegram и ВКонтакте ссылка
    уходит с картинкой."""
    add = []
    pick = lambda pat: (re.search(pat, html, re.S) or [None, None])[1]
    if 'property="og:title"' not in html:
        title, desc, canon = pick(r"<title>(.*?)</title>"), pick(r'<meta name="description" content="([^"]*)"'), pick(r'<link rel="canonical" href="([^"]*)"')
        add.append('<meta property="og:type" content="website">')
        add.append(f'<meta property="og:site_name" content="{partials.T[lang]["brand"]}">')
        if title:
            add.append(f'<meta property="og:title" content="{title}">')
        if desc:
            add.append(f'<meta property="og:description" content="{desc}">')
        if canon:
            add.append(f'<meta property="og:url" content="{canon}">')
    if 'property="og:image"' not in html:
        img = "og-studio-en.png" if lang == "en" else "og-studio.png"
        alt = partials.T[lang]["og_alt"]
        add += [f'<meta property="og:image" content="{SITE}/assets/{img}">',
                '<meta property="og:image:width" content="1200">', '<meta property="og:image:height" content="630">',
                f'<meta property="og:image:alt" content="{alt}">']
    if 'name="twitter:card"' not in html:
        add.append('<meta name="twitter:card" content="summary_large_image">')
    return html.replace("</head>", "\n".join(add) + "\n</head>", 1) if add else html


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
                .replace("{{FOOTER}}", partials.footer(base, lang, GAMES[lang], url(pair)))
                .replace("{{MARK}}", partials.BRAND)
                .replace("{{NEWS}}", news.page(lang))
                .replace("{{NEWS_LATEST}}\n", news.latest(lang, base)))
    if key != "404":
        html = og_defaults(html, lang)
    if key == "home":
        html = html.replace("</head>", partials.studio_ld(lang) + "\n</head>", 1)
    write(name, html)

for name in raw:
    write(name, (root / "src" / name).read_text(encoding="utf-8"))

# Лента новостей Atom; новость с ошибкой в сайт не попадает — причина здесь и в tools/check.py.
for lang, name in (("ru", "news.atom"), ("en", "en/news.atom")):
    (root / "site" / name).write_text(news.atom(lang), encoding="utf-8")
    print("site/" + name)
    for err in news.load(lang)[1]:
        print("Новость пропущена — " + err, file=sys.stderr)
