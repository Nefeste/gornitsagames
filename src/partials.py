BRAND = open(__file__.replace("partials.py", "brandmark.svg")).read().strip()

T = {
    "ru": {
        "skip": "К содержимому", "brand": "Горница", "home": "Горница, на главную", "sections": "Разделы",
        "games": "Игры", "about": "О студии", "support": "Поддержка", "privacy": "Политика конфиденциальности",
        "docs": "Документы", "studio": "Студия «Горница»", "brandbook": "Брендбук", "other": "English", "other_lang": "en", "fonts": "cyrillic",
        "tagline": "Спокойные, честные и понятные игры для RuStore.", "studio_col": "Студия", "help": "Помощь",
        "mail": "Почта", "mail_hello": "общая", "mail_support": "поддержка", "mail_press": "для прессы",
        "og_alt": "Знак «Горницы» — ромб из вышитых крестиков — и надпись «Светлая комната для хороших игр»",
    },
    "en": {
        "skip": "Skip to content", "brand": "Gornitsa", "home": "Gornitsa, home page", "sections": "Sections",
        "games": "Games", "about": "About", "support": "Support", "privacy": "Privacy policy",
        "docs": "Documents", "studio": "Gornitsa Studio", "brandbook": "Brand book", "other": "Русский", "other_lang": "ru", "fonts": "latin",
        "tagline": "Calm, honest and clear games for RuStore.", "studio_col": "Studio", "help": "Help",
        "mail": "Email", "mail_hello": "general", "mail_support": "support", "mail_press": "press",
        "og_alt": "The Gornitsa mark, a diamond of cross-stitches, and the words “A bright room for good games”",
    },
}


def prefix(b, lang):
    """Начало ссылок на страницы: "" или "/" у русской версии, "/en/" у английской."""
    return b + "en/" if lang == "en" else b


def head(b, lang="ru", alternates=""):
    f = T[lang]["fonts"]
    return f"""<link rel="icon" href="/favicon.ico" sizes="any">
<link rel="icon" href="{b}favicon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="manifest" href="/manifest.webmanifest">
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
  </div>
</footer>"""
