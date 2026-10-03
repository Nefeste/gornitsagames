"""Поиск и нейропоиск (поручение 06): разметка schema.org, которой нет в шаблонах страниц,
переходы на RuStore через /go/<игра> и /llms.txt. Вызывает build.py; без сторонних библиотек —
сайт собирается и на сервере.

- BreadcrumbList — на всех страницах, кроме главной и 404;
- FAQPage — на странице поддержки, из её же <details class="faq">: вопрос и ответ живут в одном месте;
- NewsArticle — на странице новостей, по одной на новость (tools/news.py);
- /go/<игра> — переадресация на карточку игры в RuStore (пока карточки нет — на страницу игры).
  Её делает nginx (сниппет собирается здесь, ставит deploy/seo/apply.sh), а site/go/<игра>.html —
  запасная страница, если сниппета на машине ещё нет. Ссылки страниц на RuStore идут через /go/:
  так переходы видны в журнале сервера, а cookie и счётчики не нужны (решение №30);
- /llms.txt и /en/llms.txt — кто студия, игры со ссылками, политика и почта: из tools/games.json
  и собранных страниц игр.
"""
import html, json, pathlib, re

import news
from md import SITE, attr

ROOT = pathlib.Path(__file__).resolve().parent.parent
GAMES_JSON = ROOT / "tools" / "games.json"
STORE_RE = re.compile(r"https://www\.rustore\.ru/catalog/app/[A-Za-z0-9_.]+")

T = {
    "ru": {"home": "Горница", "news": "Новости", "faq_page": "/support.html", "news_page": "/news.html",
           "summary": "Студия мобильных игр для RuStore: спокойные, честные и понятные игры на русском материале. "
                      "Игры работают без сети, без регистрации, а реклама не мешает играть.",
           "about": "«Горница» — небольшая независимая студия. Каждую игру она сначала выпускает в RuStore, для недорогих "
                    "Android-телефонов, и поддерживает сама. Девять обещаний игрокам: честная случайность, деньги не "
                    "покупают победу, играть можно без сети, без регистрации, реклама не мешает, никакого давления, "
                    "бот — всегда бот, ничего лишнего о вас, ответ по существу.",
           "games": "Игры", "studio": "Студия", "help": "Помощь", "contacts": "Контакты",
           "status": {"live": "в RuStore", "test": "закрытый тест", "dev": "в разработке"},
           "rustore": "RuStore", "facts": {"Платформа": "Платформа", "Цена": "цена", "Интернет": "интернет", "Возраст": "возраст"},
           "links": [("О студии и девять обещаний игрокам", "/about.html"), ("Новости", "/news.html"),
                     ("Для прессы", "/press.html"), ("Брендбук", "/brand.html")],
           "help_links": [("Поддержка и частые вопросы", "/support.html"),
                          ("Политика конфиденциальности", "/privacy.html")],
           "mail": [("Поддержка игроков", "support@gornitsa.games"), ("Общая почта", "hello@gornitsa.games"),
                    ("Пресса", "press@gornitsa.games"), ("Вопросы о данных", "privacy@gornitsa.games")],
           "channels": "Каналы", "dev_page": "Страница разработчика в RuStore",
           "other": ("English version", "/en/llms.txt")},
    "en": {"home": "Gornitsa", "news": "News", "faq_page": "/en/support.html", "news_page": "/en/news.html",
           "summary": "A mobile game studio for RuStore: calm, honest and clear games built on Russian culture. "
                      "The games work offline, need no sign-up, and ads never interrupt play.",
           "about": "Gornitsa is a small independent studio. It releases every game on RuStore first, for affordable "
                    "Android phones, and supports it itself. Nine promises to players: fair randomness, money never "
                    "buys a win, play offline, no sign-up, ads never get in the way, no pressure, a bot is always a bot, "
                    "nothing collected beyond what's needed, real answers from support.",
           "games": "Games", "studio": "Studio", "help": "Help", "contacts": "Contacts",
           "status": {"live": "on RuStore", "test": "closed test", "dev": "in development"},
           "rustore": "RuStore", "facts": {"Platform": "Platform", "Price": "price", "Internet": "internet", "Age rating": "age"},
           "links": [("About the studio and its nine promises", "/en/about.html"), ("News", "/en/news.html"),
                     ("Press", "/en/press.html"), ("Brand book", "/en/brand.html")],
           "help_links": [("Support and FAQ", "/en/support.html"), ("Privacy policy", "/en/privacy.html")],
           "mail": [("Player support", "support@gornitsa.games"), ("General", "hello@gornitsa.games"),
                    ("Press", "press@gornitsa.games"), ("Data questions", "privacy@gornitsa.games")],
           "channels": "Channels", "dev_page": "Developer page on RuStore",
           "other": ("Русская версия", "/llms.txt")},
}

STUDIO = {"@type": "Organization", "@id": f"{SITE}/#studio"}


def text(fragment):
    """HTML → строка: без тегов, с обычными пробелами."""
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", fragment))).replace(" .", ".").replace(" ,", ",").strip()


def ld(data):
    return '<script type="application/ld+json">' + json.dumps(data, ensure_ascii=False).replace("</", "<\\/") + "</script>"


def games():
    return [g["slug"] for g in json.loads(GAMES_JSON.read_text(encoding="utf-8"))["games"]]


# ---------- /go/<игра> ----------

def go_targets():
    """Куда ведёт /go/<игра>: карточка RuStore со страницы игры, а пока её нет — сама страница."""
    out = {}
    for slug in games():
        page = ROOT / "src" / slug / "index.html"
        m = STORE_RE.search(page.read_text(encoding="utf-8")) if page.is_file() else None
        out[slug] = m.group(0) if m else f"{SITE}/{slug}/"
    return out


def go_rewrite(html_text, targets):
    """Ссылки страниц на карточку RuStore → /go/<игра>. Разметку для поисковиков (ld+json) не трогает:
    там остаётся адрес магазина."""
    by_url = {u: s for s, u in targets.items() if "rustore.ru/" in u}
    return re.sub(r'href="(https://www\.rustore\.ru/catalog/app/[A-Za-z0-9_.]+)"',
                  lambda m: f'href="/go/{by_url[m.group(1)]}"' if m.group(1) in by_url else m.group(0), html_text)


def go_page(slug, url):
    """Запасная страница /go/<игра>.html: nginx отдаёт её, только если сниппета переадресаций нет."""
    u = attr(url)
    return f"""<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<meta http-equiv="refresh" content="0; url={u}">
<link rel="canonical" href="{u}">
<title>Переход — Горница</title>
</head>
<body>
<p><a href="{u}">{u}</a></p>
</body>
</html>
"""


def go_nginx(targets):
    """Сниппет nginx: /go/<игра> → 302 на RuStore. no-store — каждый переход виден в журнале."""
    lines = ["# /go/<игра> — переходы на RuStore (поручение 06). Собирает build.py (tools/seo.py),",
             "# ставит deploy/seo/apply.sh в /etc/nginx/snippets/gornitsa.games-go.conf — правки здесь затрутся."]
    for slug, url in targets.items():
        lines += [f"location ~ ^/go/{slug}/?$ {{",
                  f"    add_header Cache-Control \"no-store\" always;",
                  f"    add_header X-Robots-Tag \"noindex\" always;",
                  f"    include /etc/nginx/snippets/gornitsa-site-headers.conf;",
                  f"    return 302 {url};",
                  "}"]
    return "\n".join(lines) + "\n"


# ---------- разметка schema.org ----------

def breadcrumbs(name, page_html, lang, game_names):
    """BreadcrumbList: «Горница» → игра → страница. Главная и 404 — без неё."""
    t = T[lang]
    pre = "/en" if lang == "en" else ""
    items = [(t["home"], f"{SITE}{pre}/")]
    rel = name[3:] if name.startswith("en/") else name
    parts = rel.split("/")
    title = text((re.search(r"<title>(.*?)</title>", page_html, re.S) or [None, ""])[1])
    here = title.split(" — ")[0]
    if len(parts) == 2:  # страница игры или страница внутри игры
        slug = parts[0]
        game = dict(game_names).get(slug, slug)
        items.append((game, f"{SITE}{pre}/{slug}/"))
        if parts[1] != "index.html":
            items.append((here, f"{SITE}{pre}/{rel}"))
    else:
        items.append((here, f"{SITE}{pre}/{rel}"))
    return ld({"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": i, "name": n, "item": u} for i, (n, u) in enumerate(items, 1)]})


def faq(page_html, lang):
    """FAQPage из вопросов страницы поддержки (<details class="faq">)."""
    qa = re.findall(r'<details class="faq"[^>]*>\s*<summary>(.*?)</summary>\s*<div class="answer">(.*?)</div>\s*</details>',
                    page_html, re.S)
    if not qa:
        return ""
    return ld({"@context": "https://schema.org", "@type": "FAQPage", "inLanguage": lang,
               "url": f"{SITE}{T[lang]['faq_page']}", "mainEntity": [
                   {"@type": "Question", "name": text(q), "acceptedAnswer": {"@type": "Answer", "text": text(a)}}
                   for q, a in qa]})


def news_articles(lang):
    """NewsArticle на каждую новость страницы «Новости»."""
    items, _ = news.load(lang)
    if not items:
        return ""
    t = T[lang]
    img = f"{SITE}/assets/og-studio-en.png" if lang == "en" else f"{SITE}/assets/og-studio.png"
    graph = [{"@type": "NewsArticle", "headline": i["title"], "url": f"{SITE}{t['news_page']}#{i['id']}",
              "mainEntityOfPage": f"{SITE}{t['news_page']}#{i['id']}",
              "datePublished": f"{i['date']}T12:00:00+03:00", "dateModified": f"{i['date']}T12:00:00+03:00",
              "description": text(re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", i["lead"]).replace("**", "").replace("*", "")),
              "inLanguage": lang, "image": img, "author": STUDIO, "publisher": STUDIO} for i in items]
    return ld({"@context": "https://schema.org", "@graph": graph})


def enrich(name, key, lang, page_html, game_names, targets):
    """Всё, что добавляется к готовой странице: разметка в <head> и ссылки на RuStore через /go/."""
    add = []
    if key not in ("home", "404"):
        add.append(breadcrumbs(name, page_html, lang, game_names))
    if key == "support":
        add.append(faq(page_html, lang))
    if key == "news":
        add.append(news_articles(lang))
    add = [a for a in add if a]
    if add:
        page_html = page_html.replace("</head>", "\n".join(add) + "\n</head>", 1)
    return go_rewrite(page_html, targets)


# ---------- /llms.txt ----------

def game_info(slug, lang):
    page = ROOT / "src" / ("en" if lang == "en" else "") / slug / "index.html"
    if not page.is_file():
        return None
    h = page.read_text(encoding="utf-8")
    pick = lambda pat: text((re.search(pat, h, re.S) or [None, ""])[1])
    eyebrow = pick(r'<p class="eyebrow">(.*?)</p>')
    status = "live" if 'class="store-badge"' in h else ("test" if re.search(r"закрытый тест|closed test", eyebrow, re.I) else "dev")
    facts = dict((text(k), text(v)) for k, v in re.findall(r"<dt>(.*?)</dt><dd>(.*?)</dd>", h, re.S))
    store = STORE_RE.search(h)
    return {"name": pick(r"<h1[^>]*>(.*?)</h1>"), "lead": pick(r'<p class="lead">(.*?)</p>'),
            "kind": eyebrow.split(" · ")[0], "status": status, "facts": facts,
            "store": store.group(0) if store else None}


def llms(lang, rustore_developer="", telegram="", vk=""):
    """llms.txt по llmstxt.org: заголовок, краткое описание, разделы со ссылками."""
    t = T[lang]
    pre = "/en" if lang == "en" else ""
    out = [f"# {t['home']}", "", f"> {t['summary']}", "", t["about"], "", f"## {t['games']}", ""]
    for slug in games():
        g = game_info(slug, lang)
        if not g:
            continue
        line = f"- [{g['name']}]({SITE}{pre}/{slug}/): {g['kind']}, {t['status'][g['status']]}. {g['lead']}"
        extra = [f"{label}: {g['facts'][dt]}" for dt, label in t["facts"].items() if g["facts"].get(dt)]
        if extra:
            line += " " + "; ".join(extra) + "."
        if g["store"] and g["status"] == "live":
            line += f" {t['rustore']}: {g['store']}"
        out.append(line)
    out += ["", f"## {t['studio']}", ""] + [f"- [{n}]({SITE}{u})" for n, u in t["links"]]
    out += ["", f"## {t['help']}", ""] + [f"- [{n}]({SITE}{u})" for n, u in t["help_links"]]
    out += ["", f"## {t['contacts']}", ""] + [f"- {n}: {m}" for n, m in t["mail"]]
    chans = [c for c in (telegram, vk) if c]
    if chans:
        out.append(f"- {t['channels']}: " + ", ".join(chans))
    if rustore_developer:
        out.append(f"- {t['dev_page']}: {rustore_developer}")
    out += ["", f"[{t['other'][0]}]({SITE}{t['other'][1]})", ""]
    return "\n".join(out)
