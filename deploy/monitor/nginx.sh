#!/usr/bin/env bash
# gornitsa-monitor-nginx: сводки мониторинга в nginx сайта —
# https://gornitsa.games/.well-known/monitor/latest.json и ГГГГ-ММ-ДД.json.
# Ставит deploy/monitor/setup.sh; вызывает gornitsa-monitor-password после смены пароля.
#
# Пишет /etc/nginx/snippets/gornitsa.games-monitor.conf: только по HTTPS и только с именем и паролем
# из /etc/gornitsa-monitor/htpasswd; пока файла нет — 403 всем. Конфиг сайта подключает такие файлы
# строкой `include /etc/nginx/snippets/gornitsa.games-*.conf;` (deploy/nginx/*.conf; в старый конфиг
# на машине её добавляет uzory-nginx). Новый файл не прошёл `nginx -t` — возвращается прежний.

set -euo pipefail

SITE=/etc/nginx/sites-available/gornitsa.games.conf
SNIPPET=/etc/nginx/snippets/gornitsa.games-monitor.conf
INCLUDE='include /etc/nginx/snippets/gornitsa.games-*.conf;'
PASSWD=/etc/gornitsa-monitor/htpasswd

render() {
  cat <<'CONF'
# Мониторинг машины: сводки по паролю. Файл пишет /usr/local/sbin/gornitsa-monitor-nginx
# (репозиторий gornitsagames, deploy/monitor/nginx.sh) — правки здесь затрутся.
CONF
  if [[ ! -s "$PASSWD" ]]; then
    cat <<'CONF'
# Пароль ещё не задан (sudo gornitsa-monitor-password) — закрыто для всех.
location ^~ /.well-known/monitor/ {
    return 403;
}
CONF
    return
  fi
  cat <<CONF
location ^~ /.well-known/monitor/ {
    # пароль не должен ходить открытым текстом
    if (\$https = "") {
        return 403;
    }
    auth_basic "gornitsa monitor";
    auth_basic_user_file ${PASSWD};

    alias /var/lib/gornitsa-monitor/daily/;
    types { application/json json; }
    default_type application/json;
    charset utf-8;
    charset_types application/json;

    add_header Cache-Control "no-store" always;
    add_header X-Robots-Tag "noindex, nofollow" always;
    include /etc/nginx/snippets/gornitsa-site-headers.conf;
}
CONF
}

if [[ ! -f "$SITE" ]] || ! grep -qF "$INCLUDE" "$SITE"; then
  echo "nginx: в $SITE нет строки «$INCLUDE» — сводки по сети пока не отдаются" >&2
  exit 0
fi

tmp="$(mktemp)"
render > "$tmp"
if [[ -f "$SNIPPET" ]] && cmp -s "$tmp" "$SNIPPET"; then
  rm -f "$tmp"
  exit 0
fi
BACKUP=""
if [[ -f "$SNIPPET" ]]; then BACKUP="$(mktemp)"; cp "$SNIPPET" "$BACKUP"; fi
install -m 644 "$tmp" "$SNIPPET"
rm -f "$tmp"

if nginx -t -q 2>/dev/null; then
  systemctl reload nginx
  rm -f "$BACKUP"
  if [[ -s "$PASSWD" ]]; then echo "nginx: /.well-known/monitor/ — по паролю"; else echo "nginx: /.well-known/monitor/ — закрыто, пока нет пароля (sudo gornitsa-monitor-password)"; fi
else
  nginx -t || true
  if [[ -n "$BACKUP" ]]; then mv -f "$BACKUP" "$SNIPPET"; else rm -f "$SNIPPET"; fi
  echo "nginx: новый конфиг мониторинга не прошёл проверку — оставил прежний" >&2
  exit 1
fi
