import html, json, pathlib, re

BRAND = open(__file__.replace("partials.py", "brandmark.svg")).read().strip()
SITE = "https://gornitsa.games"
# Настройки, которые знает только сайт: реквизиты продавца, страница разработчика в RuStore
CONFIG = json.loads((pathlib.Path(__file__).resolve().parent.parent / "tools" / "site.json").read_text(encoding="utf-8"))
# Каналы студии (устав, docs/10-channels.md): подвал, страница поддержки, разметка для поисковиков
TELEGRAM = "https://t.me/gornitsa_games"
VK = "https://vk.com/gornitsa_games"

T = {
    "ru": {
        "skip": "К содержимому", "brand": "Горница", "home": "Горница, на главную", "sections": "Разделы",
        "games": "Игры", "about": "О студии", "support": "Поддержка", "privacy": "Политика конфиденциальности",
        "docs": "Документы", "studio": "Студия «Горница»", "brandbook": "Брендбук", "other": "English", "other_lang": "en", "fonts": "cyrillic",
        "tagline": "Спокойные, честные и понятные игры для RuStore.", "studio_col": "Студия", "help": "Помощь",
        "mail": "Почта", "mail_hello": "общая", "mail_support": "поддержка", "mail_press": "для прессы",
        "news": "Новости", "press": "Для прессы", "feed": "Новости «Горницы»", "vk": "ВКонтакте",
        "og_alt": "Знак «Горницы» — ромб из вышитых крестиков — и надпись «Светлая комната для хороших игр»",
        "seller": "Продавец", "seller_inn": "ИНН", "seller_ogrnip": "ОГРНИП",
        "seller_address": "Адрес для претензий", "seller_email": "Почта для претензий",
    },
    "en": {
        "skip": "Skip to content", "brand": "Gornitsa", "home": "Gornitsa, home page", "sections": "Sections",
        "games": "Games", "about": "About", "support": "Support", "privacy": "Privacy policy",
        "docs": "Documents", "studio": "Gornitsa Studio", "brandbook": "Brand book", "other": "Русский", "other_lang": "ru", "fonts": "latin",
        "tagline": "Calm, honest and clear games for RuStore.", "studio_col": "Studio", "help": "Help",
        "mail": "Email", "mail_hello": "general", "mail_support": "support", "mail_press": "press",
        "news": "News", "press": "Press", "feed": "Gornitsa news", "vk": "VK",
        "og_alt": "The Gornitsa mark, a diamond of cross-stitches, and the words “A bright room for good games”",
        "seller": "Seller", "seller_inn": "INN (taxpayer number)", "seller_ogrnip": "OGRNIP (state registration)",
        "seller_address": "Address for claims", "seller_email": "Email for claims",
    },
}


def seller_errors():
    """Включённые реквизиты должны быть полными: ИНН ИП — 12 цифр, ОГРНИП — 15. Выдуманных нет:
    пока ИП не зарегистрировано, enabled — false и поля пустые (tools/site.json)."""
    s = CONFIG["seller"]
    if not s.get("enabled"):
        return []
    errs = [f"tools/site.json: seller.{k} пустое, а enabled — true" for k in ("name", "inn", "ogrnip", "address", "email") if not s.get(k)]
    if s.get("inn") and not re.fullmatch(r"\d{12}", s["inn"]):
        errs.append("tools/site.json: seller.inn — 12 цифр (ИНН индивидуального предпринимателя)")
    if s.get("ogrnip") and not re.fullmatch(r"\d{15}", s["ogrnip"]):
        errs.append("tools/site.json: seller.ogrnip — 15 цифр")
    return errs


def seller(lang="ru", kind="block"):
    """Реквизиты продавца — в подвале (kind="line"), на поддержке (kind="block") и в политике (kind="para").
    Выключены в tools/site.json — пустая строка: на сайте ничего не меняется."""
    s, t = CONFIG["seller"], T[lang]
    if not s.get("enabled") or seller_errors():
        return ""
    e = html.escape
    if kind == "para":
        return (f'\n      <p>{t["seller"]}: {e(s["name"])}, {t["seller_inn"]} {e(s["inn"])}, {t["seller_ogrnip"]} {e(s["ogrnip"])}. '
                f'{t["seller_address"]}: {e(s["address"])}; {t["seller_email"].lower()}: {e(s["email"])}.</p>')
    if kind == "line":
        # в подвале — короткое имя («ИП Фамилия И. О.»), если оно есть; полное — на поддержке и в политике
        return (f'\n  <div class="wrap footer-seller"><p class="meta">{e(s.get("short") or s["name"])} · {t["seller_inn"]} {e(s["inn"])} · '
                f'{t["seller_ogrnip"]} {e(s["ogrnip"])} · {t["seller_address"]}: {e(s["address"])}</p></div>')
    rows = [(t["seller"], s["name"]), (t["seller_inn"], s["inn"]), (t["seller_ogrnip"], s["ogrnip"]),
            (t["seller_address"], s["address"]), (t["seller_email"], s["email"])]
    dl = "\n".join(f"        <div><dt>{k}</dt><dd>{e(v)}</dd></div>" for k, v in rows)
    return f"""    <section class="seller" id="seller" aria-labelledby="seller-title">
      <h2 id="seller-title">{t["seller"]}</h2>
      <dl class="game-facts">
{dl}
      </dl>
    </section>
"""


def ld_json(data):
    """Разметка schema.org для поисковиков: JSON в <script>, без «</» внутри."""
    text = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
    return f'<script type="application/ld+json">{text}</script>'


def studio_ld(lang="ru"):
    """Главная: студия (название, знак, почта) и сайт. Страницы игр ссылаются на студию по @id."""
    t, other = T[lang], T["en" if lang == "ru" else "ru"]
    home = f"{SITE}/en/" if lang == "en" else f"{SITE}/"
    return ld_json({"@context": "https://schema.org", "@graph": [
        {"@type": "Organization", "@id": f"{SITE}/#studio", "name": t["brand"], "alternateName": other["brand"],
         "url": f"{SITE}/", "logo": f"{SITE}/assets/brand/mark-1024.png", "description": t["tagline"],
         "email": "hello@gornitsa.games", "sameAs": [TELEGRAM, VK] + ([CONFIG["rustore_developer"]["url"]] if CONFIG["rustore_developer"].get("url") else []),
         "contactPoint": [
             {"@type": "ContactPoint", "contactType": "customer support", "email": "support@gornitsa.games",
              "availableLanguage": ["ru", "en"]},
             {"@type": "ContactPoint", "contactType": "press", "email": "press@gornitsa.games"}]},
        {"@type": "WebSite", "@id": f"{home}#site", "url": home, "name": t["brand"], "inLanguage": lang,
         "publisher": {"@id": f"{SITE}/#studio"}},
    ]})


def prefix(b, lang):
    """Начало ссылок на страницы: "" или "/" у русской версии, "/en/" у английской."""
    return b + "en/" if lang == "en" else b


def head(b, lang="ru", alternates=""):
    f = T[lang]["fonts"]
    feed = "/en/news.atom" if lang == "en" else "/news.atom"
    return f"""<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" href="{b}favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/manifest.webmanifest">
<link rel="alternate" type="application/atom+xml" title="{T[lang]['feed']}" href="{feed}">
<link rel="preload" href="{b}assets/fonts/kurale-{f}-400-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="{b}assets/fonts/onest-{f}-400-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="{b}assets/brand.css">
<link rel="stylesheet" href="{b}assets/site.css">{alternates}"""


def header(active, b, lang="ru", other=None):
    t = T[lang]
    p = prefix(b, lang)
    home = p or "./"

    def nav(href, label, key):
        cur = ' aria-current="page"' if key == active else ""
        return f'<a href="{href}"{cur}>{label}</a>'

    switch = f'\n      <a class="lang" href="{other}" hreflang="{t["other_lang"]}" lang="{t["other_lang"]}">{t["other"]}</a>' if other else ""
    return f"""<a class="skip" href="#main">{t['skip']}</a>
<header class="site-header">
  <div class="wrap">
    <a class="brand" href="{home}" aria-label="{t['home']}">{BRAND}<span class="brand-name">{t['brand']}</span></a>
    <nav class="nav" aria-label="{t['sections']}">
      {nav(f"{home}#games", t['games'], 'games')}
      {nav(f"{p}about.html", t['about'], 'about')}
      {nav(f"{p}support.html", t['support'], 'support')}{switch}
    </nav>
  </div>
</header>"""


def footer(b, lang="ru", games=(), other=None):
    """Подвал: знак и строка о студии, игры, студия, помощь, почта; язык и год — внизу.
    games — [(адрес, название)] из tools/games.json (build.py): новая игра появится сама."""
    t = T[lang]
    p = prefix(b, lang)
    home = p or "./"
    game_links = "\n".join(f'        <li><a href="{p}{slug}/">{name}</a></li>' for slug, name in games)
    switch = f'\n    <a class="lang" href="{other}" hreflang="{t["other_lang"]}" lang="{t["other_lang"]}">{t["other"]}</a>' if other else ""
    return f"""<footer class="site-footer">
  <div class="band-wrap" aria-hidden="true"><svg class="band" height="34"></svg></div>
  <div class="wrap footer-main">
    <div class="footer-about">
      <a class="brand" href="{home}" aria-label="{t['home']}">{BRAND}<span class="brand-name">{t['brand']}</span></a>
      <p>{t['tagline']}</p>
    </div>
    <nav class="footer-col" aria-labelledby="footer-games">
      <h2 id="footer-games">{t['games']}</h2>
      <ul>
{game_links}
      </ul>
    </nav>
    <nav class="footer-col" aria-labelledby="footer-studio">
      <h2 id="footer-studio">{t['studio_col']}</h2>
      <ul>
        <li><a href="{p}about.html">{t['about']}</a></li>
        <li><a href="{p}news.html">{t['news']}</a></li>
        <li><a href="{TELEGRAM}" rel="me">Telegram</a></li>
        <li><a href="{VK}" rel="me">{t['vk']}</a></li>
        <li><a href="{p}press.html">{t['press']}</a></li>
        <li><a href="{p}brand.html">{t['brandbook']}</a></li>
      </ul>
    </nav>
    <nav class="footer-col" aria-labelledby="footer-help">
      <h2 id="footer-help">{t['help']}</h2>
      <ul>
        <li><a href="{p}support.html">{t['support']}</a></li>
        <li><a href="{p}privacy.html">{t['privacy']}</a></li>
      </ul>
    </nav>
    <div class="footer-col">
      <h2>{t['mail']}</h2>
      <ul class="footer-mail">
        <li>hello@gornitsa.games<span>{t['mail_hello']}</span></li>
        <li>support@gornitsa.games<span>{t['mail_support']}</span></li>
        <li>press@gornitsa.games<span>{t['mail_press']}</span></li>
      </ul>
    </div>
  </div>
  <div class="wrap footer-bottom">
    <span>© <span data-year>2026</span> {t['studio']}</span>{switch}
  </div>{seller(lang, "line")}
</footer>"""
