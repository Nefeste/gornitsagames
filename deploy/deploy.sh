#!/usr/bin/env bash
# Выкладка сайта на сервер со своего компьютера.
# Использование:  ./deploy/deploy.sh IP_ИЛИ_ИМЯ_СЕРВЕРА
# Нужен SSH-доступ пользователем deploy (его создаёт setup-server.sh).

set -euo pipefail

HOST="${1:-${DEPLOY_HOST:-}}"
USER_NAME="${DEPLOY_USER:-deploy}"
DOMAIN="${DOMAIN:-gornitsa.games}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${HOST}" ]]; then
  echo "Укажите сервер: ./deploy/deploy.sh 203.0.113.10" >&2
  exit 1
fi

bash "${ROOT_DIR}/deploy/fetch-fonts.sh"
python3 "${ROOT_DIR}/build.py"
rsync -avz --delete --chmod=D755,F644 \
  --exclude ".DS_Store" \
  "${ROOT_DIR}/site/" "${USER_NAME}@${HOST}:/var/www/${DOMAIN}/"

echo "Сайт выложен: https://${DOMAIN}"
