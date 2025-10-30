<#
.SYNOPSIS
    user and activity reconnaissance module
.DESCRIPTION
    Gathers user information, recent files, PowerShell history, scheduled tasks, and more
#>

function Get-UserInformation {
    $userInfo = @{}

    # Current user
    try {
        $localUser = Get-LocalUser -Name $env:USERNAME -ErrorAction SilentlyContinue
        $userInfo.Username = $env:USERNAME
        $userInfo.FullName = if ($localUser) { $localUser.FullName } else { $env:USERNAME }
        $userInfo.UserProfile = $env:USERPROFILE
        $userInfo.Enabled = if ($localUser) { $localUser.Enabled } else { "Unknown" }
        $userInfo.LastLogon = if ($localUser) { $localUser.LastLogon } else { "Unknown" }
    } catch {
        $userInfo.Username = $env:USERNAME
        $userInfo.FullName = $env:USERNAME
    }

    # Email
    try {
        $email = (Get-CimInstance CIM_ComputerSystem -ErrorAction SilentlyContinue).PrimaryOwnerName
        $userInfo.Email = if ($email) { $email } else { "Not detected" }
    } catch {
        $userInfo.Email = "Not detected"
    }

    # Local Users
    try {
        $userInfo.AllLocalUsers = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True" | 
            Select-Object Name, FullName, Disabled, Status, SID
    } catch {
        $userInfo.AllLocalUsers = "Unable to retrieve"
    }

    try {
        $userInfo.UserGroups = (whoami /groups /fo csv | ConvertFrom-Csv | Select-Object 'Group Name', Type)
    } catch {
        $userInfo.UserGroups = "Unable to retrieve"
    }

    return $userInfo
}

function Get-PowerShellHistory {
    $historyPath = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
    
    if (Test-Path $historyPath) {
        try {
            $history = Get-Content -Path $historyPath -ErrorAction Stop
            return $history
        } catch {
            return "Unable to read PowerShell history"
        }
    } else {
        return "PowerShell history file not found"
    }
}

function Get-RecentFiles {
    param(
        [int]$Count = 100
    )

    try {
        $recentFiles = Get-ChildItem -Path $env:USERPROFILE -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt (Get-Date).AddDays(-30) } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $Count FullName, LastWriteTime, Length, Extension

        return $recentFiles
    } catch {
        return "Unable to retrieve recent files"
    }
}

function Get-StartupPrograms {
    $startupItems = @()

    try {
        $startupFolder = [Environment]::GetFolderPath("Startup")
        $folderItems = Get-ChildItem -Path $startupFolder -ErrorAction SilentlyContinue | 
            Select-Object Name, FullName
        $startupItems += $folderItems
    } catch {}

    $registryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    )

    foreach ($path in $registryPaths) {
        try {
            $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            if ($items) {
                $items.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
                    $startupItems += [PSCustomObject]@{
                        Name = $_.Name
                        Command = $_.Value
                        Location = $path
                    }
                }
            }
        } catch {}
    }

    return $startupItems
}

function Get-ScheduledTasksInfo {
    try {
        $tasks = Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' } |
            Select-Object TaskName, TaskPath, State, 
                @{Name='Author';Expression={$_.Principal.UserId}},
                @{Name='RunLevel';Expression={$_.Principal.RunLevel}},
                @{Name='LastRunTime';Expression={$_.LastRunTime}},
                @{Name='NextRunTime';Expression={$_.NextRunTime}}

        return $tasks
    } catch {
        return "Unable to retrieve scheduled tasks"
    }
}

function Get-InstalledSoftware {
    $software = @()

    $registryPaths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($path in $registryPaths) {
        try {
            $software += Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName } |
                Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation
        } catch {}
    }

    return $software | Sort-Object DisplayName -Unique
}

function Get-RunningProcesses {
    try {
        $processes = Get-Process | 
            Select-Object Id, ProcessName, Path, Company, ProductVersion, 
                @{Name='Memory(MB)';Expression={[math]::Round($_.WorkingSet64 / 1MB, 2)}},
                @{Name='CPU(s)';Expression={$_.TotalProcessorTime.TotalSeconds}},
                StartTime |
            Sort-Object 'Memory(MB)' -Descending

        return $processes
    } catch {
        return "Unable to retrieve process list"
    }
}

function Get-ActiveConnections {
    try {
        $connections = Get-NetTCPConnection | 
            Where-Object { $_.State -eq 'Established' } |
            Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess,
                @{Name='ProcessName';Expression={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}} |
            Sort-Object RemoteAddress

        return $connections
    } catch {
        return "Unable to retrieve active connections"
    }
}

function Get-GeoLocation {
    try {
        Add-Type -AssemblyName System.Device
        $geoWatcher = New-Object System.Device.Location.GeoCoordinateWatcher
        $geoWatcher.Start()

        $timeout = 0
        while (($geoWatcher.Status -ne 'Ready') -and ($geoWatcher.Permission -ne 'Denied') -and ($timeout -lt 30)) {
            Start-Sleep -Milliseconds 100
            $timeout++
        }

        if ($geoWatcher.Permission -eq 'Denied') {
            return "Location permission denied"
        } 
        elseif ($geoWatcher.Status -eq 'Ready') {
            $location = $geoWatcher.Position.Location
            return [PSCustomObject]@{
                Latitude = $location.Latitude
                Longitude = $location.Longitude
            }
        }
        else {
            return "Unable to determine location"
        }
    } catch {
        return "Error retrieving geolocation: $($_.Exception.Message)"
    }
}

function Export-UserReconReport {
    param(
        [string]$OutputPath
    )

    $userInfo = Get-UserInformation
    $geoLocation = Get-GeoLocation
    $psHistory = Get-PowerShellHistory
    $recentFiles = Get-RecentFiles -Count 50
    $startup = Get-StartupPrograms
    $tasks = Get-ScheduledTasksInfo
    $software = Get-InstalledSoftware
    $processes = Get-RunningProcesses
    $connections = Get-ActiveConnections

    $report = @"
====================================================================================================
USER RECONNAISSANCE REPORT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
====================================================================================================

USER INFORMATION
----------------------------------------------------------------------------------------------------
Username:               $($userInfo.Username)
Full Name:              $($userInfo.FullName)
Email:                  $($userInfo.Email)
Profile Path:           $($userInfo.UserProfile)
Account Enabled:        $($userInfo.Enabled)
Last Logon:             $($userInfo.LastLogon)

GEOLOCATION
----------------------------------------------------------------------------------------------------
$($geoLocation | Format-List | Out-String)

ALL LOCAL USERS
----------------------------------------------------------------------------------------------------
$($userInfo.AllLocalUsers | Format-Table -AutoSize | Out-String)

USER GROUPS
----------------------------------------------------------------------------------------------------
$($userInfo.UserGroups | Format-Table -AutoSize | Out-String)

POWERSHELL HISTORY (Last 20 commands)
----------------------------------------------------------------------------------------------------
$(if ($psHistory -is [array]) { $psHistory | Select-Object -Last 20 | Out-String } else { $psHistory })

RECENT FILES (Last 30 days, Top 50)
----------------------------------------------------------------------------------------------------
$($recentFiles | Format-Table FullName, LastWriteTime, Length -AutoSize | Out-String)

STARTUP PROGRAMS
----------------------------------------------------------------------------------------------------
$($startup | Format-Table -AutoSize | Out-String)

SCHEDULED TASKS (Active)
----------------------------------------------------------------------------------------------------
$($tasks | Select-Object -First 30 | Format-Table -AutoSize | Out-String)

INSTALLED SOFTWARE (Top 50)
----------------------------------------------------------------------------------------------------
$($software | Select-Object -First 50 | Format-Table DisplayName, DisplayVersion, Publisher -AutoSize | Out-String)

RUNNING PROCESSES (Top 30 by Memory)
----------------------------------------------------------------------------------------------------
$($processes | Select-Object -First 30 | Format-Table -AutoSize | Out-String)

ACTIVE NETWORK CONNECTIONS
----------------------------------------------------------------------------------------------------
$($connections | Format-Table -AutoSize | Out-String)

====================================================================================================
"@

    $report | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Output "User recon report exported to: $OutputPath"
}