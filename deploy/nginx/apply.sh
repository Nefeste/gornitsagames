#!/usr/bin/env bash
# Ставит настройки nginx сайта из deploy/nginx/ на машину: заголовки и места (snippets)
# и сам конфиг сайта с HTTPS (gornitsa.games.https.conf; server_tokens off — в нём, у сайта).
# Запускает update-site.sh, когда меняется deploy/nginx/ и сертификат Let's Encrypt уже есть.
#
# Порядок: копия нынешних файлов → новые файлы → nginx -t → reload → проверка: https://домен/
# отвечает 200, http:// — 301. Что-то не так — всё возвращается как было, nginx перезагружается.

set -euo pipefail

DIR="${DIR:-/opt/gornitsa}"
DOMAIN="${DOMAIN:-gornitsa.games}"
SRC="${DIR}/deploy/nginx"
SITE_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"
HEADERS=/etc/nginx/snippets/gornitsa-site-headers.conf
LOCATIONS=/etc/nginx/snippets/gornitsa-site-locations.conf
# Первая версия (30.09.2026) ставила server_tokens off сюда, для всей машины, — nginx -t не прошёл:
# на машине server_tokens уже задан в http{}. Теперь он в server{} сайта, а этот файл убирается.
SERVER=/etc/nginx/conf.d/gornitsa-server.conf

if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
  echo "nginx: сертификата ${DOMAIN} ещё нет — настройки с HTTPS не ставлю"
  exit 0
fi

BACKUP="$(mktemp -d)"
FILES=("$SITE_CONF" "$HEADERS" "$LOCATIONS" "$SERVER")
for f in "${FILES[@]}"; do
  if [[ -f "$f" ]]; then cp -p "$f" "${BACKUP}/$(basename "$f")"; fi
done
restore() {
  for f in "${FILES[@]}"; do
    local b="${BACKUP}/$(basename "$f")"
    if [[ -f "$b" ]]; then cp -p "$b" "$f"; else rm -f "$f"; fi
  done
  if nginx -t -q 2>/dev/null; then systemctl reload nginx; fi
}

install -d -m 755 /etc/nginx/snippets
install -m 644 "${SRC}/headers.conf" "$HEADERS"
install -m 644 "${SRC}/locations.conf" "$LOCATIONS"
rm -f "$SERVER"

tmp="$(mktemp)"
sed "s/gornitsa\.games/${DOMAIN}/g" "${SRC}/gornitsa.games.https.conf" > "$tmp"
# файлов certbot с настройками TLS может не быть (сертификат выпускали без установщика nginx)
if [[ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]]; then
  sed -i 's|^\([[:space:]]*\)include /etc/letsencrypt/options-ssl-nginx.conf;.*|\1ssl_protocols TLSv1.2 TLSv1.3;|' "$tmp"
fi
if [[ ! -f /etc/letsencrypt/ssl-dhparams.pem ]]; then
  sed -i '/ssl_dhparam \/etc\/letsencrypt\/ssl-dhparams.pem;/d' "$tmp"
fi
install -m 644 "$tmp" "$SITE_CONF"
rm -f "$tmp"

if ! nginx -t; then
  echo "nginx: новые настройки сайта не прошли nginx -t — вернул прежние" >&2
  restore
  exit 1
fi
systemctl reload nginx
sleep 2

https_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 --resolve "${DOMAIN}:443:127.0.0.1" "https://${DOMAIN}/" || true)"
http_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 --resolve "${DOMAIN}:80:127.0.0.1" "http://${DOMAIN}/" || true)"
if [[ "$https_code" != 200 || "$http_code" != 301 ]]; then
  echo "nginx: после новых настроек https:// ответил ${https_code}, http:// — ${http_code}; вернул прежние" >&2
  restore
  exit 1
fi
rm -rf "$BACKUP"
echo "nginx: настройки сайта обновлены (HTTP/2, HSTS, заголовки во всех местах сайта)"
