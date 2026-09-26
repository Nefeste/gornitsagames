#!/usr/bin/env python3
"""Собирает страницы из src/ в site/: подставляет общую шапку, подвал и <head>."""
import pathlib, sys
root = pathlib.Path(__file__).parent
sys.path.insert(0, str(root / "src"))
import partials

pages = {"index.html": "home", "support.html": "support", "privacy.html": "privacy", "404.html": "404"}
for name, key in pages.items():
    html = (root / "src" / name).read_text(encoding="utf-8")
    base = "/" if key == "404" else ""
    html = html.replace("{{HEAD}}", partials.head(base)).replace("{{HEADER}}", partials.header(key, base)).replace("{{FOOTER}}", partials.footer(base))
    (root / "site" / name).write_text(html, encoding="utf-8")
    print("site/" + name)
