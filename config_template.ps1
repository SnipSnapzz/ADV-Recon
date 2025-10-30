<#
.SYNOPSIS
  Safe config template for generated PowerShell scripts.
.DESCRIPTION
  This is intentionally benign... replace placeholders only for authorized lab use. Dont be evil :)
#>

$ScriptConfig = @{
    ProjectName = "PS-Builder-Demo"
    SafeMode    = $true
    Debug       = $true
    LogPath     = (Join-Path -Path $env:TEMP -ChildPath "ps_builder_demo.log")
}

function Write-SafeLog {
    param([string]$Message)
    try {
        $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $entry = "$ts`t$Message"
        $dir = Split-Path -Parent $ScriptConfig.LogPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -Path $ScriptConfig.LogPath -Value $entry -ErrorAction SilentlyContinue
    } catch {}
}

Write-SafeLog "Generated script started. SafeMode=$($ScriptConfig.SafeMode) Debug=$($ScriptConfig.Debug)"
