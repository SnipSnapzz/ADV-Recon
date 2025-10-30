<#
.SYNOPSIS
    Browser data extraction module
.DESCRIPTION
    Extracts history, bookmarks, and cookies from Chrome, Edge, and Firefox
#>

function Get-BrowserData {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Chrome', 'Edge', 'Firefox')]
        [string]$Browser,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet('History', 'Bookmarks', 'Cookies')]
        [string]$DataType,
        
        [string]$OutputFolder = $env:TEMP
    )

    $results = @()
    $urlRegex = '(https?):\/\/([\w-]+\.)+[\w-]+(\/[\w\-\.\/\?%&=]*)?'

    $path = switch ("$Browser-$DataType") {
        'Chrome-History'    { "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\History" }
        'Chrome-Bookmarks'  { "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Bookmarks" }
        'Chrome-Cookies'    { "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Network\Cookies" }
        'Edge-History'      { "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\History" }
        'Edge-Bookmarks'    { "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks" }
        'Edge-Cookies'      { "$env:USERPROFILE\AppData\Local\Microsoft\Edge\User Data\Default\Network\Cookies" }
        'Firefox-History'   { (Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*.default-release\places.sqlite" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }
        'Firefox-Cookies'   { (Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*.default-release\cookies.sqlite" -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }
    }

    if (-not $path -or -not (Test-Path $path)) {
        Write-Output "[$Browser] $DataType database not found at: $path"
        return $null
    }

    if ($Browser -in @('Chrome', 'Edge') -and $DataType -in @('History', 'Cookies')) {
        $tempDb = Join-Path $env:TEMP "temp_$($Browser)_$($DataType)_$(Get-Random).db"
        try {
            Copy-Item -Path $path -Destination $tempDb -Force -ErrorAction Stop
            $content = Get-Content -Path $tempDb -Raw -Encoding Byte -ErrorAction SilentlyContinue
            if ($content) {
                $textContent = [System.Text.Encoding]::ASCII.GetString($content)
                $matches = [regex]::Matches($textContent, $urlRegex)
                $results = $matches | Select-Object -ExpandProperty Value | Sort-Object -Unique
            }
            
            Remove-Item -Path $tempDb -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Output "Error accessing $Browser $DataType : $($_.Exception.Message)"
            return $null
        }
    }
    
    elseif ($DataType -eq 'Bookmarks') {
        try {
            $content = Get-Content -Path $path -Raw | ConvertFrom-Json
            $results = Get-BookmarkUrls -BookmarkNode $content.roots
        } catch {
            Write-Output "Error parsing bookmarks: $($_.Exception.Message)"
            return $null
        }
    }

    elseif ($Browser -eq 'Firefox') {
        $tempDb = Join-Path $env:TEMP "temp_firefox_$(Get-Random).db"
        try {
            Copy-Item -Path $path -Destination $tempDb -Force -ErrorAction Stop
            $content = Get-Content -Path $tempDb -Raw -Encoding Byte -ErrorAction SilentlyContinue
            if ($content) {
                $textContent = [System.Text.Encoding]::ASCII.GetString($content)
                $matches = [regex]::Matches($textContent, $urlRegex)
                $results = $matches | Select-Object -ExpandProperty Value | Sort-Object -Unique
            }
            Remove-Item -Path $tempDb -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Output "Error accessing Firefox data: $($_.Exception.Message)"
            return $null
        }
    }

    return $results
}

function Get-BookmarkUrls {
    param($BookmarkNode)
    
    $urls = @()
    
    foreach ($prop in $BookmarkNode.PSObject.Properties) {
        $node = $prop.Value
        if ($node.type -eq 'url') {
            $urls += $node.url
        }
        elseif ($node.children) {
            $urls += Get-BookmarkUrls -BookmarkNode $node
        }
    }
    
    return $urls
}

function Export-BrowserDataReport {
    param(
        [string]$OutputPath
    )

    $report = @"
====================================================================================================
BROWSER DATA EXTRACTION REPORT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
====================================================================================================

"@

    $browsers = @('Chrome', 'Edge', 'Firefox')
    $dataTypes = @('History', 'Bookmarks')

    foreach ($browser in $browsers) {
        $report += "`n$browser BROWSER DATA`n"
        $report += "-" * 100 + "`n"
        
        foreach ($dataType in $dataTypes) {
            $data = Get-BrowserData -Browser $browser -DataType $dataType
            
            if ($data) {
                $report += "`n$dataType (Total: $($data.Count)):`n"
                $report += ($data | Select-Object -First 50 | Out-String)
                if ($data.Count -gt 50) {
                    $report += "`n... and $($data.Count - 50) more entries`n"
                }
            } else {
                $report += "`n$dataType : No data found or unable to access`n"
            }
        }
        $report += "`n"
    }

    $report | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Output "Browser data exported to: $OutputPath"
}

function Copy-FirefoxCookies {
    param(
        [string]$OutputFolder = $env:TEMP
    )

    $firefoxProfilePath = Join-Path $env:APPDATA "Mozilla\Firefox\Profiles"
    
    if (-not (Test-Path $firefoxProfilePath)) {
        Write-Output "Firefox profile path not found"
        return $null
    }

    $firefoxProfile = Get-ChildItem -Path $firefoxProfilePath | Where-Object { $_.Name -like "*default-release" } | Select-Object -First 1
    
    if (-not $firefoxProfile) {
        Write-Output "Firefox default profile not found"
        return $null
    }

    $cookiesPath = Join-Path $firefoxProfile.FullName "cookies.sqlite"
    
    if (-not (Test-Path $cookiesPath)) {
        Write-Output "Firefox cookies database not found"
        return $null
    }

    $outputPath = Join-Path $OutputFolder "firefox_cookies_$(Get-Date -Format 'yyyyMMdd_HHmmss').sqlite"
    
    try {
        Copy-Item -Path $cookiesPath -Destination $outputPath -Force
        Write-Output "Firefox cookies copied to: $outputPath"
        return $outputPath
    } catch {
        Write-Output "Error copying Firefox cookies: $($_.Exception.Message)"
        return $null
    }
}