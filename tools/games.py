#!/usr/bin/env python3
"""Страницы игр из store/site/ их репозиториев (ADR студии 0015, устав Nefeste/gornitsa,
docs/08-publishing.md, раздел «Сайт»).

    python3 tools/games.py --src games            собрать страницы из games/<игра>/store/
    python3 tools/games.py --check ../skazy       только проверить store/site/ одной игры

Для каждой игры из tools/games.json читает store/site/page.ru.md (и page.en.md), проверяет
формат и пишет src/<игра>/index.html, src/en/<игра>/index.html, карточку на главной
(между метками <!-- game:<игра> --> и <!-- /game:<игра> --> в src/index.html и
src/en/index.html) и картинки в site/assets/games/. Из какого коммита игры взята страница
и из каких картинок (отпечаток пикселей) — в games.lock.json: картинки, у которых пиксели
не изменились, не перекодируются и в PR не попадают.
Игра с ошибками в store/site/ пропускается, причина — в отчёте (--report, описание PR).

Нужны PyYAML и Pillow (в workflow — точные версии из .github/workflows/games.yml).
"""
import argparse, hashlib, io, json, pathlib, re, subprocess, sys

import yaml
from PIL import Image, ImageOps

from md import SITE, attr, body_errors, esc, inline, local, render_body, url_ok

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = ROOT / "tools" / "games.json"
LOCK = ROOT / "games.lock.json"
ASSETS = ROOT / "site" / "assets" / "games"
PAPER = (247, 247, 242)  # --paper из brand/tokens.css: фон под прозрачными картинками

# Паспорт игры (facts): поле — подпись ru/en. Строки идут в этом порядке, какие есть.
FACTS = {
    "platform": ("Платформа", "Platform"),
    "price": ("Цена", "Price"),
    "age": ("Возраст", "Age rating"),
    "players": ("Игроки", "Players"),
    "internet": ("Интернет", "Internet"),
    "languages": ("Языки", "Languages"),
}

# Сколько знаков можно в полях (docs/08-publishing.md устава).
LIMITS = {"name": 40, "title": 60, "description": 220, "kind": 40, "lead": 160, "caption": 30,
          "alt": 160, "card.text": 240, "card.points": 80, "links.text": 40, "note": 200,
          **{f"facts.{k}": 40 for k in FACTS}}

STATUS = {  # класс плашки, плашка ru/en, приписка к жанру ru/en
    "dev": ("dev", "В разработке", "In development", "в разработке", "in development"),
    "test": ("dev", "Закрытый тест", "Closed test", "закрытый тест", "closed test"),
    "live": ("live", "В RuStore", "On RuStore", None, None),
}

T = {
    "ru": {"crumbs_label": "Навигация", "crumbs": "← Все игры студии", "home": "/#games",
           "shots": "Снимки экрана", "privacy": "Политика конфиденциальности",
           "delete": "Удалить профиль", "other": "English", "about": "Об игре",
           "site_name": "Горница", "banner": "Баннер 1024 × 500", "icon": "Значок 192 × 192",
           "page_shots": "Страница и снимки экрана"},
    "en": {"crumbs_label": "Navigation", "crumbs": "← All games", "home": "/en/#games",
           "shots": "Screenshots", "privacy": "Privacy policy", "delete": "Delete your profile",
           "other": "По-русски", "about": "About the game", "site_name": "Gornitsa",
           "banner": "Banner 1024 × 500", "icon": "Icon 192 × 192", "page_shots": "Page and screenshots"},
}

# Картинки: размер на сайте, формат, качество.
SPEC = {
    "icon": ((192, 192), "WEBP", 90),
    "feature": ((1024, 500), "WEBP", 86),
    "shot-portrait": ((540, 960), "WEBP", 84),
    "shot-landscape": ((960, 540), "WEBP", 84),
    # Снимок крупно — по нажатию на снимок (site.js): мелкий текст игры читается.
    # Больше исходника не растягивается.
    "shot-portrait-full": ((1080, 1920), "WEBP", 86),
    "shot-landscape-full": ((1920, 1080), "WEBP", 86),
    "og": ((1200, 630), "PNG", None),
    # Обложка над названием: 3 : 1, на телефоне края срезаются до 2 : 1.
    "cover": ((1920, 640), "WEBP", 82),
    "cover-small": ((960, 320), "WEBP", 82),
}

# ---------- store/site/page.*.md ----------

def read_page(path):
    text = path.read_text(encoding="utf-8")
    m = re.match(r"---\n(.*?)\n---\n?(.*)", text, re.S)
    if not m:
        raise ValueError("нет полей между строками --- в начале файла")
    meta = yaml.safe_load(m.group(1)) or {}
    if not isinstance(meta, dict):
        raise ValueError("поля в начале файла — не словарь YAML")
    meta["_line"] = text[:m.start(2)].count("\n") + 1  # с какой строки файла начинается текст
    return meta, m.group(2)


def image_size(path):
    with Image.open(path) as im:
        return im.size


def near(a, b, tol=0.02):
    return abs(a - b) <= tol * b


def validate(meta, body, store):
    errs = []

    def text(key, value, need=True):
        if value is None or value == "":
            if need:
                errs.append(f"нет поля {key}")
            return
        if not isinstance(value, str):
            errs.append(f"{key} — не строка")
        elif len(value) > LIMITS[key]:
            errs.append(f"{key}: {len(value)} знаков, можно до {LIMITS[key]}")
        elif re.search(r"<[A-Za-z/!]", value):
            errs.append(f"{key}: HTML не пропускается")

    def links(key, value):
        if value is None:
            return
        if not isinstance(value, list):
            errs.append(f"{key} — не список")
            return
        for i, l in enumerate(value, 1):
            if not isinstance(l, dict) or not l.get("text") or not l.get("url"):
                errs.append(f"{key} {i}: нужны text и url")
                continue
            text("links.text", l["text"])
            if not url_ok(l["url"]):
                errs.append(f"{key} {i}: ссылка {l['url']} — только https:// или mailto:")

    def image(key, rel, check):
        if not rel:
            errs.append(f"нет поля {key}")
            return None
        p = (store / rel).resolve()
        if store.resolve() not in p.parents or not p.is_file():
            errs.append(f"{key}: нет файла store/{rel}")
            return None
        if p.suffix.lower() not in (".png", ".webp"):
            errs.append(f"{key}: store/{rel} — нужен PNG или WebP")
            return None
        w, h = image_size(p)
        if msg := check(w, h):
            errs.append(f"{key}: store/{rel} {w} × {h} — {msg}")
        return w, h

    for key in ("name", "title", "description", "kind", "lead"):
        text(key, meta.get(key))
    text("note", meta.get("note"), need=False)
    if meta.get("status") not in STATUS:
        errs.append(f"status: {meta.get('status')!r} — нужно dev, test или live")
    links("links", meta.get("links"))

    image("icon", meta.get("icon"), lambda w, h: None if w == h and w >= 192 else "нужен квадрат от 192 × 192")
    image("feature", meta.get("feature"),
          lambda w, h: None if near(w / h, 1024 / 500) and w >= 1024 else "нужно 1024 × 500")
    if meta.get("og"):
        image("og", meta["og"], lambda w, h: None if w >= 1200 and h >= 630 else "нужно не меньше 1200 × 630")
    if meta.get("cover"):
        image("cover", meta["cover"], lambda w, h: None if near(w / h, 3) and w >= 1920 else "нужно 3 : 1 от 1920 × 640")

    facts = meta.get("facts")
    if facts is not None:
        if not isinstance(facts, dict):
            errs.append("facts — не словарь: строки вида «platform: Android»")
        else:
            for k, v in facts.items():
                if k in FACTS:
                    text(f"facts.{k}", v)
                else:
                    errs.append(f"facts: поля {k} нет — можно {', '.join(FACTS)}")
            if len(facts) < 2:
                errs.append("facts: нужно от 2 строк")

    shots = meta.get("shots")
    if not isinstance(shots, list) or not 3 <= len(shots) <= 8:
        errs.append("shots: нужно от 3 до 8 снимков")
        shots = shots if isinstance(shots, list) else []
    forms = set()
    for i, s in enumerate(shots, 1):
        if not isinstance(s, dict):
            errs.append(f"снимок {i}: нужны file, caption и alt")
            continue
        text("caption", s.get("caption"))
        text("alt", s.get("alt"))

        def shape(w, h):
            if near(w / h, 9 / 16) and w >= 540:
                forms.add("portrait")
            elif near(w / h, 16 / 9) and h >= 540:
                forms.add("landscape")
            else:
                return "нужно 9 : 16 от 540 × 960 или 16 : 9 от 960 × 540"

        image(f"снимок {i}", s.get("file"), shape)
    if len(forms) > 1:
        errs.append("shots: снимки разной формы — нужны все 9 : 16 или все 16 : 9")

    card = meta.get("card")
    if not isinstance(card, dict):
        errs.append("нет поля card")
    else:
        text("card.text", card.get("text"))
        pts = card.get("points")
        if not isinstance(pts, list) or not 2 <= len(pts) <= 4:
            errs.append("card.points: нужно от 2 до 4 пунктов")
        else:
            for p in pts:
                text("card.points", p)
        links("card.links", card.get("links"))

    errs += body_errors(body, meta.get("_line", 1))
    if not body.strip():
        errs.append("нет текста страницы")
    return errs


# ---------- картинки ----------

def load_rgb(path):
    im = Image.open(path)
    im.load()
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        bg = Image.new("RGB", im.size, PAPER)
        bg.paste(im, mask=im.getchannel("A"))
        return bg
    return im.convert("RGB")


def pixels_key(data):
    """Отпечаток пикселей, а не байтов файла: картинку, которую игра пересохранила без изменений
    (другое сжатие PNG, метаданные), сайт не перекодирует и в PR не несёт."""
    with Image.open(io.BytesIO(data)) as im:
        im = im.convert("RGBA")
        return hashlib.sha256(f"{im.width}x{im.height}:".encode() + im.tobytes()).hexdigest()[:16]


def target_size(spec, src_size):
    """Размер картинки на сайте. Крупный снимок (-full) не бывает больше исходника."""
    (w, h), _, _ = SPEC[spec]
    if spec.endswith("-full"):
        k = min(1, src_size[0] / w, src_size[1] / h)
        w, h = round(w * k), round(h * k)
    return w, h


def encode(path, spec, cover_og=False):
    _, fmt, q = SPEC[spec]
    raw = path.read_bytes()
    with Image.open(io.BytesIO(raw)) as im:
        w, h = target_size(spec, im.size)
        if im.format == "WEBP" and im.size == (w, h) and fmt == "WEBP":
            return raw  # уже готова для сайта — без второго сжатия
    im = load_rgb(path)
    if spec == "og" and not cover_og:
        # Из обложки 1024 × 500: вписать по ширине, поля — цвета верхнего и нижнего края.
        k = w / im.width
        im = im.resize((w, round(im.height * k)), Image.LANCZOS)
        out = Image.new("RGB", (w, h))
        top = (h - im.height) // 2
        edge = lambda y: tuple(sum(c) // im.width for c in zip(*[im.getpixel((x, y)) for x in range(im.width)]))
        out.paste(Image.new("RGB", (w, top), edge(0)), (0, 0))
        out.paste(Image.new("RGB", (w, h - top - im.height), edge(im.height - 1)), (0, top + im.height))
        out.paste(im, (0, top))
        im = out
    else:
        im = ImageOps.fit(im, (w, h), Image.LANCZOS)
    buf = io.BytesIO()
    if fmt == "WEBP":
        im.save(buf, "WEBP", quality=q, method=6)
    else:
        im.save(buf, "PNG", optimize=True)
    return buf.getvalue()


# ---------- страница и карточка ----------

def page_path(slug, lang):
    return f"/{slug}/" if lang == "ru" else f"/en/{slug}/"


def render_page(slug, lang, meta, body, img, extra_meta, has_delete, privacy_anchor, source):
    t = T[lang]
    st = STATUS[meta["status"]]
    eyebrow = meta["kind"] + (f" · {st[3] if lang == 'ru' else st[4]}" if st[3] else "")
    path = page_path(slug, lang)
    shots = img["shots"]
    landscape = shots and shots[0]["w"] > shots[0]["h"]
    cls = "shots shots-wide" if landscape else ("shots shots-4" if len(shots) in (4, 8) else "shots")
    fig = []
    for i, s in enumerate(shots):
        lazy = ' loading="lazy"' if i else ""
        # Ссылка на крупный снимок: site.js открывает его поверх страницы, без JS — просто картинкой.
        fw, fh = s["full_size"]
        fig.append(f'      <figure><a class="shot" href="/assets/games/{s["full"]}" data-size="{fw}x{fh}">'
                   f'<img src="/assets/games/{s["name"]}" '
                   f'width="{s["w"]}" height="{s["h"]}" alt="{attr(s["alt"])}"{lazy}></a>'
                   f'<figcaption>{esc(s["caption"])}</figcaption></figure>')
    actions = ""
    if meta.get("links"):
        btns = [f'      <a class="btn {"btn-primary" if i == 0 else "btn-ghost"}" href="{attr(local(l["url"]))}">{esc(l["text"])}</a>'
                for i, l in enumerate(meta["links"])]
        actions = '    <div class="actions">\n' + "\n".join(btns) + "\n    </div>\n"
    pre = "" if lang == "ru" else "/en"
    links = [f'<a href="{attr(l["url"])}">{esc(l["text"])}</a>' for l in extra_meta]
    links.append(f'<a href="{pre}/privacy.html#{privacy_anchor}">{t["privacy"]}</a>')
    if has_delete:
        links.append(f'<a href="{pre}/{slug}/delete.html">{t["delete"]}</a>')
    other = "en" if lang == "ru" else "ru"
    links.append(f'<a href="{page_path(slug, other)}" hreflang="{other}" lang="{other}">{t["other"]}</a>')
    note = f'      <p class="meta">{inline(meta["note"])}</p>\n' if meta.get("note") else ""
    cover = ""
    if img.get("cover"):
        # Картинка без надписей: название рядом, текстом. Декор — поэтому alt пустой.
        cover = (f'    <div class="game-cover"><img src="/assets/games/{img["cover"]}" '
                 f'srcset="/assets/games/{img["cover_small"]} 960w, /assets/games/{img["cover"]} 1920w" '
                 f'sizes="(min-width: 1160px) 1072px, 100vw" width="1920" height="640" alt="" fetchpriority="high"></div>\n')
    facts = meta.get("facts") or {}
    passport = ""
    if facts:
        rows = [f'      <div><dt>{FACTS[k][0 if lang == "ru" else 1]}</dt><dd>{esc(facts[k])}</dd></div>'
                for k in FACTS if facts.get(k)]
        passport = '    <dl class="game-facts">\n' + "\n".join(rows) + "\n    </dl>\n"
    studio = {"@type": "Organization", "@id": f"{SITE}/#studio", "name": t["site_name"], "url": f"{SITE}/"}
    ld = {"@context": "https://schema.org", "@type": "VideoGame", "name": meta["name"], "url": f"{SITE}{path}",
          "description": meta["description"], "genre": meta["kind"], "image": f"{SITE}/assets/games/{img['og']}",
          "screenshot": [f"{SITE}/assets/games/{s['full']}" for s in shots],
          "applicationCategory": "GameApplication", "operatingSystem": "Android",
          "author": studio, "publisher": studio}
    if facts.get("platform"):
        ld["gamePlatform"] = facts["platform"]
    if facts.get("age"):
        ld["contentRating"] = facts["age"]
    store = [l["url"] for l in meta.get("links") or [] if "rustore.ru/" in l["url"]]
    if meta["status"] == "live" and store:
        ld["installUrl"] = store[0]
    ld_text = json.dumps(ld, ensure_ascii=False).replace("</", "<\\/")
    return f"""<!doctype html>
<!-- Собрано tools/games.py из {source}.
     Не правьте здесь: правка — в store/site/ игры, сайт заберёт её сам (ADR студии 0015). -->
<html lang="{lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>{esc(meta["title"])}</title>
<meta name="description" content="{attr(meta["description"])}">
<link rel="canonical" href="{SITE}{path}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="{t["site_name"]}">
<meta property="og:title" content="{attr(meta["title"])}">
<meta property="og:description" content="{attr(meta["lead"])}">
<meta property="og:url" content="{SITE}{path}">
<meta property="og:image" content="{SITE}/assets/games/{img["og"]}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="theme-color" content="#ecede6">
<script type="application/ld+json">{ld_text}</script>
{{{{HEAD}}}}
</head>
<body>
{{{{HEADER}}}}
<main id="main" class="doc">
  <div class="wrap">
    <nav class="crumbs" aria-label="{t["crumbs_label"]}"><a href="{t["home"]}">{t["crumbs"]}</a></nav>
{cover}    <header class="game-hero">
      <img class="game-icon" src="/assets/games/{img["icon"]}" width="192" height="192" alt="">
      <div>
        <p class="eyebrow">{esc(eyebrow)}</p>
        <h1>{esc(meta["name"])}</h1>
        <p class="lead">{esc(meta["lead"])}</p>
      </div>
    </header>
{actions}{passport}
    <section class="{cls}" aria-label="{t["shots"]}">
{chr(10).join(fig)}
    </section>

    <article class="doc-body">
{render_body(body)}
{note}      <p class="meta">{" · ".join(links)}</p>
    </article>
  </div>
</main>
{{{{FOOTER}}}}
<script src="/assets/site.js" defer></script>
</body>
</html>
"""


def render_card(slug, lang, meta, img, extra, lazy):
    t = T[lang]
    st = STATUS[meta["status"]]
    page = f"{slug}/" if lang == "ru" else f"/en/{slug}/"
    assets = "assets/games/" if lang == "ru" else "/assets/games/"
    card = meta["card"]
    pts = "\n".join(f"            <li>{esc(p)}</li>" for p in card["points"])
    links = [f'            <a href="{page}">{t["about"]}</a>']
    links += [f'            <a href="{attr(local(l["url"]))}">{esc(l["text"])}</a>' for l in (card.get("links") or []) + extra]
    return f"""        <article class="game">
          <a class="game-shot" href="{page}" tabindex="-1" aria-hidden="true"><img src="{assets}{img["feature"]}" width="1024" height="500" alt=""{' loading="lazy"' if lazy else ""}></a>
          <div class="game-top"><span class="game-kind">{esc(meta["kind"])}</span><span class="status status-{st[0]}">{st[1] if lang == "ru" else st[2]}</span></div>
          <h3><a href="{page}">{esc(meta["name"])}</a></h3>
          <p>{esc(card["text"])}</p>
          <ul>
{pts}
          </ul>
          <div class="game-links">
{chr(10).join(links)}
          </div>
        </article>
"""


def render_press(slug, lang, meta, img):
    """Карточка игры на странице «Для прессы»: коротко, паспорт и картинки — скачать."""
    t = T[lang]
    st = STATUS[meta["status"]]
    page = page_path(slug, lang)
    facts = meta.get("facts") or {}
    rows = "".join(f'<div><dt>{FACTS[k][0 if lang == "ru" else 1]}</dt><dd>{esc(facts[k])}</dd></div>'
                   for k in FACTS if facts.get(k))
    passport = f'\n            <dl class="game-facts">{rows}</dl>' if rows else ""
    return f"""        <article class="press-game">
          <img class="game-icon" src="/assets/games/{img["icon"]}" width="192" height="192" alt="">
          <div>
            <p class="eyebrow">{esc(meta["kind"])} · {(st[3] or "в RuStore") if lang == "ru" else (st[4] or "on RuStore")}</p>
            <h3><a href="{page}">{esc(meta["name"])}</a></h3>
            <p>{esc(meta["lead"])}</p>{passport}
            <p class="press-files"><a href="/assets/games/{img["feature"]}" download>{t["banner"]}</a> <a href="/assets/games/{img["icon"]}" download>{t["icon"]}</a> <a href="{page}">{t["page_shots"]}</a></p>
          </div>
        </article>
"""


# ---------- одна игра ----------

class Game:
    def __init__(self, cfg, src, lock):
        self.cfg, self.slug = cfg, cfg["slug"]
        self.store = src / self.slug / "store"
        self.lock = lock.get(self.slug, {})
        self.errors, self.files, self.images = [], {}, {}
        self.commit = git_head(src / self.slug)

    def load(self):
        pages = {}
        for lang in ("ru", "en"):
            p = self.store / "site" / f"page.{lang}.md"
            if not p.is_file():
                continue
            try:
                meta, body = read_page(p)
            except (ValueError, yaml.YAMLError) as e:
                self.errors.append(f"page.{lang}.md: {e}")
                continue
            self.errors += [f"page.{lang}.md: {e}" for e in validate(meta, body, self.store)]
            pages[lang] = (meta, body)
        return pages

    def image(self, rel, spec, base, lang_tag, taken, cover_og=False, suffix=""):
        """Имя картинки на сайте: <игра>-<имя файла>[-full]; у другого файла с тем же именем — -en."""
        src = (self.store / rel).resolve()
        stem = re.sub(rf"^{self.slug}-", "", pathlib.Path(rel).stem)
        ext = ".png" if SPEC[spec][1] == "PNG" else ".webp"
        name = f"{self.slug}-{base or stem}{suffix}{ext}"
        if taken.get(name, src) != src:
            name = f"{self.slug}-{base or stem}-{lang_tag}{suffix}{ext}"
        taken[name] = src
        data, how = src.read_bytes(), f":{spec}:{int(cover_og)}"
        key = "px" + pixels_key(data) + how
        old = self.lock.get("images", {}).get(name)
        bytes_key = hashlib.sha256(data).hexdigest()[:16] + how  # ключ в games.lock.json до 30.09.2026
        if old not in (key, bytes_key) or not (ASSETS / name).is_file():
            self.files[ASSETS / name] = encode(src, spec, cover_og)
        self.images[name] = key
        return name


def git_head(path):
    try:
        return subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"], capture_output=True,
                              text=True, check=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def put(doc, slug, kind, html):
    """Вставить html между метками <!-- kind:slug --> и <!-- /kind:slug --> страницы doc."""
    mark = re.compile(rf"(<!-- {kind}:{slug}\b[^>]*-->\n)(.*?)(^[ \t]*<!-- /{kind}:{slug} -->)", re.S | re.M)
    m = mark.search(doc["text"])
    if not m:
        return f"в {doc['path'].relative_to(ROOT)} нет меток <!-- {kind}:{slug} --> … <!-- /{kind}:{slug} -->"
    body = html(m.group(2)) if callable(html) else html
    doc["text"] = doc["text"][:m.start(2)] + body + doc["text"][m.end(2):]
    return None


def sync(cfg, src, lock, index):
    g = Game(cfg, src, lock)
    slug = g.slug
    if not (g.store / "site" / "page.ru.md").is_file():
        return g, f"— {slug}: нет store/site/page.ru.md, страница не меняется"
    pages = g.load()
    if g.errors:
        return g, f"✗ {slug}: страница не обновлена —\n" + "\n".join(f"  - {e}" for e in g.errors)
    repo = cfg["repo"]
    privacy = (ROOT / "src" / "privacy.html").read_text(encoding="utf-8")
    anchor = slug if f'id="{slug}"' in privacy else "upcoming"
    has_delete = (ROOT / "src" / slug / "delete.html").is_file()
    taken = {}
    for lang, (meta, body) in pages.items():
        img = {"icon": g.image(meta["icon"], "icon", "icon", lang, taken),
               "feature": g.image(meta["feature"], "feature", "feature", lang, taken)}
        if meta.get("og"):
            img["og"] = g.image(meta["og"], "og", "og", lang, taken, cover_og=True)
        else:
            img["og"] = g.image(meta["feature"], "og", "og", lang, taken)
        if meta.get("cover"):
            img["cover"] = g.image(meta["cover"], "cover", "cover", lang, taken)
            img["cover_small"] = g.image(meta["cover"], "cover-small", "cover", lang, taken, suffix="-960")
        img["shots"] = []
        for s in meta["shots"]:
            w, h = image_size(g.store / s["file"])
            spec = "shot-landscape" if w > h else "shot-portrait"
            name = g.image(s["file"], spec, None, lang, taken)
            full = g.image(s["file"], spec + "-full", None, lang, taken, suffix="-full")
            (sw, sh), _, _ = SPEC[spec]
            img["shots"].append({"name": name, "full": full, "full_size": target_size(spec + "-full", (w, h)),
                                 "w": sw, "h": sh, "alt": s["alt"], "caption": s["caption"]})
        source = f"store/site/page.{lang}.md репозитория {repo}"  # коммит — в games.lock.json
        out = ROOT / "src" / ("" if lang == "ru" else "en") / slug / "index.html"
        g.files[out] = render_page(slug, lang, meta, body, img, cfg.get("meta", {}).get(lang, []),
                                   has_delete, anchor, source).encode()
        extra = cfg.get("card", {}).get(lang, [])
        for err in (put(index[lang], slug, "game", lambda old: render_card(slug, lang, meta, img, extra, 'loading="lazy"' in old)),
                    put(index["press-" + lang], slug, "press", render_press(slug, lang, meta, img))):
            if err:
                g.errors.append(err)
    if g.errors:
        return g, f"✗ {slug}: страница не обновлена —\n" + "\n".join(f"  - {e}" for e in g.errors)
    changed = [p for p, data in g.files.items() if not p.is_file() or p.read_bytes() != data]
    return g, changed


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--src", type=pathlib.Path, help="папка с games/<игра>/store/")
    ap.add_argument("--check", type=pathlib.Path, help="проверить store/site/ одной игры и выйти")
    ap.add_argument("--report", type=pathlib.Path, help="куда записать отчёт для описания PR")
    a = ap.parse_args()

    if a.check:
        store, bad = a.check / "store", 0
        for lang in ("ru", "en"):
            p = store / "site" / f"page.{lang}.md"
            if p.is_file():
                try:
                    meta, body = read_page(p)
                except (ValueError, yaml.YAMLError) as e:
                    print(f"page.{lang}.md: {e}")
                    bad += 1
                    continue
                for e in validate(meta, body, store):
                    print(f"page.{lang}.md: {e}")
                    bad += 1
        print("store/site/ в порядке" if not bad else f"ошибок: {bad}")
        return 1 if bad else 0

    if not a.src:
        ap.error("нужен --src или --check")
    cfg = json.loads(CONFIG.read_text(encoding="utf-8"))["games"]
    lock = json.loads(LOCK.read_text(encoding="utf-8")) if LOCK.is_file() else {}
    # Страницы, куда игры вставляют свои карточки: главная (метки game:) и «Для прессы» (press:).
    index = {key: {"path": p, "text": p.read_text(encoding="utf-8")}
             for key, p in (("ru", ROOT / "src" / "index.html"), ("en", ROOT / "src" / "en" / "index.html"),
                            ("press-ru", ROOT / "src" / "press.html"), ("press-en", ROOT / "src" / "en" / "press.html"))}
    report, new_lock = [], dict(lock)
    for c in cfg:
        before = {k: v["text"] for k, v in index.items()}
        g, res = sync(c, a.src, lock, index)
        if isinstance(res, str):
            report.append(res)
            if res.startswith("✗"):
                for k in index:  # карточка упавшей игры не меняется
                    index[k]["text"] = before[k]
            continue
        cards = [index[k]["path"] for k in index if index[k]["text"] != before[k]]
        if not res and not cards:
            report.append(f"= {g.slug}: без изменений")
            continue
        pics_new = [p.name for p in sorted(res) if p.parent == ASSETS and not p.is_file()]
        pics_changed = [p.name for p in sorted(res) if p.parent == ASSETS and p.is_file()]
        for p in res:
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(g.files[p])
        new_lock[g.slug] = {"repo": c["repo"], "commit": g.commit, "images": dict(sorted(g.images.items()))}
        commit = f"{c['repo']}@{g.commit[:7]}" if g.commit else c["repo"]
        what = [p.relative_to(ROOT).as_posix() for p in sorted(res) if p.suffix == ".html"]
        what += [p.relative_to(ROOT).as_posix() + " (карточка)" for p in cards]
        if pics_new:
            what.append("новые картинки: " + ", ".join(f"`{n}`" for n in pics_new))
        if pics_changed:
            what.append("изменились картинки: " + ", ".join(f"`{n}`" for n in pics_changed))
        report.append(f"✓ {g.slug}: из {commit} — " + ", ".join(what))
    for v in index.values():
        if v["text"] != v["path"].read_text(encoding="utf-8"):
            v["path"].write_text(v["text"], encoding="utf-8")
    # Картинки игр, на которые больше ничего не ссылается, убираются.
    used = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "src").rglob("*.html"))
    synced = {line.split(":")[0][2:] for line in report if line.startswith("✓")}
    for f in sorted(ASSETS.glob("*")):
        if f.name.split("-")[0] in synced and f.name not in used:
            f.unlink()
            report.append(f"  убрана картинка `site/assets/games/{f.name}` — на неё больше нет ссылок")
    if new_lock != lock:
        LOCK.write_text(json.dumps(new_lock, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    text = "\n".join(report)
    print(text)
    if a.report:
        a.report.write_text(text + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
