# Копии на вашем компьютере

Решение владельца №15: копии баз серверов игр хранятся у вас на компьютере, а забираются по SFTP.
Как это устроено на сервере — README, раздел «Копии баз». Вместе с базами вы получаете всё, чтобы
поднять машины заново, а раз в неделю — копию всех репозиториев с GitHub. Как восстановить всё
с нуля — [`restore.md`](restore.md).

Коротко:
- **Сервер.** Раз в сутки, в 03:30 по Москве, сервер снимает базы «Вотчины», «Нард» и «Сказов»
  и собирает **архив настроек машины**: настройки служб и их секреты, ключи доступа к
  репозиториям, ключ шифрования «Узоров», сертификаты HTTPS, ключи SSH машины. Каждую копию он
  проверяет, сжимает и шифрует вашим **открытым** ключом age. Расшифровать копию может только ваш
  **закрытый** ключ, а его на сервере нет.
- **Компьютер.** Раз в сутки он сам забирает свежие копии по SFTP. Пользователь `backup` на сервере
  может только читать копии.
- **Проверка.** Раз в месяц вы проверяете, что копия восстанавливается.
- **GitHub.** Раз в неделю компьютер сам сохраняет все репозитории студии: историю, Issues, PR,
  релизы и их файлы (шаг 7).

В базах есть персональные данные игроков: ники, теги, переписка застав. Поэтому:
- **Ключ age.** Закрытый ключ age никому не отправляйте и не храните в облаке.
- **Хранение.** Копии храните только на диске с шифрованием.
- **Срок.** Копии старше 14 дней удаляйте — скрипт забора делает это сам.

Сервер тоже хранит копии 14 дней. Вместе это не дольше 28 дней, и удалённый профиль исчезает
из копий в срок, который обещает политика: удаляем в течение 30 дней.

Шаги 1–4 и 7 делаются один раз, шаг 6 — раз в месяц.

## 1. Программы

**Windows 10 или 11.** Откройте «Терминал» (PowerShell) и выполните:

```powershell
winget install FiloSottile.age
winget install Rclone.Rclone
winget install Python.Python.3.12
```

Закройте и снова откройте терминал. Клиент SSH (`ssh`, `ssh-keygen`, `sftp`) в Windows уже есть.

**macOS.** Поставьте Homebrew (https://brew.sh), затем в «Терминале»:

```bash
brew install age rclone python
```

## 2. Ключи — создать и прислать только открытые части

**Ключ SSH** — им компьютер входит на сервер.

Windows (PowerShell):
```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\gornitsa_backup" -C "gornitsa-backup"
```

macOS:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/gornitsa_backup -C "gornitsa-backup"
```

На вопрос о пароле (passphrase) нажмите Enter дважды. Без пароля компьютер сможет забирать копии
сам, по расписанию. Защиту даёт шифрование диска (шаг 3). Получится два файла:
- **`gornitsa_backup`** — закрытый ключ. Он остаётся на компьютере.
- **`gornitsa_backup.pub`** — открытый ключ. Он идёт на сервер.

**Ключ age** — им шифруются копии.

Windows:
```powershell
mkdir "$env:USERPROFILE\.gornitsa" -Force
age-keygen -o "$env:USERPROFILE\.gornitsa\age-key.txt"
```

macOS:
```bash
mkdir -p ~/.gornitsa && chmod 700 ~/.gornitsa
age-keygen -o ~/.gornitsa/age-key.txt
```

Команда покажет `Public key: age1…` — это открытая часть. В файле `age-key.txt` лежит закрытый
ключ: строка `AGE-SECRET-KEY-1…`.

**Сделайте копию закрытого ключа age на бумаге или на флешке и уберите её в надёжное место.**
Потеряете ключ — ни одну копию уже не расшифровать.

**Поставить открытые ключи на сервер.** Войдите на сервер (`ssh gornitsa@gornitsa.games`) и выполните:

```bash
sudo gornitsa-backup-keys
```

Команда попросит две строки:
- **ключ SSH** — содержимое `gornitsa_backup.pub`, строка вида `ssh-ed25519 AAAA… gornitsa-backup`;
- **ключ age** — строка `age1…`.

Закрытые ключи команда не примет. В конце она покажет **отпечаток сервера** — запишите его для шага 4.

Можно и иначе: прислать обе открытые строки агенту в сессию. Они не секретны, но в репозиторий
не кладутся — агент подскажет, как вставить их на сервере.

## 3. Где хранить

Нужна отдельная папка на диске с шифрованием.
- **Windows.** Диск с BitLocker («Параметры» → «Конфиденциальность и защита» → «Шифрование
  устройства» или «Управление BitLocker»), папка `D:\GornitsaBackup`.
- **macOS.** Включённый FileVault («Системные настройки» → «Конфиденциальность и безопасность»),
  папка `~/GornitsaBackup`.

Не годятся:
- **Облачные папки:** OneDrive, iCloud Drive, Яндекс Диск, Google Drive, Dropbox. Это уже
  передача копий третьей стороне, возможно за границу.
- **«Рабочий стол» и «Документы» на macOS,** если они синхронизируются с iCloud.

Папку лучше исключить из Time Machine и «Истории файлов». Иначе там останутся копии старше 14 дней,
а это нарушает срок удаления.

## 4. Забирать копии автоматически

**Сначала один раз войдите вручную** — так компьютер запомнит сервер:

```bash
sftp -i ~/.ssh/gornitsa_backup backup@gornitsa.games
```

В Windows путь к ключу — `$env:USERPROFILE\.ssh\gornitsa_backup`. Сверьте отпечаток, который
покажет `sftp`, с отпечатком из шага 2, и ответьте `yes`. Дальше:
- `ls out` — показывает папки по датам;
- `bye` — выход.

**Настроить rclone.** Скрипты забора ищут удалённое хранилище с именем `gornitsa-backup`.

Windows:
```powershell
rclone config create gornitsa-backup sftp host gornitsa.games user backup `
  key_file "$env:USERPROFILE\.ssh\gornitsa_backup" known_hosts_file "$env:USERPROFILE\.ssh\known_hosts" `
  shell_type none md5sum_command none sha1sum_command none disable_hashcheck true
```

macOS:
```bash
rclone config create gornitsa-backup sftp host gornitsa.games user backup \
  key_file ~/.ssh/gornitsa_backup known_hosts_file ~/.ssh/known_hosts \
  shell_type none md5sum_command none sha1sum_command none disable_hashcheck true
```

`shell_type none` нужен потому, что на сервере у `backup` нет shell, только SFTP.

Проверка — эта команда должна забрать копии за 3 дня в папку:

```bash
rclone copy gornitsa-backup:out D:\GornitsaBackup --max-age 3d -v     # Windows
rclone copy gornitsa-backup:out ~/GornitsaBackup --max-age 3d -v      # macOS
```

### Windows — Планировщик заданий

1. Скачайте из репозитория `deploy/backup/owner/pull-backup.ps1` и `deploy/backup/check-backup.py`
   в `C:\Gornitsa\`. Если копии лежат не в `D:\GornitsaBackup`, поправьте `$Dest` в начале
   `pull-backup.ps1`.
2. В PowerShell (обычный, не от администратора):

```powershell
$a = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Gornitsa\pull-backup.ps1"'
$t = New-ScheduledTaskTrigger -Daily -At 10:00
$s = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable
Register-ScheduledTask -TaskName "Горница — копии баз" -Action $a -Trigger $t -Settings $s
```

Как это работает:
- **Запуск в 10:00.** Если компьютер в это время был выключен, задание запустится, как только
  он включится и появится сеть.
- **Проверить вручную:** `Start-ScheduledTask "Горница — копии баз"`.
- **Журнал** — `D:\GornitsaBackup\pull.log`.

### macOS — launchd

1. Скачайте `deploy/backup/owner/pull-backup.sh` и `deploy/backup/check-backup.py`
   в `~/Gornitsa/`, а `deploy/backup/owner/games.gornitsa.backup.plist` —
   в `~/Library/LaunchAgents/`.
2. В plist замените `ИМЯ` на своё имя пользователя (команда `whoami`). Затем:

```bash
mkdir -p ~/GornitsaBackup
launchctl load ~/Library/LaunchAgents/games.gornitsa.backup.plist
launchctl start games.gornitsa.backup      # проверить сразу
```

Как это работает:
- **Запуск в 10:00.** Если Mac спал, задание запустится, когда он проснётся.
- **Журнал** — `~/GornitsaBackup/pull.log`.

### Вручную — WinSCP или FileZilla

Запасной вариант, если rclone не работает. Протокол SFTP, сервер `gornitsa.games`,
порт 22, пользователь `backup`, пароля нет, ключ — `gornitsa_backup`:
- WinSCP: «Дополнительно» → SSH → «Аутентификация» → файл ключа; WinSCP сам предложит
  перевести ключ в формат `.ppk`.
- FileZilla: «Настройки» → SFTP → «Добавить файл ключа».

Скачайте свежие папки из `out` в папку копий. Записать или удалить что-то на сервере нельзя —
так и задумано.

## 5. Что лежит в папке копий

```
GornitsaBackup/
  2026-10-04/
    votchina.db.gz.age     база, сжатая и зашифрованная вашим ключом age
    nardy.db.gz.age
    skazy.db.gz.age
    site-config.tar.gz.age архив настроек машины с секретами служб — тоже зашифрован вашим ключом
    manifest.json          имя, размеры и sha256 каждой копии, итог проверки
  pull.log
```

Архив настроек нужен только для того, чтобы поднять машину заново ([`restore.md`](restore.md)).
В нём пароли и ключи служб, поэтому он, как и базы, расшифровывается только вашим ключом age.

`manifest.json` не зашифрован: в нём только размеры, контрольные суммы и результат проверки,
данных игроков нет.

## 6. Раз в месяц — проверка восстановления

Скрипт `check-backup.py` делает всё сам:
- берёт самую свежую папку и расшифровывает каждую базу во временную папку;
- сверяет sha256 с `manifest.json`;
- делает `PRAGMA integrity_check` и считает строки в таблицах;
- удаляет расшифрованное.

Содержимое баз скрипт не показывает — только числа.

Windows:
```powershell
python C:\Gornitsa\check-backup.py --key "$env:USERPROFILE\.gornitsa\age-key.txt" D:\GornitsaBackup
```

macOS:
```bash
python3 ~/Gornitsa/check-backup.py --key ~/.gornitsa/age-key.txt ~/GornitsaBackup
```

В конце скрипт пишет одно из двух:
- **«Итог: всё восстанавливается»** — всё в порядке.
- **«ЕСТЬ ОШИБКИ»** — пришлите вывод в сессию агенту. В выводе нет данных игроков, только
  числа строк.

Числа строк полезно сравнивать с прошлым месяцем: если в таблице профилей вдруг стало намного
меньше записей, что-то не так.

## 7. Раз в неделю — копия GitHub

На случай, если пропадёт доступ к GitHub или репозитории придётся разворачивать заново, компьютер
раз в неделю сохраняет все репозитории `Nefeste` (и закрытые) со всей историей, Issues, PR,
релизами и файлами последних релизов (APK). Делает это `deploy/backup/owner/backup-github.py`
вашим обычным входом в GitHub. На серверах студии для этого ничего не нужно.

**Программы:** git и GitHub CLI.
- Windows: `winget install Git.Git GitHub.cli`.
- macOS: `brew install git gh`.

Один раз войдите и разрешите git брать вход у gh:

```bash
gh auth login        # GitHub.com → HTTPS → войти в браузере аккаунтом Nefeste
gh auth setup-git
```

**Первый запуск вручную.** Скачайте `deploy/backup/owner/backup-github.py` в `C:\Gornitsa\`
(macOS — в `~/Gornitsa/`) и выполните:

```bash
python C:\Gornitsa\backup-github.py D:\GornitsaBackup\github          # Windows
python3 ~/Gornitsa/backup-github.py ~/GornitsaBackup/github             # macOS
```

Первый раз — дольше: скачивается вся история и файлы релизов. В конце — «Всё сохранено.»

**По расписанию — Windows:**

```powershell
$a = New-ScheduledTaskAction -Execute "python.exe" `
  -Argument 'C:\Gornitsa\backup-github.py D:\GornitsaBackup\github'
$t = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 11:00
$s = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable
Register-ScheduledTask -TaskName "Горница — копия GitHub" -Action $a -Trigger $t -Settings $s
```

**По расписанию — macOS:** `deploy/backup/owner/games.gornitsa.github.plist` — в
`~/Library/LaunchAgents/`, заменить `ИМЯ` и выполнить
`launchctl load ~/Library/LaunchAgents/games.gornitsa.github.plist`. Журнал — `~/GornitsaBackup/github.log`.

Что получится в `GornitsaBackup/github`:

```
git/<репо>.git             зеркало каждого репозитория: все ветки, теги, история
bundles/ГГГГ-ММ-ДД/        <репо>.bundle — один файл на репозиторий; хранятся 4 недели
github/<репо>/             Issues, PR, комментарии, релизы, метки; переменные Actions;
                           ИМЕНА секретов Actions (значения GitHub не отдаёт — они в реестре
                           секретов, uprava/owner/secrets.md)
releases/<репо>/<тег>/     APK и другие файлы трёх последних релизов
last-run.json              итог последнего запуска
```

Здесь нет данных игроков, но есть закрытый код студии. Храните в той же папке на зашифрованном
диске. Для копии на флешке — папка `bundles/` последней даты на флешке с шифрованием (BitLocker
To Go или APFS с шифрованием на macOS).

Правило «не дольше 14 дней» к этим копиям не относится: персональных данных в них нет.

## Если что-то случилось

- **Сторож пишет «копии не забирали больше 3 суток».** Проверьте, что компьютер включался,
  и посмотрите `pull.log`. Запустить забор можно и вручную.
- **Новый компьютер.**
  - Перенесите `age-key.txt`, иначе старые копии не открыть.
  - Сделайте новый ключ SSH (шаг 2) и запустите `sudo gornitsa-backup-keys` с новым открытым ключом.
- **Ключ age потерян или украден.**
  - Сделайте новый ключ age и поставьте его через `sudo gornitsa-backup-keys`.
  - Если ключ украден, старые копии на компьютере удалите: их можно расшифровать украденным ключом.
- **Восстановить базу на сервере.** Это делает агент вместе с вами. Расшифрованную базу нужно
  вернуть на сервер, а закрытый ключ age при этом остаётся у вас: сервер его не получает.
  Порядок для каждой игры — в README, разделы серверов игр.
- **Пропала машина, доступ к GitHub или всё сразу** — [`restore.md`](restore.md).

## Машина «Сеней»

«Сени» работают на своей машине `seni.gornitsa.games`, и там своя база с почтой и перепиской.
Копии с неё забираются так же, вторым хранилищем rclone:
- имя `seni-backup`, хост `seni.gornitsa.games`;
- своя папка, например `GornitsaBackup\seni`;
- `-Remote seni-backup:out -Dest D:\GornitsaBackup\seni` в задании.

С той машины приходят `seni.db.gz.age` и архив настроек `seni-config.tar.gz.age`: пароли почты и
токены каналов из `/etc/seni`. Файл переезда (`sudo seni-migrate export`) по-прежнему годится для
переезда «Сеней» — архив его не заменяет, а дублирует на случай, если старой машины уже нет.

Как набор ставится на ту машину — README, раздел «Копии баз».
