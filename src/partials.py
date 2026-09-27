BRAND = open(__file__.replace("partials.py", "brandmark.svg")).read().strip()

T = {
    "ru": {
        "skip": "К содержимому", "brand": "Горница", "home": "Горница, на главную", "sections": "Разделы",
        "games": "Игры", "about": "О студии", "support": "Поддержка", "privacy": "Политика конфиденциальности",
        "docs": "Документы", "studio": "Студия «Горница»", "other": "English", "other_lang": "en", "fonts": "cyrillic",
    },
    "en": {
        "skip": "Skip to content", "brand": "Gornitsa", "home": "Gornitsa, home page", "sections": "Sections",
        "games": "Games", "about": "About", "support": "Support", "privacy": "Privacy policy",
        "docs": "Documents", "studio": "Gornitsa Studio", "other": "Русский", "other_lang": "ru", "fonts": "latin",
    },
}


def prefix(b, lang):
    """Начало ссылок на страницы: "" или "/" у русской версии, "/en/" у английской."""
    return b + "en/" if lang == "en" else b


def head(b, lang="ru", alternates=""):
    f = T[lang]["fonts"]
    return f"""<link rel="icon" href="{b}favicon.svg" type="image/svg+xml">
<link rel="preload" href="{b}assets/fonts/kurale-{f}-400-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="{b}assets/fonts/onest-{f}-400-normal.woff2" as="font" type="font/woff2" crossorigin>
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
      {nav(f"{home}#about", t['about'], 'about')}
      {nav(f"{p}support.html", t['support'], 'support')}{switch}
    </nav>
  </div>
</header>"""


def footer(b, lang="ru"):
    t = T[lang]
    p = prefix(b, lang)
    return f"""<footer class="site-footer">
  <div class="band-wrap" aria-hidden="true"><svg class="band" height="34"></svg></div>
  <div class="wrap">
    <span>© <span data-year>2026</span> {t['studio']}</span>
    <nav aria-label="{t['docs']}">
      <a href="{p}support.html">{t['support']}</a>
      <a href="{p}privacy.html">{t['privacy']}</a>
      <span>hello@gornitsa.games</span>
    </nav>
  </div>
</footer>"""
