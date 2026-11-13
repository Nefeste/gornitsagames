import html, json, pathlib, re

BRAND = open(__file__.replace("partials.py", "brandmark.svg")).read().strip()
SITE = "https://gornitsa.games"
# Настройки, которые знает только сайт: реквизиты продавца, страница разработчика в RuStore
CONFIG = json.loads((pathlib.Path(__file__).resolve().parent.parent / "tools" / "site.json").read_text(encoding="utf-8"))
# Каналы студии (устав, docs/10-channels.md): подвал, страница поддержки, разметка для поисковиков
TELEGRAM = "https://t.me/gornitsa_games"
VK = "https://vk.com/gornitsa_games"
# Значки каналов в подвале (решение владельца 08.11.2026) — знаки Telegram и ВКонтакте из simple-icons 13.21.0
# (лицензия CC0; знаки — товарные знаки их владельцев, здесь — только как ссылка на наш канал там)
ICONS = {
    "telegram": "M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z",
    "vk": "m9.489.004.729-.003h3.564l.73.003.914.01.433.007.418.011.403.014.388.016.374.021.36.025.345.03.333.033c1.74.196 2.933.616 3.833 1.516.9.9 1.32 2.092 1.516 3.833l.034.333.029.346.025.36.02.373.025.588.012.41.013.644.009.915.004.98-.001 3.313-.003.73-.01.914-.007.433-.011.418-.014.403-.016.388-.021.374-.025.36-.03.345-.033.333c-.196 1.74-.616 2.933-1.516 3.833-.9.9-2.092 1.32-3.833 1.516l-.333.034-.346.029-.36.025-.373.02-.588.025-.41.012-.644.013-.915.009-.98.004-3.313-.001-.73-.003-.914-.01-.433-.007-.418-.011-.403-.014-.388-.016-.374-.021-.36-.025-.345-.03-.333-.033c-1.74-.196-2.933-.616-3.833-1.516-.9-.9-1.32-2.092-1.516-3.833l-.034-.333-.029-.346-.025-.36-.02-.373-.025-.588-.012-.41-.013-.644-.009-.915-.004-.98.001-3.313.003-.73.01-.914.007-.433.011-.418.014-.403.016-.388.021-.374.025-.36.03-.345.033-.333c.196-1.74.616-2.933 1.516-3.833.9-.9 2.092-1.32 3.833-1.516l.333-.034.346-.029.36-.025.373-.02.588-.025.41-.012.644-.013.915-.009ZM6.79 7.3H4.05c.13 6.24 3.25 9.99 8.72 9.99h.31v-3.57c2.01.2 3.53 1.67 4.14 3.57h2.84c-.78-2.84-2.83-4.41-4.11-5.01 1.28-.74 3.08-2.54 3.51-4.98h-2.58c-.56 1.98-2.22 3.78-3.8 3.95V7.3H10.5v6.92c-1.6-.4-3.62-2.34-3.71-6.92Z",
}


def icon(name):
    return f'<svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true" focusable="false"><path fill="currentColor" d="{ICONS[name]}"/></svg>'

T = {
    "ru": {
        "skip": "К содержимому", "brand": "Горница", "home": "Горница, на главную", "sections": "Разделы",
        "games": "Игры", "about": "О студии", "support": "Поддержка", "privacy": "Политика конфиденциальности", "terms": "Условия использования",
        "docs": "Документы", "studio": "Студия «Горница»", "brandbook": "Брендбук", "other": "English", "other_lang": "en", "fonts": "cyrillic",
        "tagline": "Спокойные, честные и понятные игры для RuStore.", "studio_col": "Студия", "help": "Помощь",
        "mail": "Почта", "mail_hello": "общая", "mail_support": "поддержка", "mail_press": "для прессы", "mail_qa": "тестирование", "testers": "Тестерам",
        "news": "Новости", "press": "Для прессы", "feed": "Новости «Горницы»", "vk": "ВКонтакте", "tg_label": "Telegram-канал «Горницы»", "vk_label": "«Горница» ВКонтакте", "channels": "Каналы студии", "wallpapers": "Обои", "creators": "Блогерам",
        "og_alt": "Знак «Горницы» — ромб из вышитых крестиков — и надпись «Светлая комната для хороших игр»",
        "seller": "Продавец", "seller_inn": "ИНН", "seller_ogrnip": "ОГРНИП",
        "seller_address": "Адрес для претензий", "seller_email": "Почта для претензий",
    },
    "en": {
        "skip": "Skip to content", "brand": "Gornitsa", "home": "Gornitsa, home page", "sections": "Sections",
        "games": "Games", "about": "About", "support": "Support", "privacy": "Privacy policy", "terms": "Terms of use",
        "docs": "Documents", "studio": "Gornitsa Studio", "brandbook": "Brand book", "other": "Русский", "other_lang": "ru", "fonts": "latin",
        "tagline": "Calm, honest and clear games for RuStore.", "studio_col": "Studio", "help": "Help",
        "mail": "Email", "mail_hello": "general", "mail_support": "support", "mail_press": "press", "mail_qa": "testing", "testers": "Testers",
        "news": "News", "press": "Press", "feed": "Gornitsa news", "vk": "VK", "tg_label": "Gornitsa on Telegram", "vk_label": "Gornitsa on VK", "channels": "Studio channels", "wallpapers": "Wallpapers", "creators": "Creators",
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
<meta name="theme-color" content="#111816" media="(prefers-color-scheme: dark)">
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
    """Подвал: знак, строка о студии и значки каналов; игры, студия, помощь с почтой; язык и год — внизу.
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
      <ul class="footer-social" aria-label="{t['channels']}">
        <li><a href="{TELEGRAM}" rel="me" aria-label="{t['tg_label']}" title="{t['tg_label']}">{icon("telegram")}</a></li>
        <li><a href="{VK}" rel="me" aria-label="{t['vk_label']}" title="{t['vk_label']}">{icon("vk")}</a></li>
      </ul>
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
        <li><a href="{p}press.html">{t['press']}</a></li>
        <li><a href="{p}creators.html">{t['creators']}</a></li>
        <li><a href="{p}testers.html">{t['testers']}</a></li>
        <li><a href="{p}brand.html">{t['brandbook']}</a></li>
        <li><a href="{p}wallpapers.html">{t['wallpapers']}</a></li>
      </ul>
    </nav>
    <nav class="footer-col" aria-labelledby="footer-help">
      <h2 id="footer-help">{t['help']}</h2>
      <ul>
        <li><a href="{p}support.html">{t['support']}</a></li>
        <li><a href="{p}privacy.html">{t['privacy']}</a></li>
        <li><a href="{p}terms.html">{t['terms']}</a></li>
      </ul>
      <ul class="footer-mail" aria-label="{t['mail']}">
        <li>hello@gornitsa.games<span>{t['mail_hello']}</span></li>
        <li>support@gornitsa.games<span>{t['mail_support']}</span></li>
        <li>press@gornitsa.games<span>{t['mail_press']}</span></li>
        <li>qa@gornitsa.games<span>{t['mail_qa']}</span></li>
      </ul>
    </nav>
  </div>
  <div class="wrap footer-bottom">
    <span>© <span data-year>2026</span> {t['studio']}</span>{switch}
  </div>{seller(lang, "line")}
</footer>"""
