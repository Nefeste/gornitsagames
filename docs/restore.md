# Восстановление с нуля

Что делать, если пропала машина, доступ к GitHub или всё сразу. Копии, из которых всё
поднимается, лежат у вас на компьютере ([`backup.md`](backup.md)):

| Что | Откуда | Как часто |
|---|---|---|
| базы игр (`votchina`, `nardy`, `skazy`) и «Сеней» | `GornitsaBackup/ГГГГ-ММ-ДД/*.db.gz.age` | раз в сутки, 14 дней |
| настройки машин с секретами служб | `site-config.tar.gz.age`, у «Сеней» — `seni-config.tar.gz.age` | раз в сутки, 14 дней |
| все репозитории, Issues, PR, релизы | `GornitsaBackup/github/` | раз в неделю |
| ключи подписи APK, пароли аккаунтов, ключ age | менеджер паролей (реестр — `uprava/owner/secrets.md`) | при каждом изменении |

**Главное правило: закрытый ключ age не попадает на сервер.** Копии расшифровываются у вас, а на
новую машину уходят уже открытыми — по SSH, прямо в нужное место. Команды ниже — для macOS и
Linux. В Windows то же самое выполняется в PowerShell: путь к ключу —
`$env:USERPROFILE\.gornitsa\age-key.txt`, а вместо `~` — полный путь к папке копий.

Всё это можно делать вместе с агентом: он ведёт по шагам и проверяет результат. Ключ age, пароли и
расшифрованные копии остаются у вас.

## 1. Пропала машина сайта и игр

Новая машина получает те же ключи, что были. Поэтому:
- ключи доступа к репозиториям игр в GitHub менять не нужно;
- ключ шифрования «Узоров» тот же, CI менять не нужно;
- отпечаток SSH тот же — компьютер не испугается «чужого» сервера;
- сертификаты HTTPS на месте.

1. **Новая VPS.** Ubuntu 24.04, Москва или Санкт-Петербург, ваш ключ SSH (README, «Запуск с нуля», шаги 2–3).
2. **DNS.** В Рег.ру записи `@`, `www`, `votchina`, `nardy`, `skazy` — на новый адрес.
3. **Настройки — до установки**, чтобы установщик нашёл прежние ключи и не сделал новых.
   Возьмите самую свежую папку копий:

   ```bash
   cd ~/GornitsaBackup/2026-10-04            # самая свежая дата
   age -d -i ~/.gornitsa/age-key.txt site-config.tar.gz.age | ssh root@НОВЫЙ_АДРЕС \
     'tar -xzpf - -C / --exclude=etc/ssh/sshd_config.d --exclude=etc/gornitsa/ssh-admin-ok'
   ```

   Настройки входа по SSH (`sshd_config.d`, отметка `ssh-admin-ok`) **не распаковываются**: с ними
   вход root закрылся бы раньше, чем установщик заведёт пользователя `gornitsa`, — и войти можно
   было бы только через консоль панели. Их заново пишет установщик, а root закрывается в шаге 7.

   В архиве — `/etc/votchina`, `/etc/nardy`, `/etc/skazy`, `/etc/uzory`, `/etc/gornitsa*`,
   `/etc/letsencrypt`, ключи SSH машины, настройки nginx, sshd и fail2ban, `~/.ssh` пользователей,
   сводки мониторинга.
4. **Установка** — на новой машине, от root:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/Nefeste/gornitsagames/main/deploy/bootstrap.sh | bash
   ```

   Если GitHub недоступен, возьмите сайт из своей копии:

   ```bash
   scp ~/GornitsaBackup/github/bundles/<дата>/gornitsagames.bundle root@НОВЫЙ_АДРЕС:/root/
   ssh root@НОВЫЙ_АДРЕС 'git clone /root/gornitsagames.bundle /opt/gornitsa && REPO=/root/gornitsagames.bundle bash /opt/gornitsa/deploy/bootstrap.sh'
   ```

5. **Базы.** Для каждой игры (`votchina`, `nardy`, `skazy`):

   ```bash
   ssh root@НОВЫЙ_АДРЕС 'systemctl stop votchina'
   age -d -i ~/.gornitsa/age-key.txt votchina.db.gz.age | ssh root@НОВЫЙ_АДРЕС \
     'gunzip > /var/lib/votchina/votchina.db && rm -f /var/lib/votchina/votchina.db-wal /var/lib/votchina/votchina.db-shm && chown votchina: /var/lib/votchina/votchina.db && systemctl start votchina'
   ```

6. **Проверка:**
   - `curl https://votchina.gornitsa.games/v1/ping` (и `nardy`, `skazy`);
   - `https://gornitsa.games/.well-known/monitor/status.json`;
   - вход `ssh gornitsa@НОВЫЙ_АДРЕС`.

   Сборки серверов игры подтянут сами из веток `vps` за 2 минуты.
7. **Закрыть вход root** — как в README, «Вход на сервер», шаги 4–6: `ssh gornitsa@НОВЫЙ_АДРЕС`,
   `sudo whoami`, затем `sudo gornitsa-ssh ok`.

Пропало только что-то одно (например, испорчена база) — восстанавливается только шаг 5 этой игры
на старой машине.

## 2. Пропала машина «Сеней»

Если есть свежий файл переезда (`sudo seni-migrate export`), — `docs/05-deploy.md` в `Nefeste/seni`,
«Переезд». Если нет — из ежедневной копии:

1. Новая VPS, A-запись `seni` на её адрес.
2. Настройки — до установки, чтобы установщик взял прежний ключ доступа к репозиторию:

   ```bash
   age -d -i ~/.gornitsa/age-key.txt seni-config.tar.gz.age | ssh root@НОВЫЙ_АДРЕС \
     'tar -xzpf - -C / --exclude=etc/ssh/sshd_config.d'
   ```

3. Установка — команда из README, «Сени — шлюз студии». Ключ уже на месте, поэтому ждать, пока его
   добавят в GitHub, не придётся.
4. База:

   ```bash
   ssh root@НОВЫЙ_АДРЕС 'systemctl stop seni'
   age -d -i ~/.gornitsa/age-key.txt seni.db.gz.age | ssh root@НОВЫЙ_АДРЕС \
     'gunzip > /var/lib/seni/seni.db && rm -f /var/lib/seni/seni.db-wal /var/lib/seni/seni.db-shm && chown seni: /var/lib/seni/seni.db && systemctl start seni'
   ```

## 3. Пропал доступ к GitHub

Всё нужное есть в `GornitsaBackup/github`.

1. **Новое место для кода.** Новый аккаунт или организация GitHub — или другой хостинг git,
   например российский GitFlic. Для каждого репозитория создайте пустой и залейте зеркало:

   ```bash
   cd ~/GornitsaBackup/github/git/votchina.git
   git push --mirror https://github.com/НОВЫЙ/votchina.git
   ```

   Если зеркала нет, а есть только bundle:
   `git clone --mirror bundles/<дата>/votchina.bundle votchina.git`, затем тот же `git push --mirror`.
2. **Секреты Actions.** Их значения GitHub не отдаёт: они в менеджере паролей, по реестру
   `uprava/owner/secrets.md`. Список имён для каждого репозитория — в
   `github/<репо>/actions-secret-names.json`. Переменные Actions вместе со значениями — в
   `actions-variables.json`.
3. **Ключи доступа машин.** Ключи доступа (Deploy keys) — в новые репозитории, без права записи.
   Открытые ключи — в `github/<репо>/deploy-keys.json` или на машинах (`/etc/<игра>/deploy_key.pub`).
4. **Адреса в коде.** Машины забирают код с `github.com/Nefeste/…`: адреса записаны в
   `deploy/*/pull.sh`, `deploy/bootstrap.sh` и `deploy/seni-bootstrap.sh`. С новым адресом их нужно
   поменять — это одна правка в каждом файле, её делает агент.
5. **Issues и PR.** Они в `github/<репо>/issues.json` и `pulls.json` — для чтения. Переносить их в
   новый репозиторий не обязательно.

## 4. Пропал ваш компьютер

1. **Ключ age** — из менеджера паролей или из бумажной копии. Без него ни одну старую копию не
   открыть.
2. **Ключ SSH** — новый (шаг 2 [`backup.md`](backup.md)). Поставьте его на обеих машинах:
   `sudo gornitsa-backup-keys`. Вход `gornitsa` на сервер — допишите новый ключ в
   `/home/gornitsa/.ssh/authorized_keys` через консоль Рег.облака.
3. **Забор копий** — заново по [`backup.md`](backup.md), шаги 3–4 и 7. Копии на сервере хранятся
   14 дней, так что последние две недели не потеряются.

## Раз в квартал — проверка, что восстановление возможно

- **Ключи подписи APK.** Ключ каждой игры, пароли и псевдоним есть в менеджере паролей. Отпечаток
  ключа совпадает с переменной `ANDROID_CERT_SHA256` игры:

  ```bash
  keytool -list -v -keystore <ключ>.jks -alias <псевдоним> | grep SHA256
  ```

  Реестр секретов — `uprava/owner/secrets.md`.
- **Копии.**
  - `check-backup.py` проходит по свежей папке: базы и архив настроек читаются.
  - `github/last-run.json` не старше недели, в нём нет ошибок.
