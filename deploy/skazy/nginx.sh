#!/usr/bin/env bash
# skazy-nginx: сервер заставы «Сказов» skazy.gornitsa.games в nginx (ставит deploy/skazy/setup.sh,
# вызывает skazy-pull каждые 2 минуты). Устроен как nardy-nginx (deploy/nardy/nginx.sh), но:
#   - без WebSocket: застава ходит обычными запросами (ADR 0024 «Сказов»);
#   - тело запроса — до 260 КБ: копия хозяйства бывает до 256 КБ;
#   - журнал запросов поддомена — без адресов: свой формат строки skazy_noaddr, без $remote_addr
#     и без строки запроса (?…). В журнале ошибок nginx адрес остаётся — формат тех строк не
#     меняется; живут они те же три дня.
#
# Пока нет сертификата — только порт 80. Как только A-запись skazy.gornitsa.games указывает туда
# же, куда gornitsa.games (на этот сервер), выпускает сертификат Let's Encrypt (`certbot certonly`,
# продлевает его certbot.timer) и включает HTTPS с переадресацией с http. Конфиг целиком пишет этот
# скрипт — certbot его не правит, поэтому изменения здесь доезжают до сервера сами. После
# продления сертификата certbot сам перезагружает nginx (--deploy-hook).

set -euo pipefail

NAME="skazy.gornitsa.games"
APEX="gornitsa.games"
EMAIL="gornitsa.games@gmail.com"
CONF="/etc/nginx/sites-available/${NAME}.conf"
LIVE="/etc/letsencrypt/live/${NAME}"
STATE=/var/lib/skazy-deploy

common() {
  cat <<'CONF'
    charset utf-8;
    client_max_body_size 260k;

    # Открытый ключ машины для deploy key.
    location ^~ /.well-known/skazy- {
        root /var/www/skazy-meta;
        default_type text/plain;
        add_header Cache-Control "no-cache" always;
    }

    # Всё остальное — сервер заставы (в том числе /.well-known/assetlinks.json и страницы /z/…).
    location / {
        proxy_pass http://127.0.0.1:8791;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_read_timeout 30s;
    }

    access_log /var/log/nginx/skazy/access.log skazy_noaddr;
    error_log  /var/log/nginx/skazy/error.log warn;
CONF
}

render() {   # $1: http | https
  echo "# Сервер заставы «Сказов». Файл пишет /usr/local/sbin/skazy-nginx (репозиторий gornitsagames,"
  echo "# deploy/skazy/nginx.sh) — правки здесь затрутся."
  echo
  # Строка журнала без адреса и без строки запроса; имя своё, чтобы не столкнуться с чужими
  # log_format в общем http {}.
  echo "log_format skazy_noaddr '\$time_iso8601 \$request_method \$uri \$status \$body_bytes_sent '"
  echo "                        '\$request_time \"\$http_user_agent\"';"
  echo
  if [[ "$1" == https ]]; then
    cat <<CONF
server {
    listen 80;
    listen [::]:80;
    server_name ${NAME};
    location ^~ /.well-known/skazy- {
        root /var/www/skazy-meta;
        default_type text/plain;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
    access_log /var/log/nginx/skazy/access.log skazy_noaddr;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${NAME};

    ssl_certificate ${LIVE}/fullchain.pem;
    ssl_certificate_key ${LIVE}/privkey.pem;
CONF
    if [[ -f /etc/letsencrypt/options-ssl-nginx.conf ]]; then
      echo "    include /etc/letsencrypt/options-ssl-nginx.conf;"
    else
      echo "    ssl_protocols TLSv1.2 TLSv1.3;"
    fi
    if [[ -f /etc/letsencrypt/ssl-dhparams.pem ]]; then
      echo "    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;"
    fi
    echo
    common
    echo "}"
  else
    cat <<CONF
server {
    listen 80;
    listen [::]:80;
    server_name ${NAME};

CONF
    common
    echo "}"
  fi
}

apply() {   # $1: http | https — пишет конфиг, если он изменился, проверяет и перезагружает nginx
  local tmp
  tmp="$(mktemp)"
  render "$1" > "$tmp"
  if [[ -f "$CONF" ]] && cmp -s "$tmp" "$CONF"; then rm -f "$tmp"; return 0; fi
  local old=""
  if [[ -f "$CONF" ]]; then old="$(mktemp)"; cp "$CONF" "$old"; fi
  install -m 644 "$tmp" "$CONF"
  rm -f "$tmp"
  ln -sfn "$CONF" "/etc/nginx/sites-enabled/${NAME}.conf"
  if nginx -t -q 2>/dev/null; then
    systemctl reload nginx
    echo "nginx: ${NAME} — $1"
    if [[ -n "$old" ]]; then rm -f "$old"; fi
  else
    nginx -t || true
    if [[ -n "$old" ]]; then mv "$old" "$CONF"; else rm -f "$CONF" "/etc/nginx/sites-enabled/${NAME}.conf"; fi
    echo "nginx: новый конфиг ${NAME} не прошёл проверку — оставил прежний" >&2
    return 1
  fi
}

install -d -m 755 -o root -g adm /var/log/nginx/skazy
install -d -m 700 "$STATE"

if [[ -d "$LIVE" ]]; then
  apply https
  exit 0
fi

apply http

# Сертификат — когда skazy.gornitsa.games указывает на этот же сервер. Не чаще раза в 30 минут:
# у Let's Encrypt строгие пределы на неудачные попытки.
MINE="$(getent ahostsv4 "$APEX" | awk 'NR == 1 {print $1}' || true)"
THEIRS="$(getent ahostsv4 "$NAME" | awk 'NR == 1 {print $1}' || true)"
[[ -n "$THEIRS" && "$THEIRS" == "$MINE" ]] || exit 0
LAST="$(cat "$STATE/certbot-tried" 2>/dev/null || echo 0)"
(( $(date +%s) - LAST >= 1800 )) || exit 0
date +%s > "$STATE/certbot-tried"
if certbot certonly --nginx -d "$NAME" -m "$EMAIL" --agree-tos -n -q --deploy-hook "systemctl reload nginx"; then
  echo "Сертификат для ${NAME} выпущен"
  apply https
else
  echo "certbot: не вышло, повторю через 30 минут" >&2
  exit 1
fi
