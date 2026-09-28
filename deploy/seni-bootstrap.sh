#!/usr/bin/env bash
# Установщик Сеней — шлюза студии (закрытый репозиторий Nefeste/seni, docs/05-deploy.md там).
# Лежит здесь, в открытом репозитории, потому что закрытый без ключа не скачать. Сам ничего,
# кроме ключа доступа, не настраивает: всё остальное делает deploy/setup.sh из Nefeste/seni.
#
# Новая машина (Ubuntu 24.04 или новее, Debian 12 или новее), от root:
#
#   curl -fsSL https://raw.githubusercontent.com/Nefeste/gornitsagames/main/deploy/seni-bootstrap.sh | sudo bash
#
# Переезд с другой машины — с файлом из `sudo seni-migrate export` (ключи, ключ доступа и база):
#
#   curl -fsSL https://raw.githubusercontent.com/Nefeste/gornitsagames/main/deploy/seni-bootstrap.sh \
#     | sudo SENI_IMPORT=/root/seni-export-ГГГГММДД.tar.gz.age bash
#
# Что делает:
#   1. ставит git, nginx, age;
#   2. при SENI_IMPORT — расшифровывает файл переезда (age спросит пароль) в /etc/seni и
#      /var/lib/seni; иначе создаёт новый ключ доступа к репозиторию (deploy key, только чтение);
#   3. показывает открытый ключ и кладёт его по адресу http://<машина>/.well-known/seni-deploy.pub;
#   4. ждёт (до часа), пока ключ добавят в Nefeste/seni → Settings → Deploy keys без права записи,
#      забирает репозиторий в /opt/seni/repo и запускает его deploy/setup.sh.
# Запускать можно повторно: сделанное не ломается.

set -euo pipefail

REPO="git@github.com:Nefeste/seni.git"
DIR=/opt/seni/repo
ETC=/etc/seni

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root: curl -fsSL <адрес скрипта> | sudo bash" >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
APT=(apt-get -q -y -o DPkg::Lock::Timeout=300)

echo "==> Сени: пакеты"
"${APT[@]}" update
"${APT[@]}" install git openssh-client nginx age curl

install -d -m 750 "$ETC"

if [[ -n "${SENI_IMPORT:-}" ]]; then
  [[ -f "$SENI_IMPORT" ]] || { echo "Нет файла переезда $SENI_IMPORT" >&2; exit 1; }
  echo "==> Сени: файл переезда $SENI_IMPORT (age спросит пароль)"
  STAGE="$(mktemp -d)"
  trap 'rm -rf "$STAGE"' EXIT
  age -d "$SENI_IMPORT" | tar -xzf - -C "$STAGE"
  [[ -f "$STAGE/etc/seni/env" && -f "$STAGE/etc/seni/deploy_key" ]] || { echo "В файле нет ключей Сеней" >&2; exit 1; }
  install -m 640 "$STAGE/etc/seni/env" "$ETC/env"
  install -m 600 "$STAGE/etc/seni/deploy_key" "$ETC/deploy_key"
  install -m 644 "$STAGE/etc/seni/deploy_key.pub" "$ETC/deploy_key.pub"
  if [[ -f "$STAGE/var/lib/seni/seni.db" ]]; then
    install -d -m 750 /var/lib/seni
    install -m 640 "$STAGE/var/lib/seni/seni.db" /var/lib/seni/seni.db
  fi
  echo "   ключи, ключ доступа и база — на месте"
elif [[ ! -f "$ETC/deploy_key" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C "seni-deploy@seni.gornitsa.games" -f "$ETC/deploy_key"
fi
chmod 600 "$ETC/deploy_key"

# Ключи GitHub (https://api.github.com/meta → ssh_keys), как в deploy/nardy/setup.sh.
cat > "$ETC/known_hosts" <<'KEYS'
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
KEYS
chmod 644 "$ETC/known_hosts"
export GIT_SSH_COMMAND="ssh -i $ETC/deploy_key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$ETC/known_hosts -o ConnectTimeout=20"

# Открытый ключ — по адресу машины: стандартный сайт nginx отдаёт /var/www/html.
# (deploy/setup.sh потом уберёт стандартный сайт и будет отдавать ключ сам, по имени.)
install -d -m 755 /var/www/html/.well-known
install -m 644 "$ETC/deploy_key.pub" /var/www/html/.well-known/seni-deploy.pub
systemctl enable --now nginx >/dev/null 2>&1 || true

if ! git ls-remote "$REPO" HEAD >/dev/null 2>&1; then
  IP="$(curl -4 -fsS --max-time 10 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
  echo
  echo "Добавьте ключ машины в Nefeste/seni → Settings → Deploy keys (без права записи):"
  echo
  echo "  $(cat "$ETC/deploy_key.pub")"
  echo
  echo "Он же — по адресу http://${IP}/.well-known/seni-deploy.pub"
  echo "Жду, пока ключ заработает (до часа; окно можно не закрывать — или запустить установщик потом ещё раз)."
  for i in $(seq 1 180); do
    sleep 20
    if git ls-remote "$REPO" HEAD >/dev/null 2>&1; then break; fi
    (( i % 3 == 0 )) && echo "   …жду ключ ($((i / 3)) мин)"
    if (( i == 180 )); then echo "Ключ так и не заработал. Добавьте его и запустите установщик ещё раз." >&2; exit 1; fi
  done
fi
echo "==> Сени: доступ к репозиторию есть"

if [[ -d "$DIR/.git" ]]; then
  git -C "$DIR" fetch -q origin main
  git -C "$DIR" checkout -q -f --detach FETCH_HEAD
else
  install -d -m 755 /opt/seni
  git clone -q --branch main "$REPO" "$DIR"
fi

bash "$DIR/deploy/setup.sh"
