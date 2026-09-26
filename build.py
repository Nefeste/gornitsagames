#!/usr/bin/env python3
"""Собирает страницы из src/ в site/: подставляет общую шапку, подвал и <head>."""
import pathlib, sys
root = pathlib.Path(__file__).parent
sys.path.insert(0, str(root / "src"))
import partials

# страница: (раздел в шапке, основа ссылок). Страницы во вложенных папках и 404
# ссылаются на общие файлы от корня сайта ("/"), остальные — относительно ("").
pages = {
    "index.html": ("home", ""),
    "support.html": ("support", ""),
    "privacy.html": ("privacy", ""),
    "404.html": ("404", "/"),
    "votchina/index.html": ("games", "/"),
    "votchina/tournaments.html": ("games", "/"),
    "votchina/privacy.html": ("games", "/"),
    "votchina/delete.html": ("games", "/"),
}
for name, (key, base) in pages.items():
    html = (root / "src" / name).read_text(encoding="utf-8")
    html = html.replace("{{HEAD}}", partials.head(base)).replace("{{HEADER}}", partials.header(key, base)).replace("{{FOOTER}}", partials.footer(base))
    out = root / "site" / name
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
    print("site/" + name)
