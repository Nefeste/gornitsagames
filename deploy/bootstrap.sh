#!/usr/bin/env bash
# Настройка сервера одной командой (выполнить на свежем VPS от root):
#
#   curl -fsSL https://raw.githubusercontent.com/Nefeste/gornitsagames/main/deploy/bootstrap.sh | bash
#
# Скрипт скачивает репозиторий в /opt/gornitsa, настраивает nginx, файрвол и HTTPS
# (deploy/setup-server.sh) и включает автообновление: каждые 5 минут сервер проверяет GitHub
# и, если в ветке main есть новые коммиты, выкладывает свежую версию сайта.
# Как только DNS домена начнёт указывать на сервер, автообновление само выпустит сертификат HTTPS.
# Заодно настраивает серверы игр «Вотчина» (deploy/votchina/setup.sh), «Длинные нарды»
# (deploy/nardy/setup.sh), заставы «Сказов» (deploy/skazy/setup.sh) и закрытую веб-версию
# «Узоров» (deploy/uzory/setup.sh), и мониторинг ресурсов машины (deploy/monitor/setup.sh).

set -euo pipefail

REPO="${REPO:-https://github.com/Nefeste/gornitsagames.git}"
BRANCH="${BRANCH:-main}"
DIR="/opt/gornitsa"

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: curl -fsSL <адрес скрипта> | sudo bash" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q git

if [[ -d "${DIR}/.git" ]]; then
  git -C "${DIR}" fetch -q origin "${BRANCH}"
  git -C "${DIR}" reset -q --hard "origin/${BRANCH}"
else
  git clone -q --branch "${BRANCH}" "${REPO}" "${DIR}"
fi

echo "==> Готовлю файлы сайта"
apt-get install -y -q python3 curl rsync
bash "${DIR}/deploy/fetch-fonts.sh"
python3 "${DIR}/build.py"

bash "${DIR}/deploy/setup-server.sh"

echo "==> Включаю автообновление сайта из GitHub"
install -m 755 "${DIR}/deploy/update-site.sh" /usr/local/bin/gornitsa-update

cat > /etc/systemd/system/gornitsa-update.service <<UNIT
[Unit]
Description=Обновление сайта gornitsa.games из GitHub
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Environment=BRANCH=${BRANCH}
ExecStart=/usr/local/bin/gornitsa-update
UNIT

cat > /etc/systemd/system/gornitsa-update.timer <<'UNIT'
[Unit]
Description=Проверять обновления сайта каждые 5 минут

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now gornitsa-update.timer

echo "==> Сервер игры «Вотчина» (votchina.gornitsa.games)"
if bash "${DIR}/deploy/votchina/setup.sh"; then
  git -C "${DIR}" rev-parse "HEAD:deploy/votchina" > /var/lib/gornitsa-votchina-setup
fi

echo "==> Сервер игры «Длинные нарды» (nardy.gornitsa.games)"
if bash "${DIR}/deploy/nardy/setup.sh"; then
  git -C "${DIR}" rev-parse "HEAD:deploy/nardy" > /var/lib/gornitsa-nardy-setup
fi

echo "==> Сервер заставы «Сказов» (skazy.gornitsa.games)"
if bash "${DIR}/deploy/skazy/setup.sh"; then
  git -C "${DIR}" rev-parse "HEAD:deploy/skazy" > /var/lib/gornitsa-skazy-setup
fi

echo "==> Закрытая веб-версия «Узоров» (gornitsa.games/uzory/test/)"
if bash "${DIR}/deploy/uzory/setup.sh"; then
  git -C "${DIR}" rev-parse "HEAD:deploy/uzory" > /var/lib/gornitsa-uzory-setup
fi

echo "==> Мониторинг ресурсов машины"
if bash "${DIR}/deploy/monitor/setup.sh"; then
  git -C "${DIR}" rev-parse "HEAD:deploy/monitor" > /var/lib/gornitsa-monitor-setup
fi

echo
echo "Готово. Сайт обновляется сам после каждого push в ветку ${BRANCH}."
echo "Журнал обновлений: journalctl -u gornitsa-update -n 50"
