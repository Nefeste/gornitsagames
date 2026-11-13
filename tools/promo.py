"""Путь игрока к игре: то, что сайт добавляет к готовым страницам, чтобы человек дошёл до RuStore.

Страницы игр и карточки на главной собирает tools/games.py из store/site/ игр и руками их не правят
(ADR студии 0015). Всё, что знает только сайт, — здесь; вызывает build.py перед tools/seo.py (ссылки
на RuStore потом идут через /go/<игра>).

- Карточка на главной: у вышедшей игры — официальная кнопка «Скачайте из RuStore» (её берём со страницы
  игры, даже если игра забыла ссылку в карточке); у игры в разработке — «Записаться в тест».
- Страница игры: рядом с кнопкой RuStore — QR-код для тех, кто открыл страницу на компьютере (игра
  ставится на телефон); внизу — блок «Скачать» (или «Игра ещё в работе» со ссылкой на тест и каналы)
  и «Ещё игры „Горницы“» — три другие игры, вышедшие — первыми.
"""
import html, re

import qr, seo
from md import SITE, attr

T = {
    "ru": {
        "badge": "Скачайте «{name}» из RuStore", "test": "Записаться в тест", "testers": "testers.html",
        "qr_label": "QR-код: «{name}» в RuStore", "qr": "Открыли на компьютере? Наведите камеру телефона на код — откроется RuStore.",
        "get": "Скачать «{name}»", "get_text": "Игра ставится на телефон с Android из RuStore.", "how": "Как установить", "support": "support.html", "price": "Цена",
        "soon": "«{name}» ещё в работе", "soon_text": "До выхода игру получают участники закрытого теста. О выходе в RuStore напишем в каналах студии.",
        "tg": "Telegram", "vk": "ВКонтакте",
        "more": "Ещё игры «Горницы»", "all": "Все игры студии", "home": "/#games",
        "soon_head": "Скоро — можно сыграть раньше всех в закрытом тесте",
        "live": "В RuStore", "dev": "В разработке", "test_st": "Закрытый тест",
    },
    "en": {
        "badge": "Download {name} from RuStore", "test": "Join the test", "testers": "testers.html",
        "qr_label": "QR code: {name} on RuStore", "qr": "On a computer? Point your phone camera at the code to open RuStore.",
        "get": "Get {name}", "get_text": "The game installs on an Android phone from RuStore.", "how": "How to install", "support": "support.html", "price": "Price",
        "soon": "{name} is still in the works", "soon_text": "Before release the game goes to closed test participants. We’ll post in the studio channels when it reaches RuStore.",
        "tg": "Telegram", "vk": "VK",
        "more": "More Gornitsa games", "all": "All games", "home": "/en/#games",
        "soon_head": "Coming soon — play early in a closed test",
        "live": "On RuStore", "dev": "In development", "test_st": "Closed test",
    },
}

BADGE = '<a class="store-badge" href="{url}"><img src="/assets/stores/rustore.svg" width="128" height="46" alt="{alt}"{lazy}></a>'


def qr_block(slug, name, lang):
    t = T[lang]
    code = qr.svg(f"{SITE}/go/{slug}", attr(t["qr_label"].format(name=name)))
    return f'<div class="qr">{code}<p>{t["qr"]}</p></div>'


def cards(page, lang, go, tg, vk):
    """Главная: низ каждой карточки игры — действие. Вышла — кнопка RuStore, в работе — запись в тест."""
    t = T[lang]
    pre = "/en/" if lang == "en" else ""

    def card(m):
        slug, block = m.group(1), m.group(2)
        name = seo.text((re.search(r"<h3><a[^>]*>(.*?)</a></h3>", block, re.S) or [None, slug])[1])
        links = re.search(r'(<div class="game-links">\n)(.*?)(\n\s*</div>)', block, re.S)
        if not links:
            return m.group(0)
        rows = [l for l in links.group(2).split("\n") if "rustore.ru/" not in l]
        store = go.get(slug, "")
        if 'status-live' in block and "rustore.ru/" in store:
            get = ('          <div class="game-get">\n            '
                   + BADGE.format(url=store, alt=attr(t["badge"].format(name=name)), lazy=' loading="lazy"') + "\n          </div>\n")
        else:
            get = ""
            rows.append(f'            <a href="{pre}{t["testers"]}">{t["test"]}</a>')
        new = get + "          " + links.group(1) + "\n".join(rows) + links.group(3)
        return m.group(0).replace("          " + links.group(0), new, 1)

    page = re.sub(r"<!-- game:([a-z0-9-]+) [^>]*-->(.*?)<!-- /game:\1 -->", card, page, flags=re.S)
    # Вышедшие игры — первой сеткой, игры в разработке — второй: порядок внутри задаёт src/index.html,
    # а в какую сетку идёт карточка — её статус, так что вышедшая игра переедет наверх сама.
    soon = [m.group(0) for m in re.finditer(r"        <!-- game:([a-z0-9-]+) [^>]*-->.*?<!-- /game:\1 -->\n", page, re.S)
            if "status-live" not in m.group(0)]
    for block in soon:
        page = page.replace(block, "", 1)
    grid = (f'      <p class="eyebrow games-sub" id="soon">{t["soon_head"]}</p>\n      <div class="games">\n'
            + "".join(soon) + "      </div>\n") if soon else ""
    return page.replace("{{GAMES_SOON}}\n", grid, 1)


def game_page(page, slug, lang, go, names, tg, vk):
    """Страница игры: QR у кнопки RuStore, внизу — «Скачать» или «ещё в работе» и другие игры студии."""
    t = T[lang]
    pre = "/en" if lang == "en" else ""
    name = dict(names).get(slug, slug)
    store = go.get(slug, "")
    live = 'class="store-badge"' in page and "rustore.ru/" in store
    e = html.escape
    if live:
        # верх: код — сразу после кнопок
        page = re.sub(r'(    <div class="actions">\n.*?\n    </div>\n)',
                      lambda m: m.group(1) + f"    {qr_block(slug, name, lang)}\n", page, count=1, flags=re.S)
        price = re.search(rf"<dt>{t['price']}</dt><dd>(.*?)</dd>", page, re.S)
        cost = f' {t["price"]}: {seo.text(price.group(1))}.' if price else ""
        get = f"""    <section class="get" aria-labelledby="get-title">
      <div>
        <h2 id="get-title">{e(t["get"].format(name=name))}</h2>
        <p>{t["get_text"]}{e(cost)} <a href="{pre}/{t["support"]}#install">{t["how"]}</a></p>
        <div class="actions">
          {BADGE.format(url=store, alt=attr(t["badge"].format(name=name)), lazy=' loading="lazy"')}
        </div>
      </div>
      {qr_block(slug, name, lang)}
    </section>
"""
    else:
        get = f"""    <section class="get" aria-labelledby="get-title">
      <div>
        <h2 id="get-title">{e(t["soon"].format(name=name))}</h2>
        <p>{t["soon_text"]}</p>
        <div class="actions">
          <a class="btn btn-primary" href="{pre}/{t["testers"]}">{t["test"]}</a>
          <a class="btn btn-ghost" href="{tg}">{t["tg"]}</a>
          <a class="btn btn-ghost" href="{vk}">{t["vk"]}</a>
        </div>
      </div>
    </section>
"""
    others = []
    for other, _ in names:
        g = seo.game_info(other, lang) if other != slug else None
        if g:
            others.append((g["status"] != "live", len(others), other, g))
    tiles = []
    for _, _, other, g in sorted(others)[:3]:
        st = {"live": t["live"], "test": t["test_st"]}.get(g["status"], t["dev"])
        tiles.append(f"""        <a class="more-tile more-game" href="{pre}/{other}/">
          <img class="game-icon" src="/assets/games/{other}-icon.webp" width="192" height="192" alt="" loading="lazy">
          <h3>{e(g["name"])}</h3>
          <p>{e(g["lead"])}</p>
          <span class="more-go">{st} <span aria-hidden="true">→</span></span>
        </a>""")
    more = f"""    <section class="more-games" aria-labelledby="more-games-title">
      <h2 id="more-games-title">{t["more"]}</h2>
      <div class="more-tiles">
{chr(10).join(tiles)}
      </div>
      <p class="principles-more"><a href="{t["home"]}">{t["all"]}</a></p>
    </section>
""" if tiles else ""
    return page.replace("    </article>\n  </div>\n</main>", "    </article>\n" + get + more + "  </div>\n</main>", 1)
