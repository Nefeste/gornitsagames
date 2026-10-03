# Забор копий баз «Горницы» на компьютер владельца — Windows (docs/backup.md, шаг 4).
# Запускает Планировщик заданий раз в сутки; вручную:
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\Gornitsa\pull-backup.ps1
# Забирает папки копий за последние 3 дня (rclone copy --max-age 3d; уже забранное не качает
# повторно), а свои папки старше 14 дней удаляет: удалённый профиль игрока не должен жить в копиях
# дольше, чем обещает политика (удаление в течение 30 дней).
param(
  [string]$Dest = "D:\GornitsaBackup",   # папка на диске с BitLocker, не в OneDrive и не в Яндекс Диске
  [string]$Remote = "gornitsa-backup:out",
  [int]$KeepDays = 14
)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$log = Join-Path $Dest "pull.log"

& rclone copy $Remote $Dest --max-age 3d --log-file $log --log-level INFO
if ($LASTEXITCODE -ne 0) { throw "rclone завершился с кодом $LASTEXITCODE — подробности в $log" }

$cutoff = (Get-Date).AddDays(-$KeepDays).ToString("yyyy-MM-dd")
Get-ChildItem -Path $Dest -Directory |
  Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.Name -lt $cutoff } |
  ForEach-Object { Remove-Item -Recurse -Force $_.FullName; Add-Content $log "удалена старая копия $($_.Name)" }
