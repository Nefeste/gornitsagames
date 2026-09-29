"""Markdown сайта — только то, что разрешает устав (docs/08-publishing.md, раздел «Сайт»):
абзацы, заголовки ## и ###, списки, **жирный**, *курсив*, ссылки https:// и mailto:.
Без сторонних библиотек: им пользуются и tools/games.py, и build.py (новости) на сервере."""
import html, re

SITE = "https://gornitsa.games"

esc = lambda s: html.escape(str(s), quote=False)
attr = lambda s: esc(s).replace('"', "&quot;")  # атрибуты — в двойных кавычках

MAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[a-z]{2,}")
LINK = re.compile(r"\[([^\]\n]+)\]\(([^)\s]+)\)")


def url_ok(u):
    return u.startswith("https://") or u.startswith("mailto:")


def local(u):
    """Ссылки на сам сайт — от корня: так они работают и на тестовой копии сайта."""
    return u[len(SITE):] or "/" if u.startswith(SITE + "/") or u == SITE else u


def inline(text):
    keep = []

    def link(m):
        keep.append(f'<a href="{attr(local(m.group(2)))}">{emph(esc(m.group(1)))}</a>')
        return f"\x00{len(keep) - 1}\x00"

    s = LINK.sub(link, text)
    s = emph(esc(s))
    s = MAIL.sub(lambda m: f'<span class="mail-address" style="font-size: inherit">{m.group(0)}</span>', s)
    return re.sub(r"\x00(\d+)\x00", lambda m: keep[int(m.group(1))], s)


def emph(s):
    s = re.sub(r"\*\*(\S(?:.*?\S)?)\*\*", r"<strong>\1</strong>", s)
    return re.sub(r"(?<![\*\w])\*(\S(?:.*?\S)?)\*(?![\*\w])", r"<em>\1</em>", s)


def body_errors(md, first=1):
    errs = []
    for n, line in enumerate(md.splitlines(), first):
        if re.search(r"<[A-Za-z/!]", line):
            errs.append(f"строка {n}: HTML не пропускается")
        if "![" in line:
            errs.append(f"строка {n}: картинок в тексте нет — снимки идут в shots")
        if line.lstrip().startswith("|"):
            errs.append(f"строка {n}: таблиц нет")
        if re.match(r"#(?!##? )|####", line):
            errs.append(f"строка {n}: заголовки — только ## и ###")
        for m in LINK.finditer(line):
            if not url_ok(m.group(2)):
                errs.append(f"строка {n}: ссылка {m.group(2)} — только https:// или mailto:")
    return errs


def render_body(md, indent="      "):
    out, para, items, kind = [], [], [], None

    def flush():
        nonlocal para, items, kind
        if para:
            out.append(f"<p>{inline(' '.join(para))}</p>")
        if items:
            out.append(f"<{kind}>")
            out.extend(f"  <li>{inline(' '.join(i))}</li>" for i in items)
            out.append(f"</{kind}>")
        para, items, kind = [], [], None

    for line in md.splitlines():
        s = line.strip()
        if not s:
            flush()
        elif m := re.match(r"(#{2,3}) (.+)", s):
            flush()
            if m.group(1) == "##" and out:
                out.append("")
            tag = "h2" if m.group(1) == "##" else "h3"
            out.append(f"<{tag}>{inline(m.group(2).strip())}</{tag}>")
        elif m := re.match(r"(-|\d+\.) (.+)", s):
            k = "ul" if m.group(1) == "-" else "ol"
            if para or (kind and kind != k):
                flush()
            kind = k
            items.append([m.group(2)])
        elif items and line.startswith("  "):
            items[-1].append(s)
        else:
            if items:
                flush()
            para.append(s)
    flush()
    return "\n".join(indent + l if l else "" for l in out)
