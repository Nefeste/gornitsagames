#!/usr/bin/env bash
# Автообновление сайта: забирает свежий main из GitHub и выкладывает site/ в папку nginx.
# Запускается systemd-таймером gornitsa-update.timer (см. deploy/bootstrap.sh).
# Если HTTPS ещё не включён, а DNS уже указывает на сервер, выпускает сертификат Let's Encrypt.

set -euo pipefail

DIR="/opt/gornitsa"
BRANCH="${BRANCH:-main}"
DOMAIN="${DOMAIN:-gornitsa.games}"
EMAIL="${EMAIL:-gornitsa.games@gmail.com}"
WEBROOT="/var/www/${DOMAIN}"
STAMP="/var/lib/gornitsa-deployed-commit"

git -C "${DIR}" fetch -q origin "${BRANCH}"
REMOTE="$(git -C "${DIR}" rev-parse "origin/${BRANCH}")"
DEPLOYED="$(cat "${STAMP}" 2>/dev/null || true)"

if [[ "${REMOTE}" != "${DEPLOYED}" ]]; then
  git -C "${DIR}" reset -q --hard "origin/${BRANCH}"
  bash "${DIR}/deploy/fetch-fonts.sh"
  python3 "${DIR}/build.py" >/dev/null
  rsync -a --delete --chmod=D755,F644 "${DIR}/site/" "${WEBROOT}/"
  chown -R deploy:www-data "${WEBROOT}" 2>/dev/null || true
  echo "${REMOTE}" > "${STAMP}"
  echo "Выложена версия ${REMOTE:0:7}"
fi

if [[ ! -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
  SERVER_IP="$(curl -4 -fsS --max-time 10 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
  APEX_IP="$(getent ahostsv4 "${DOMAIN}" | awk 'NR==1{print $1}' || true)"
  WWW_IP="$(getent ahostsv4 "www.${DOMAIN}" | awk 'NR==1{print $1}' || true)"
  if [[ -n "${SERVER_IP}" && "${APEX_IP}" == "${SERVER_IP}" && "${WWW_IP}" == "${SERVER_IP}" ]]; then
    certbot --nginx -d "${DOMAIN}" -d "www.${DOMAIN}" -m "${EMAIL}" --agree-tos -n --redirect
    systemctl reload nginx
    echo "HTTPS включён для ${DOMAIN}"
  fi
fi
