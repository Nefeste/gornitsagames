#!/usr/bin/env bash
# Первичная настройка чистого VPS (Ubuntu 22.04 / 24.04) под сайт gornitsa.games.
# Запускать один раз на сервере от root:
#   scp -r deploy root@IP_СЕРВЕРА:/root/
#   ssh root@IP_СЕРВЕРА 'bash /root/deploy/setup-server.sh'
#
# Что делает скрипт:
#   1. Обновляет систему и ставит nginx, certbot, ufw, rsync, автообновления безопасности.
#   2. Создаёт пользователя deploy (только для выкладки сайта) с вашим SSH-ключом.
#   3. Настраивает nginx по deploy/nginx/gornitsa.games.conf.
#   4. Открывает в файрволе только SSH, 80 и 443.
#   5. Если DNS уже указывает на этот сервер — выпускает бесплатный сертификат Let's Encrypt.
# Скрипт можно запускать повторно: он ничего не ломает, а просто доводит настройку.

set -euo pipefail

DOMAIN="${DOMAIN:-gornitsa.games}"
EMAIL="${EMAIL:-dev@gornitsa.games}"   # почта аккаунта Let's Encrypt — ящик разработчика студии (устав, docs/03-team.md)
DEPLOY_USER="${DEPLOY_USER:-deploy}"
WEBROOT="/var/www/${DOMAIN}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Запустите скрипт от root (sudo bash setup-server.sh)." >&2
  exit 1
fi

echo "==> Обновляю систему и ставлю пакеты"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get -y -q upgrade
apt-get -y -q install nginx certbot python3-certbot-nginx ufw rsync unattended-upgrades curl

echo "==> Включаю автоматические обновления безопасности"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF

echo "==> Пользователь ${DEPLOY_USER} для выкладки сайта"
if ! id -u "${DEPLOY_USER}" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "${DEPLOY_USER}"
fi
install -d -m 700 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh"
if [[ -f /root/.ssh/authorized_keys ]]; then
  # Копируем ключи root, если у deploy их ещё нет. Дополнительные ключи (например, для GitHub Actions)
  # можно дописать в /home/deploy/.ssh/authorized_keys вручную.
  touch "/home/${DEPLOY_USER}/.ssh/authorized_keys"
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    grep -qxF "$key" "/home/${DEPLOY_USER}/.ssh/authorized_keys" || echo "$key" >> "/home/${DEPLOY_USER}/.ssh/authorized_keys"
  done < /root/.ssh/authorized_keys
  chown "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh/authorized_keys"
  chmod 600 "/home/${DEPLOY_USER}/.ssh/authorized_keys"
else
  echo "   ВНИМАНИЕ: у root нет SSH-ключей, добавьте свой ключ в /home/${DEPLOY_USER}/.ssh/authorized_keys вручную."
fi

echo "==> Папка сайта ${WEBROOT}"
install -d -m 755 -o "${DEPLOY_USER}" -g www-data "${WEBROOT}"
if [[ -d "${SCRIPT_DIR}/../site" ]]; then
  rsync -a --delete --chmod=D755,F644 "${SCRIPT_DIR}/../site/" "${WEBROOT}/"
elif [[ ! -f "${WEBROOT}/index.html" ]]; then
  echo '<!doctype html><meta charset="utf-8"><title>Горница</title><p>Сайт скоро появится.</p>' > "${WEBROOT}/index.html"
fi
chown -R "${DEPLOY_USER}:www-data" "${WEBROOT}"

echo "==> Настраиваю nginx"
NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"
if [[ -f "${NGINX_CONF}" ]] && grep -q "managed by Certbot" "${NGINX_CONF}"; then
  echo "   Конфиг уже содержит настройки HTTPS от certbot — оставляю его как есть."
else
  sed "s/gornitsa\.games/${DOMAIN}/g" "${SCRIPT_DIR}/nginx/gornitsa.games.conf" > "${NGINX_CONF}"
fi
ln -sf "${NGINX_CONF}" "/etc/nginx/sites-enabled/${DOMAIN}.conf"
rm -f /etc/nginx/sites-enabled/default
sed -i 's/^\s*#\s*server_tokens off;/\tserver_tokens off;/' /etc/nginx/nginx.conf
nginx -t
systemctl enable --now nginx
systemctl reload nginx

echo "==> Файрвол: только SSH, HTTP и HTTPS"
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

echo "==> Проверяю DNS"
SERVER_IP="$(curl -4 -fsS --max-time 10 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
APEX_IP="$(getent ahostsv4 "${DOMAIN}" | awk 'NR==1{print $1}' || true)"
WWW_IP="$(getent ahostsv4 "www.${DOMAIN}" | awk 'NR==1{print $1}' || true)"
echo "   IP сервера: ${SERVER_IP}; ${DOMAIN} -> ${APEX_IP:-нет записи}; www.${DOMAIN} -> ${WWW_IP:-нет записи}"

if [[ -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
  echo "HTTPS уже настроен: https://${DOMAIN}"
elif [[ "${APEX_IP}" == "${SERVER_IP}" && "${WWW_IP}" == "${SERVER_IP}" ]]; then
  echo "==> Выпускаю сертификат Let's Encrypt"
  certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" -m "${EMAIL}" --agree-tos -n --redirect
  systemctl reload nginx
  echo "Готово: https://${DOMAIN}"
else
  echo
  echo "DNS ещё не указывает на этот сервер, поэтому HTTPS пока не включён."
  echo "Добавьте у регистратора две A-записи: '@' и 'www' -> ${SERVER_IP},"
  echo "подождите, пока они обновятся (обычно от 15 минут до нескольких часов), и запустите скрипт ещё раз."
  echo "Если сервер настроен через bootstrap.sh, HTTPS включится сам в течение 5 минут после обновления DNS."
fi
