#!/usr/bin/env bash
# bukvitsa-nginx: закрытая веб-версия «Буквицы» в nginx сайта — https://gornitsa.games/bukvitsa/test/
# Ставит deploy/bukvitsa/setup.sh; вызывают bukvitsa-pull каждые 5 минут и bukvitsa-password после смены пароля.
# Устроено как uzory-nginx (deploy/uzory/nginx.sh), без картинок по сети и счётчиков.
#
# Пишет /etc/nginx/snippets/gornitsa.games-bukvitsa.conf:
#   - /bukvitsa/test/ — из /opt/bukvitsa/current/test/, только по HTTPS и только с именем и паролем
#     из /etc/bukvitsa/test.htpasswd; пока файла паролей нет — 403 всем;
#   - /.well-known/bukvitsa-age.pub — открытый ключ машины: им CI «Буквицы» шифрует сборку в ветке vps.
# Конфиг сайта подключает такие файлы строкой `include /etc/nginx/snippets/gornitsa.games-*.conf;`
# (deploy/nginx/gornitsa.games.conf). В конфиг на сервере, который уже поправил certbot, строку
# добавляет этот скрипт — один раз, сразу после `root /var/www/gornitsa.games;`.
# Новый конфиг не прошёл `nginx -t` — возвращается прежний.

set -euo pipefail

SITE=/etc/nginx/sites-available/gornitsa.games.conf
SNIPPET=/etc/nginx/snippets/gornitsa.games-bukvitsa.conf
INCLUDE='include /etc/nginx/snippets/gornitsa.games-*.conf;'
PASSWD=/etc/bukvitsa/test.htpasswd

# Правила безопасности — как у сайта: WebAssembly «Буквице» не нужен (рисунок — SVG). Те же правила отдаёт
# сборке сценарий Playwright «Буквицы» (tools/e2e/browser.ts, E2E_BASE): меняете здесь — поменяйте и там.
CSP="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"

render() {
  cat <<'CONF'
# «Буквица»: закрытая веб-версия. Файл пишет /usr/local/sbin/bukvitsa-nginx (репозиторий gornitsagames,
# deploy/bukvitsa/nginx.sh) — правки здесь затрутся.

location = /bukvitsa/test {
    return 301 /bukvitsa/test/;
}

location = /.well-known/bukvitsa-age.pub {
    alias /var/www/bukvitsa-meta/bukvitsa-age.pub;
    default_type text/plain;
    add_header Cache-Control "no-cache" always;
}

CONF
  if [[ ! -s "$PASSWD" ]]; then
    cat <<'CONF'
# Пароль ещё не задан (sudo bukvitsa-password) — закрыто для всех.
location ^~ /bukvitsa/test/ {
    return 403;
}
CONF
    return
  fi
  cat <<CONF
location ^~ /bukvitsa/test/ {
    # пароль не должен ходить открытым текстом
    if (\$https = "") {
        return 403;
    }
    auth_basic "bukvitsa test";
    auth_basic_user_file ${PASSWD};

    alias /opt/bukvitsa/current/test/;
    index index.html;
    types {
        text/html html;
        application/javascript js;
        application/json json;
        image/png png;
        image/x-icon ico;
        font/ttf ttf;
    }
    default_type application/octet-stream;
CONF
  # сжатые копии .gz готовит bukvitsa-pull; модуль есть в nginx Ubuntu, но проверим
  local v
  v="$(nginx -V 2>&1 || true)"
  if grep -q -- --with-http_gzip_static_module <<< "$v"; then
    echo "    gzip_static on;"
  fi
  cat <<CONF

    # Скрипт и шрифты — с отпечатком в имени, страница — без: браузер сверяется каждый раз
    # и получает 304, пока файл не сменился.
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
restore() {
  if [[ -n "$BACKUP_SNIPPET" ]]; then mv -f "$BACKUP_SNIPPET" "$SNIPPET"; elif [[ -n "${NEW_SNIPPET:-}" ]]; then rm -f "$SNIPPET"; fi
  if [[ -n "$BACKUP_SITE" ]]; then mv -f "$BACKUP_SITE" "$SITE"; fi
}

install -d -m 755 /etc/nginx/snippets /var/www/bukvitsa-meta
CHANGED=0

# 1. Файл с местами «Буквицы»
tmp="$(mktemp)"
render > "$tmp"
if [[ ! -f "$SNIPPET" ]] || ! cmp -s "$tmp" "$SNIPPET"; then
  if [[ -f "$SNIPPET" ]]; then BACKUP_SNIPPET="$(mktemp)"; cp "$SNIPPET" "$BACKUP_SNIPPET"; else NEW_SNIPPET=1; fi
  install -m 644 "$tmp" "$SNIPPET"
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
  if [[ -s "$PASSWD" ]]; then echo "nginx: /bukvitsa/test/ — по паролю"; else echo "nginx: /bukvitsa/test/ — закрыто, пока нет пароля (sudo bukvitsa-password)"; fi
  rm -f "$BACKUP_SNIPPET" "$BACKUP_SITE"
else
  nginx -t || true
  restore
  echo "nginx: новый конфиг «Буквицы» не прошёл проверку — оставил прежний" >&2
  exit 1
fi
