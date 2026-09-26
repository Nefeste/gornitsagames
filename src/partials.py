BRAND = open(__file__.replace("partials.py", "brandmark.svg")).read().strip()

def head(b):
    return f"""<link rel="icon" href="{b}favicon.svg" type="image/svg+xml">
<link rel="preload" href="{b}assets/fonts/kurale-cyrillic-400-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="{b}assets/fonts/onest-cyrillic-400-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="{b}assets/site.css">"""

def header(active, b):
    def nav(href, label, key):
        cur = ' aria-current="page"' if key == active else ""
        return f'<a href="{href}"{cur}>{label}</a>'
    return f"""<a class="skip" href="#main">К содержимому</a>
<header class="site-header">
  <div class="wrap">
    <a class="brand" href="{b or './'}" aria-label="Горница, на главную">{BRAND}<span class="brand-name">Горница</span></a>
    <nav class="nav" aria-label="Разделы">
      {nav(f"{b or './'}#games", 'Игры', 'games')}
      {nav(f"{b or './'}#about", 'О студии', 'about')}
      {nav(f"{b}support.html", 'Поддержка', 'support')}
    </nav>
  </div>
</header>"""

def footer(b):
    return f"""<footer class="site-footer">
  <div class="band-wrap" aria-hidden="true"><svg class="band" height="34"></svg></div>
  <div class="wrap">
    <span>© <span data-year>2026</span> Студия «Горница»</span>
    <nav aria-label="Документы">
      <a href="{b}support.html">Поддержка</a>
      <a href="{b}privacy.html">Политика конфиденциальности</a>
      <span>gornitsa.games@gmail.com</span>
    </nav>
  </div>
</footer>"""
