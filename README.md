# gornitsa.games

Сайт студии мобильных игр «Горница» на русском и английском: главная, страницы игр студии, новости, страница для прессы, поддержка, политика конфиденциальности и страница 404. Сайт статический: HTML, CSS и немного JavaScript, без сборщиков и зависимостей. Шрифты (Kurale и Onest, лицензия SIL OFL) раздаются с того же сервера, поэтому сайт не обращается к Google и другим внешним сервисам. В репозитории шрифтов и готовых страниц нет: их скачивает `deploy/fetch-fonts.sh` и собирает `build.py`.

Состояние сайта, что дальше и что ждёт владельца — [`STATUS.md`](STATUS.md).

## Структура

```
src/                  шаблоны страниц (редактировать тексты здесь)
  index.html
  about.html          «О студии»: миссия, ценности, обещания игрокам (пересказ устава студии)
  brand.html          брендбук: знак, цвета, шрифты, орнамент — вживую из стилей сайта
  news.html           «Новости»: список собирает build.py из папки news/ (см. «Новости»)
  press.html          «Для прессы»: студия коротко, карточки игр (между метками press:<игра> их
                      собирает tools/games.py), знак и почта для прессы
  support.html
  privacy.html        единая политика конфиденциальности (у каждой вышедшей игры — свой раздел)
  404.html
  votchina/, nardy/,  страницы игр: index.html собирает tools/games.py из store/site/ игры —
  anamnez/, skazy/,   здесь не правится (см. [`docs/game-pages.md`](docs/game-pages.md)); рядом — страницы сайта: удаление
  uzory/              профиля (delete.html у «Вотчины», «Сказов» и нард), турниры «Вотчины»,
                      votchina/privacy.html — запасная переадресация на общую политику (на машине
                      адрес /votchina/privacy отдаёт nginx: 301, deploy/nginx/locations.conf)
  en/                 английская версия тех же страниц
  partials.py         общая шапка, подвал и <head> на обоих языках (игры в подвале build.py берёт
                      из tools/games.json и <h1> их страниц — новая игра появится там сама)
  brandmark.svg       знак «Горницы» для шапки
news/                 новости: <дата>-<имя>.ru.md и .en.md (см. «Новости»)
site/                 сайт, который выкладывается на сервер (страницы *.html собирает build.py)
  assets/brand.css    токены бренда: копия brand/tokens.css из Nefeste/gornitsa, здесь не правится
  assets/site.css     стили
  assets/site.js      узор-раскраска на главной, орнамент, кнопка «Скопировать»
  assets/games/       баннеры, значки и снимки экрана игр (WebP)
  assets/fonts/       шрифты woff2 (скачивает deploy/fetch-fonts.sh)
  assets/stores/rustore.svg   официальная кнопка «Скачайте из RuStore» (см. [`docs/game-pages.md`](docs/game-pages.md))
  assets/og-studio.png, og-studio-en.png   картинка 1200 × 630 для ссылок на страницы без своей
                      (у страниц игр — своя); build.py ставит её и поля og: сам
  assets/icons/, apple-touch-icon.png, favicon.ico, manifest.webmanifest   значки для телефонов,
                      вкладок и поисковиков; картинки студии перерисовывает tools/brand-assets.mjs
  .well-known/security.txt   куда писать об уязвимостях; срок — до Expires, check.py напомнит
  favicon.svg, robots.txt, sitemap.xml
  go/<игра>.html      запасные страницы /go/<игра> и llms.txt, en/llms.txt — собирает build.py
build.py              собирает site/*.html из src/, build/go.conf — переадресации /go/ для nginx
build/                что собирается не для сайта (build/go.conf), в git не лежит
tools/
  games.json          игры, чьи страницы собираются из store/site/, и ссылки, которые знает только сайт
  site.json           настройки, которые знает только сайт: реквизиты продавца (выключатель),
                      страница разработчика в RuStore (см. «Поиск…» и «Реквизиты продавца»)
  seo.py              хлебные крошки, FAQPage, NewsArticle, /go/<игра>, llms.txt (см. «Поиск…» ниже)
  devlog.py           черновик «Дневника разработки» по STATUS.md игр (docs/devlog.md)
  fetch-games.sh      забирает store/ с main игр в games/ (закрытые — токеном GAMES_READ_TOKEN)
  games.py            собирает страницы, карточки на главной и для прессы и картинки игр из
                      games/*/store/site/
  games-pr.sh         открывает или обновляет PR «Сайт: обновления игр» (workflow games.yml)
  md.py               Markdown страниц игр и новостей — без сторонних библиотек
  news.py             новости: страница, лента Atom (news.atom) и три свежие на главной
  check.py            проверяет собранный сайт: ссылки, якоря, размеры картинок игр, разметку
                      для поисковиков (ld+json), срок security.txt, title и описания (длины,
                      повторы), sitemap.xml, ссылки llms.txt, реквизиты продавца
  brand-assets.mjs    рисует картинку для ссылок и значки из знака и шрифтов сайта (Playwright)
games.lock.json       из какого коммита игры и из каких файлов собраны её страница и картинки
.github/workflows/games.yml   «Страницы игр»: каждую ночь — PR «Сайт: обновления игр»
.github/workflows/site.yml    «Проверка сайта»: на каждый PR — build.py, check.py, shellcheck (см. «Проверка PR»)
.github/CODEOWNERS            весь репозиторий — путь владельца: PR сайта сливает он (ADR студии 0018)
deploy/
  setup-server.sh     первичная настройка VPS: nginx, HTTPS, файрвол, вход по ключам, fail2ban
  ssh.sh              вход на сервер только по ключам, root — без входа (см. docs/machine.md, «Вход на сервер»)
  journald.conf       журналы systemd — три дня (ставит update-site.sh)
  deploy.sh           выкладка сайта со своего компьютера
  fetch-fonts.sh      скачивает шрифты в site/assets/fonts
  bootstrap.sh        настройка сервера одной командой и автообновление из GitHub
  update-site.sh      автообновление (запускается таймером раз в 5 минут)
  seni-bootstrap.sh   установщик Сеней — шлюза студии — на отдельной машине (см. docs/machine.md)
  nginx/              настройка nginx сайта (см. «Обновления сайта»)
    gornitsa.games.conf        до выпуска сертификата — первая установка
    gornitsa.games.https.conf  с HTTPS: HTTP/2, редирект с http и www — сама настройка на машине
    headers.conf, locations.conf   заголовки безопасности (в каждом месте сайта, с HSTS) и места
    apply.sh           ставит всё это на машину с проверкой и откатом
  votchina/           сервер игры «Вотчина» на этой же машине (см. docs/machine.md)
    setup.sh          настройка: Node, служба, ключи, таймеры
    pull.sh           сборка из ветки vps и выгрузка базы (каждые 2 минуты)
    nginx.sh          сайт votchina.gornitsa.games в nginx и его сертификат
    backup.sh         копия базы раз в сутки
  nardy/              сервер игры «Длинные нарды» на этой же машине (см. docs/machine.md)
    setup.sh          настройка: Bun, служба, ключ, таймеры
    pull.sh           сборка из ветки vps (каждые 2 минуты)
    nginx.sh          nardy.gornitsa.games в nginx (с WebSocket) и его сертификат
    backup.sh         копия базы раз в сутки
  skazy/              сервер заставы «Сказов» на этой же машине (см. docs/machine.md)
    setup.sh          настройка: Bun, служба, ключ, таймеры
    pull.sh           сборка из ветки vps (каждые 2 минуты)
    nginx.sh          skazy.gornitsa.games в nginx (журнал без адресов) и его сертификат
    backup.sh         копия базы раз в сутки
    restore-check.sh  проверка восстановления из копии раз в месяц
  uzory/              закрытая веб-версия «Узоров» на этой же машине (см. docs/machine.md)
    setup.sh          настройка: папки, ключ шифрования сборки, таймер
    pull.sh           сборка из ветки vps (каждые 5 минут)
    nginx.sh          /uzory/test/ в nginx сайта: только HTTPS и по паролю
    password.sh       имя и пароль владельца: sudo uzory-password
  monitor/            мониторинг ресурсов машины (см. docs/machine.md, «Мониторинг машины»)
    setup.sh          настройка: пользователь, таймеры раз в минуту и раз в сутки
    monitor.py        замеры в SQLite и сводки за сутки — только стандартная библиотека Python
    sitestats.py      посещаемость сайта без IP из журнала nginx: сутки и неделя (site-week.json)
    nginx.sh          /.well-known/monitor/ в nginx сайта: только HTTPS и по паролю
    password.sh       имя и пароль владельца: sudo gornitsa-monitor-password
  backup/             копии баз на компьютер владельца по SFTP (см. docs/machine.md, «Копии баз»)
    setup.sh          настройка: sqlite3, age, таймер в 03:30 по Москве, пользователь backup
    snapshot.sh       снимок, integrity_check, gzip и age, manifest.json: sudo gornitsa-backup
    keys.sh           открытые ключи владельца SSH и age: sudo gornitsa-backup-keys
    sftp.sh           backup — только SFTP на чтение, chroot /srv/backup
    targets.conf.example   что снимать: базы и архив настроек машины (на машине — /etc/gornitsa-backup/targets.conf)
    status.py         тревоги копий для «Сторожа» раз в 10 минут — и здесь, и на машине «Сеней»
    check-backup.py   проверка восстановления — запускает владелец у себя раз в месяц
    owner/            забор копий на компьютер владельца: Windows (pull-backup.ps1), macOS
                      (pull-backup.sh и задание launchd); копия GitHub раз в неделю (backup-github.py)
  seo/                поиск: файлы подтверждения, IndexNow, /go/ в nginx (см. «Поиск…» ниже)
    apply.sh          ставит всё это в каждом проходе автообновления
    indexnow.py       изменённые страницы из sitemap.xml — в yandex.com/indexnow
docs/backup.md        инструкция владельцу: ключи, забор копий, где хранить, проверка восстановления, копия GitHub
docs/restore.md       восстановление с нуля: машина сайта, машина «Сеней», доступ к GitHub, компьютер владельца
docs/devlog.md        «Дневник разработки»: шаблон, порядок, правила
docs/machine.md       машина сайта и серверы игр: запуск с нуля, вход, мониторинг, копии баз, «Сени»
docs/game-pages.md    страницы игр из store/site/, публикация в RuStore
docs/journal/         журнал по месяцам (ГГГГ-ММ.md)
docs/README.md        оглавление документов

## Как посмотреть локально

```bash
bash deploy/fetch-fonts.sh
python3 build.py
python3 -m http.server 8000 -d site
# открыть http://localhost:8000
```

## Новости

Новость — файл `news/<ГГГГ-ММ-ДД>-<имя>.ru.md` (имя латиницей, через дефис) и такой же `.en.md`,
если новость нужна и на английской странице:

```
---
date: 2026-09-27
title: «Вотчина» — в браузере, без установки
---
Первый абзац — анонс: он же идёт на главную и в ленту.

Дальше — абзацы и списки, **жирный**, *курсив*, ссылки [текст](https://…). Без заголовков,
HTML и картинок.
```

`build.py` собирает из папки страницу «Новости», ленты `news.atom` и `en/news.atom` и три свежие
новости на главной; новость с ошибкой в сайт не попадает, а `tools/check.py` называет ошибку.
О чём пишем, кто готовит новость и кто публикует — устав студии, [`docs/10-channels.md`](https://github.com/Nefeste/gornitsa/blob/main/docs/10-channels.md).

Поле `review: draft` — черновик: такую новость сайт не показывает (ни на странице, ни в ленте,
ни на главной), а `tools/check.py` напоминает о ней. Одобряет владелец ([`review: checked` — только человек](https://github.com/Nefeste/gornitsa/blob/main/docs/05-rules.md#контент)): `review: checked` или
без поля. Так устроен «Дневник разработки» — черновик раз в две недели по `STATUS.md` игр
(`tools/devlog.py`, шаблон и порядок — [`docs/devlog.md`](docs/devlog.md)).

## Поиск: Вебмастер, Search Console, IndexNow

Поручение 06 (решения владельца №29 и №30). Кодов подтверждения и ключей в репозитории нет — они
лежат на машине в `/etc/gornitsa-site/`; ставит их `deploy/seo/apply.sh` в каждом проходе
автообновления.

- **Подтверждение сайта.** Файл из Вебмастера (`yandex_<код>.html`) или Search Console
  (`google<код>.html`) владелец кладёт в `/etc/gornitsa-site/verification/` — через 5 минут он
  в корне сайта. Другие имена не копируются. Выкладка сайта (`rsync --delete`) их стирает,
  а тот же проход возвращает.
- **IndexNow.** Ключ — `/etc/gornitsa-site/indexnow.key`: нет — скрипт создаёт его сам, файл ключа
  `<ключ>.txt` лежит в корне сайта. После каждого прохода `deploy/seo/indexnow.py` сравнивает
  страницы из `sitemap.xml` с прошлой отправкой (отпечатки — `/var/lib/gornitsa-site/indexnow.json`)
  и шлёт изменённые адреса в `https://yandex.com/indexnow`; не принято — пришлёт снова через 5 минут.
  Выключить: `sudo touch /etc/gornitsa-site/indexnow-off`. Новая страница — строка в
  `site/sitemap.xml`, иначе `tools/check.py` не пропустит.
- **`/go/<игра>`** — переход на игру в RuStore: `https://gornitsa.games/go/votchina`. Ссылки
  страниц на карточку RuStore `build.py` сам ведёт через `/go/<игра>`, так переходы видны в журнале
  сервера без cookie и счётчиков. Куда ведёт — карточка RuStore со страницы игры, у игры без
  карточки — её страница на сайте; поменяется сама, когда у игры появится карточка. Переадресацию
  (302) делает nginx: `build/go.conf` → `/etc/nginx/snippets/gornitsa.games-go.conf`, не прошёл
  `nginx -t` — остаётся прежний. Пока сниппета нет, работает запасная страница `site/go/<игра>.html`.
  Ссылки в соцсетях, письмах и новостях — тоже через `/go/<игра>`.
- **Разметка для поисковиков** (`tools/seo.py`, `tools/games.py`, `src/partials.py`): `Organization`
  и `WebSite` на главной (в `sameAs` — каналы и страница разработчика в RuStore из `tools/site.json`),
  `VideoGame` на страницах игр (с `offers`, одной возрастной категорией `contentRating` и `inLanguage`),
  `BreadcrumbList` на внутренних страницах, `FAQPage` на поддержке — из её же вопросов, `NewsArticle`
  на «Новостях». На странице игры — блок «Коротко»: что это, платформа, цена, интернет, возраст,
  где скачать.
- **Для ассистентов и нейропоиска** — `/llms.txt` и `/en/llms.txt`: студия, игры со ссылками,
  документы и почта. Пишет `build.py` из `tools/games.json` и страниц игр.
- **Заголовки.** У каждой страницы `<title>` до 60 знаков и описание 120–160, без повторов
  (`tools/check.py`). У страниц игр это поля `title` и `description` в `store/site/page.*.md` игры:
  там описание вне 120–160 — напоминание проверки, правка — PR в игру.

## Реквизиты продавца

Закон о защите прав потребителей при продаже на расстоянии требует показать покупателю продавца:
ФИО ИП, ИНН, ОГРНИП и адрес для претензий. Продавец — ИП, зарегистрированное по решению №3;
реквизиты — `seller` в `tools/site.json` (внесены 06.10.2026). Они стоят в подвале (короткое имя
`short`), на странице поддержки (раздел «Продавец») и в политике (раздел 1); `address` — без
подписи «Адрес для претензий», её ставит сайт. Поле пустое, ИНН не из 12 цифр или ОГРНИП не из 15 —
сайт не соберётся. Выключить — `"enabled": false`.

## Как поменять текст

1. Отредактируйте нужную страницу в `src/` (шапку и подвал — в `src/partials.py`). Страницы игр
   и карточки игр на главной здесь не правятся: они собираются из `store/site/` игр (см. [`docs/game-pages.md`](docs/game-pages.md)).
2. Запустите `python3 build.py`.
3. Сделайте `git push` — через несколько минут сервер обновит сайт сам.

Стили и скрипты редактируются прямо в `site/assets/`, кроме `brand.css`: это копия
`brand/tokens.css` из устава студии [`Nefeste/gornitsa`](https://github.com/Nefeste/gornitsa)
с пометкой источника в первой строке; порядок обновления копий —
[`brand/README.md`](https://github.com/Nefeste/gornitsa/blob/main/brand/README.md#как-пользоваться-этими-файлами).

Страницы «О студии» и «Брендбук» пересказывают устав студии (`docs/01-mission.md`,
`docs/02-values.md`, `brand/README.md`) по порядку из устава:
[`docs/02-values.md`](https://github.com/Nefeste/gornitsa/blob/main/docs/02-values.md) (сначала устав, потом сайт, в том же заходе).

У каждой страницы есть пара на другом языке: русская `src/support.html` и английская `src/en/support.html`. Правьте обе, а новую страницу добавьте в список `pages` в `build.py` — тогда в шапке появится переключатель языка, а в `<head>` — ссылки `hreflang`. Надписи, которые рисует скрипт (подсказки на пяльцах, кнопка «Скопировать»), — в начале `site/assets/site.js`.

## Обновления сайта

Изменения попадают в `main` через PR, а сливает их владелец ([ADR студии 0018](https://github.com/Nefeste/gornitsa/blob/main/adr/0018-change-classes-automerge.md)): сервер проверяет GitHub каждые 5 минут и выкладывает новую версию сам. Журнал: `journalctl -u gornitsa-update -n 50`. Скрипт автообновления тоже берётся из репозитория (`deploy/update-site.sh`), а при изменении `deploy/votchina/`, `deploy/nardy/`, `deploy/skazy/` или `deploy/uzory/` он доводит настройку сервера этой игры, при изменении `deploy/monitor/` — мониторинга машины.

Настройка nginx самого сайта тоже идёт из репозитория: при изменении `deploy/nginx/` (и когда сертификат уже выпущен) `update-site.sh` запускает `deploy/nginx/apply.sh`. Тот сохраняет нынешние файлы, ставит `gornitsa.games.https.conf` как `/etc/nginx/sites-available/gornitsa.games.conf`, заголовки и места — в `/etc/nginx/snippets/gornitsa-site-*.conf` (`server_tokens off` — в самом конфиге сайта: в `http{}` машины он уже задан, второй раз там nginx не пропускает), проверяет `nginx -t`, перезагружает nginx и убеждается, что `https://gornitsa.games/` отвечает 200, а `http://` — 301. Что-то не так — всё возвращается как было, а в `/var/lib/gornitsa-nginx-site` пишется `failed <версия>`: эту версию скрипт больше не пробует, пока `deploy/nginx/` не поменяется снова. Блоки сертификата в конфиге — в том виде, в каком их пишет certbot, поэтому продление работает по-прежнему. Заголовки безопасности — в `headers.conf` и подключаются в каждом `location`: nginx не складывает `add_header` сервера и места, и заголовки на уровне сервера молча пропадали бы.

Если репозиторий когда-нибудь закроют (это новое решение владельца вместо [ADR студии 0017](https://github.com/Nefeste/gornitsa/blob/main/adr/0017-repo-visibility.md)), сайт можно выкладывать со своего компьютера: `./deploy/deploy.sh IP_СЕРВЕРА` (нужен SSH-доступ пользователем deploy, его создаёт `deploy/setup-server.sh`).

## Проверка PR

Workflow «Проверка сайта» (`.github/workflows/site.yml`) на каждый PR и push в `main` на `ubuntu-24.04`
собирает сайт (`python3 build.py`), проверяет его (`python3 tools/check.py`) и скрипты сервера
(`shellcheck deploy/**/*.sh`) — то же, что стоит прогнать у себя перед push. Секретов у него нет,
права — только чтение. Это быстрые проверки на PR по [ADR студии 0019](https://github.com/Nefeste/gornitsa/blob/main/adr/0019-ci-on-pr.md); APK сайт
не собирает. Сборка — меньше минуты, а у открытого репозитория минуты Actions не тратятся.

## Куда делись разделы

Эти разделы перенесены в [`docs/machine.md`](docs/machine.md) и [`docs/game-pages.md`](docs/game-pages.md) без изменений текста (ссылки
вида «README, «Вход на сервер»» в старых заметках читать там):

| Раздел | Где |
|---|---|
| Запуск с нуля (домен, VPS, DNS, GitHub, настройка одной командой) | [`docs/machine.md`](docs/machine.md#запуск-с-нуля) |
| Вход на сервер | [`docs/machine.md`](docs/machine.md#вход-на-сервер) |
| Мониторинг машины | [`docs/machine.md`](docs/machine.md#мониторинг-машины) |
| Копии баз | [`docs/machine.md`](docs/machine.md#копии-баз) |
| Сени — шлюз студии | [`docs/machine.md`](docs/machine.md#сени--шлюз-студии-отдельная-машина) |
| Сервер игры «Вотчина», «Длинные нарды», заставы «Сказов» | [`docs/machine.md`](docs/machine.md#сервер-игры-вотчина) |
| Закрытая веб-версия «Узоров» | [`docs/machine.md`](docs/machine.md#закрытая-веб-версия-узоров) |
| Перед публикацией игр в RuStore | [`docs/game-pages.md`](docs/game-pages.md#перед-публикацией-игр-в-rustore) |
| Страницы игр — из `store/site/` игр (ночной PR, снимки, «Для прессы», политика, страницы удаления) | [`docs/game-pages.md`](docs/game-pages.md#страницы-игр--из-storesite-игр) |
