"""Новости сайта из папки news/ (устав: docs/10-channels.md и docs/08-publishing.md).

Новость — файл news/<ГГГГ-ММ-ДД>-<имя>.ru.md и, по желанию, такой же .en.md:

    ---
    date: 2026-09-27
    title: «Вотчина» — в браузере, без установки
    ---
    Первый абзац — анонс: он же идёт на главную и в ленту.

    Дальше — текст в Markdown, как у страниц игр: абзацы, списки, **жирный**, ссылки.

build.py собирает из них страницу «Новости» (news.html, en/news.html), ленту Atom
(news.atom, en/news.atom) и три свежие новости на главной. Новость с ошибкой в сайт не
попадает: build.py пишет причину, tools/check.py считает её ошибкой.
Без сторонних библиотек: build.py запускается и на сервере.
"""
import functools, pathlib, re

from md import SITE, attr, body_errors, esc, inline, render_body

ROOT = pathlib.Path(__file__).resolve().parent.parent
NEWS = ROOT / "news"
TITLE_MAX = 90

MONTHS = {
    "ru": ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября",
           "октября", "ноября", "декабря"],
    "en": ["January", "February", "March", "April", "May", "June", "July", "August", "September",
           "October", "November", "December"],
}
T = {
    "ru": {"page": "/news.html", "feed": "/news.atom", "feed_title": "Горница — новости",
           "eyebrow": "Новости", "latest": "Что нового", "all": "Все новости", "empty": "Новостей пока нет.",
           "author": "Горница"},
    "en": {"page": "/en/news.html", "feed": "/en/news.atom", "feed_title": "Gornitsa — news",
           "eyebrow": "News", "latest": "What’s new", "all": "All news", "empty": "No news yet.",
           "author": "Gornitsa"},
}


def human_date(date, lang):
    y, m, d = (int(x) for x in date.split("-"))
    return f"{d} {MONTHS[lang][m - 1]} {y}"


@functools.lru_cache(maxsize=None)
def load(lang):
    """Новости одного языка, свежие сверху, и ошибки в файлах."""
    items, errors = [], []
    for p in sorted(NEWS.glob(f"*.{lang}.md")):
        name = p.relative_to(ROOT).as_posix()
        news_id = p.name[: -len(f".{lang}.md")]
        m = re.match(r"---\n(.*?)\n---\n(.*)", p.read_text(encoding="utf-8"), re.S)
        if not m:
            errors.append(f"{name}: нет полей между строками --- в начале файла")
            continue
        meta = {}
        for line in m.group(1).splitlines():
            key, _, value = line.partition(":")
            meta[key.strip()] = value.strip().strip('"')
        date, title, body = meta.get("date", ""), meta.get("title", ""), m.group(2).strip()
        errs = []
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date) or not news_id.startswith(date + "-"):
            errs.append("date — ГГГГ-ММ-ДД, та же дата, что в начале имени файла")
        if not re.fullmatch(r"[0-9a-z-]+", news_id):
            errs.append("имя файла — латиницей в нижнем регистре, цифры и дефисы")
        if not title:
            errs.append("нет поля title")
        elif len(title) > TITLE_MAX:
            errs.append(f"title: {len(title)} знаков, можно до {TITLE_MAX}")
        if not body:
            errs.append("нет текста")
        first = m.group(1).count("\n") + 4  # строка файла, с которой начинается текст
        errs += body_errors(m.group(2), first)
        if re.search(r"^#{2,3} ", body, re.M):
            errs.append("заголовков в новости нет — только абзацы и списки")
        if errs:
            errors += [f"{name}: {e}" for e in errs]
            continue
        items.append({"id": news_id, "date": date, "title": title, "body": body,
                      "lead": body.split("\n\n")[0].replace("\n", " ")})
    items.sort(key=lambda i: (i["date"], i["id"]), reverse=True)
    return items, errors


def page(lang):
    """Список новостей для news.html."""
    items, _ = load(lang)
    if not items:
        return f'      <p>{T[lang]["empty"]}</p>'
    out = []
    for i in items:
        out.append(f"""      <article class="news-item" id="{i["id"]}">
        <p class="news-date"><time datetime="{i["date"]}">{human_date(i["date"], lang)}</time></p>
        <h2>{esc(i["title"])}</h2>
{render_body(i["body"], "        ")}
      </article>""")
    return "\n".join(out)


def latest(lang, base, n=3):
    """Три свежие новости для главной; нет новостей — нет и блока."""
    items, _ = load(lang)
    if not items:
        return ""
    t = T[lang]
    href = "news.html" if (lang == "ru" and base == "") else t["page"]
    rows = "\n".join(f"""        <li>
          <time datetime="{i["date"]}">{human_date(i["date"], lang)}</time>
          <h3><a href="{href}#{i["id"]}">{esc(i["title"])}</a></h3>
          <p>{inline(i["lead"])}</p>
        </li>""" for i in items[:n])
    return f"""  <section class="section" id="news" aria-labelledby="news-title" style="padding-top: 0">
    <div class="wrap">
      <div class="section-head">
        <p class="eyebrow">{t["eyebrow"]}</p>
        <h2 id="news-title">{t["latest"]}</h2>
      </div>
      <ul class="news-list">
{rows}
      </ul>
      <p class="principles-more"><a href="{href}">{t["all"]}</a></p>
    </div>
  </section>

"""


def atom(lang):
    """Лента Atom: у каждой новости — полный текст; время — полдень по Москве."""
    items, _ = load(lang)
    t = T[lang]
    stamp = lambda d: f"{d}T12:00:00+03:00"
    updated = stamp(items[0]["date"]) if items else "2026-09-26T12:00:00+03:00"
    entries = []
    for i in items:
        url = f'{SITE}{t["page"]}#{i["id"]}'
        entries.append(f"""  <entry>
    <id>{url}</id>
    <title>{esc(i["title"])}</title>
    <link rel="alternate" type="text/html" href="{attr(url)}"/>
    <published>{stamp(i["date"])}</published>
    <updated>{stamp(i["date"])}</updated>
    <content type="html">{esc(render_body(i["body"], ""))}</content>
  </entry>""")
    return f"""<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="{lang}" xml:base="{SITE}/">
  <id>{SITE}{t["page"]}</id>
  <title>{t["feed_title"]}</title>
  <link rel="alternate" type="text/html" href="{SITE}{t["page"]}"/>
  <link rel="self" type="application/atom+xml" href="{SITE}{t["feed"]}"/>
  <updated>{updated}</updated>
  <author><name>{t["author"]}</name><uri>{SITE}/</uri></author>
  <icon>{SITE}/favicon.ico</icon>
{chr(10).join(entries)}
</feed>
"""
