#!/usr/bin/env bash
# uzory-nginx: закрытая веб-версия «Узоров» в nginx сайта — https://gornitsa.games/uzory/test/
# (спецификация docs/specs/2026-09-web.md в репозитории Nefeste/uzory). Ставит deploy/uzory/setup.sh;
# вызывают uzory-pull каждые 5 минут и uzory-password после смены пароля.
#
# Пишет /etc/nginx/snippets/gornitsa.games-uzory.conf:
#   - /uzory/test/ — из /opt/uzory/current/test/, только по HTTPS и только с именем и паролем
#     из /etc/uzory/test.htpasswd; пока файла паролей нет — 403 всем;
#   - /.well-known/uzory-age.pub — открытый ключ машины: им CI «Узоров» шифрует сборку в ветке vps;
#   - /uzory/v1/ — новые картинки по сети (наборы, подписанный каталог; кладёт их uzory-packs): каталог и
#     подпись — без кэша, наборы — навсегда (в имени набора — отпечаток содержимого). Запросы каталога —
#     в отдельный журнал без адресов /var/log/uzory/catalog.log: из него счётчики (uzory-stats). Не в
#     /var/log/nginx: его ротирует logrotate, а этот журнал ведёт сама свёртка (хранит строки семь дней).
#     Подпись и наборы в журналы запросов не пишутся вовсе (так в docs/specs/2026-09-packs.md «Узоров»):
#     адресов игроков в журналах нет;
# И /etc/nginx/conf.d/uzory-stats.conf — формат этого журнала (log_format живёт только на уровне http).
# Конфиг сайта подключает такие файлы строкой `include /etc/nginx/snippets/gornitsa.games-*.conf;`
# (deploy/nginx/gornitsa.games.conf). В конфиг на сервере, который уже поправил certbot, строку
# добавляет этот скрипт — один раз, сразу после `root /var/www/gornitsa.games;`.
# Новый конфиг не прошёл `nginx -t` — возвращается прежний.

set -euo pipefail

SITE=/etc/nginx/sites-available/gornitsa.games.conf
SNIPPET=/etc/nginx/snippets/gornitsa.games-uzory.conf
INCLUDE='include /etc/nginx/snippets/gornitsa.games-*.conf;'
PASSWD=/etc/uzory/test.htpasswd
STATS_CONF=/etc/nginx/conf.d/uzory-stats.conf

# Правила безопасности — как у сайта, плюс 'wasm-unsafe-eval' (CanvasKit — это WebAssembly)
# и blob: для картинок. Те же правила отдаёт сборке сценарий Playwright «Узоров» (tools/e2e/smoke.ts):
# меняете здесь — поменяйте и там.
CSP="default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"

render() {
  cat <<'CONF'
# «Узоры»: закрытая веб-версия. Файл пишет /usr/local/sbin/uzory-nginx (репозиторий gornitsagames,
# deploy/uzory/nginx.sh) — правки здесь затрутся.

location = /uzory/test {
    return 301 /uzory/test/;
}

location = /.well-known/uzory-age.pub {
    alias /var/www/uzory-meta/uzory-age.pub;
    default_type text/plain;
    add_header Cache-Control "no-cache" always;
}

# Новые картинки по сети (docs/03-server-api.md «Узоров»). Файлы кладёт uzory-packs из ветки packs.
location = /uzory/v1/catalog.json {
    alias /srv/gornitsa/uzory/v1/catalog.json;
    default_type application/json;
    # счётчики: время, строка запроса и код — без адресов (ADR 0012 «Узоров»)
    access_log /var/log/uzory/catalog.log uzory_stats;
    add_header Cache-Control "no-cache" always;
    add_header X-Content-Type-Options "nosniff" always;
}

location = /uzory/v1/catalog.sig {
    alias /srv/gornitsa/uzory/v1/catalog.sig;
    default_type text/plain;
    # второй запрос той же проверки: не считается и не пишется вовсе — ни с адресом, ни без
    access_log off;
    add_header Cache-Control "no-cache" always;
    add_header X-Content-Type-Options "nosniff" always;
}

location ^~ /uzory/v1/packs/ {
    alias /srv/gornitsa/uzory/v1/packs/;
    default_type application/octet-stream;
    access_log off;
    gzip on;
    gzip_types application/octet-stream;
    add_header Cache-Control "public, max-age=31536000, immutable" always;
    add_header X-Content-Type-Options "nosniff" always;
}

location ^~ /uzory/v1/ {
    return 404;
}

CONF
  if [[ ! -s "$PASSWD" ]]; then
    cat <<'CONF'
# Пароль ещё не задан (sudo uzory-password) — закрыто для всех.
location ^~ /uzory/test/ {
    return 403;
}
CONF
    return
  fi
  cat <<CONF
location ^~ /uzory/test/ {
    # пароль не должен ходить открытым текстом
    if (\$https = "") {
        return 403;
    }
    auth_basic "uzory test";
    auth_basic_user_file ${PASSWD};

    alias /opt/uzory/current/test/;
    index index.html;
    types {
        text/html html;
        application/javascript js;
        application/json json;
        application/wasm wasm;
        image/png png;
        image/x-icon ico;
        font/ttf ttf;
    }
    default_type application/octet-stream;
CONF
  # сжатые копии .gz готовит uzory-pull; модуль есть в nginx Ubuntu, но проверим
  local v
  v="$(nginx -V 2>&1 || true)"
  if grep -q -- --with-http_gzip_static_module <<< "$v"; then
    echo "    gzip_static on;"
  fi
  cat <<CONF

    # Скрипт и шрифты — с отпечатком в имени, canvaskit.wasm и страница — без: браузер
    # сверяется каждый раз и получает 304, пока файл не сменился.
    add_header Cache-Control "no-cache" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-Robots-Tag "noindex, nofollow" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), interest-cohort=()" always;
    add_header Content-Security-Policy "${CSP}" always;
}
CONF
}

BACKUP_SNIPPET=""
BACKUP_SITE=""
BACKUP_STATS=""
restore() {
  if [[ -n "$BACKUP_SNIPPET" ]]; then mv -f "$BACKUP_SNIPPET" "$SNIPPET"; elif [[ -n "${NEW_SNIPPET:-}" ]]; then rm -f "$SNIPPET"; fi
  if [[ -n "$BACKUP_SITE" ]]; then mv -f "$BACKUP_SITE" "$SITE"; fi
  if [[ -n "$BACKUP_STATS" ]]; then mv -f "$BACKUP_STATS" "$STATS_CONF"; elif [[ -n "${NEW_STATS:-}" ]]; then rm -f "$STATS_CONF"; fi
}

install -d -m 755 /etc/nginx/snippets /var/www/uzory-meta /var/log/uzory
CHANGED=0

# 1. Файл с местами «Узоров»
tmp="$(mktemp)"
render > "$tmp"
if [[ ! -f "$SNIPPET" ]] || ! cmp -s "$tmp" "$SNIPPET"; then
  if [[ -f "$SNIPPET" ]]; then BACKUP_SNIPPET="$(mktemp)"; cp "$SNIPPET" "$BACKUP_SNIPPET"; else NEW_SNIPPET=1; fi
  install -m 644 "$tmp" "$SNIPPET"
  CHANGED=1
fi
rm -f "$tmp"

# 1а. Формат журнала каталога — на уровне http (conf.d подключён в nginx.conf Ubuntu)
tmp="$(mktemp)"
cat > "$tmp" <<'CONF'
# «Узоры»: журнал запросов каталога без адресов — счётчики (server/stats в репозитории Nefeste/uzory).
# Файл пишет /usr/local/sbin/uzory-nginx (репозиторий gornitsagames, deploy/uzory/nginx.sh).
log_format uzory_stats '$time_iso8601 "$request_uri" $status';
CONF
if [[ ! -f "$STATS_CONF" ]] || ! cmp -s "$tmp" "$STATS_CONF"; then
  if [[ -f "$STATS_CONF" ]]; then BACKUP_STATS="$(mktemp)"; cp "$STATS_CONF" "$BACKUP_STATS"; else NEW_STATS=1; fi
  install -d -m 755 "$(dirname "$STATS_CONF")"
  install -m 644 "$tmp" "$STATS_CONF"
  CHANGED=1
fi
rm -f "$tmp"

# 2. Строка include в конфиге сайта
if [[ ! -f "$SITE" ]]; then
  echo "Нет $SITE — сначала настройка сайта (deploy/setup-server.sh)" >&2
  restore
  exit 1
fi
if ! grep -qF "$INCLUDE" "$SITE"; then
  ROOT_RE='^[[:space:]]*root[[:space:]]+/var/www/gornitsa\.games;[[:space:]]*$'
  if [[ "$(grep -cE "$ROOT_RE" "$SITE" || true)" != 1 ]]; then
    echo "В $SITE не одна строка «root /var/www/gornitsa.games;» — добавьте в блок server сайта вручную: $INCLUDE" >&2
    restore
    exit 1
  fi
  BACKUP_SITE="$(mktemp)"
  cp -p "$SITE" "$BACKUP_SITE"
  tmp="$(mktemp)"
  INC="    $INCLUDE" RE="$ROOT_RE" awk '{ print } $0 ~ ENVIRON["RE"] { print ENVIRON["INC"] }' "$SITE" > "$tmp"
  cat "$tmp" > "$SITE"
  rm -f "$tmp"
  CHANGED=1
fi

(( CHANGED )) || exit 0
if nginx -t -q 2>/dev/null; then
  systemctl reload nginx
  if [[ -s "$PASSWD" ]]; then echo "nginx: /uzory/test/ — по паролю"; else echo "nginx: /uzory/test/ — закрыто, пока нет пароля (sudo uzory-password)"; fi
  rm -f "$BACKUP_SNIPPET" "$BACKUP_SITE" "$BACKUP_STATS"
else
  nginx -t || true
  restore
  echo "nginx: новый конфиг «Узоров» не прошёл проверку — оставил прежний" >&2
  exit 1
fi
