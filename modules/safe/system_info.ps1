<#
.SYNOPSIS
    system information gathering module
.DESCRIPTION
    Collects comprehensive system details including hardware, network, and security settings
#>

function Get-SystemInfo {
    param(
        [string]$OutputFolder = $env:TEMP
    )

    $output = @{}

    # System
    try {
        $computerSystem = Get-CimInstance CIM_ComputerSystem
        $output.ComputerName = $computerSystem.Name
        $output.Model = $computerSystem.Model
        $output.Manufacturer = $computerSystem.Manufacturer
        $output.Domain = $computerSystem.Domain
        $output.TotalPhysicalMemory = "{0:N2} GB" -f ($computerSystem.TotalPhysicalMemory / 1GB)
    } catch {
        $output.ComputerSystemError = $_.Exception.Message
    }

    # BIOS
    try {
        $bios = Get-CimInstance CIM_BIOSElement
        $output.BIOSVersion = $bios.Version
        $output.BIOSManufacturer = $bios.Manufacturer
        $output.SerialNumber = $bios.SerialNumber
    } catch {
        $output.BIOSError = $_.Exception.Message
    }

    # OS
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $output.OSCaption = $os.Caption
        $output.OSVersion = $os.Version
        $output.OSArchitecture = $os.OSArchitecture
        $output.InstallDate = $os.InstallDate
        $output.LastBootUpTime = $os.LastBootUpTime
    } catch {
        $output.OSError = $_.Exception.Message
    }

    # CPU
    try {
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $output.CPUName = $cpu.Name
        $output.CPUManufacturer = $cpu.Manufacturer
        $output.CPUCores = $cpu.NumberOfCores
        $output.CPULogicalProcessors = $cpu.NumberOfLogicalProcessors
        $output.CPUMaxClockSpeed = "$($cpu.MaxClockSpeed) MHz"
    } catch {
        $output.CPUError = $_.Exception.Message
    }

    # RAM
    try {
        $ram = Get-CimInstance Win32_PhysicalMemory
        $output.RAMModules = $ram | ForEach-Object {
            [PSCustomObject]@{
                Capacity = "{0:N2} GB" -f ($_.Capacity / 1GB)
                Speed = "$($_.Speed) MHz"
                Manufacturer = $_.Manufacturer
                PartNumber = $_.PartNumber
            }
        }
    } catch {
        $output.RAMError = $_.Exception.Message
    }

    # Network
    try {
        $output.PublicIP = (Invoke-WebRequest -Uri "https://api.ipify.org" -UseBasicParsing -TimeoutSec 5).Content
    } catch {
        $output.PublicIP = "Unable to retrieve"
    }

    try {
        $netAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
        $output.NetworkAdapters = $netAdapters | ForEach-Object {
            $ipConfig = Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                Name = $_.Name
                MacAddress = $_.MacAddress
                Status = $_.Status
                LinkSpeed = $_.LinkSpeed
                IPAddress = $ipConfig.IPAddress
            }
        }
    } catch {
        $output.NetworkError = $_.Exception.Message
    }

    # Security
    try {
        $uacKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        $consentPrompt = (Get-ItemProperty -Path $uacKey -Name ConsentPromptBehaviorAdmin -ErrorAction SilentlyContinue).ConsentPromptBehaviorAdmin
        $secureDesktop = (Get-ItemProperty -Path $uacKey -Name PromptOnSecureDesktop -ErrorAction SilentlyContinue).PromptOnSecureDesktop
        
        if ($consentPrompt -eq 0 -and $secureDesktop -eq 0) {
            $output.UACLevel = "Never notify"
        } elseif ($consentPrompt -eq 5 -and $secureDesktop -eq 0) {
            $output.UACLevel = "Notify without dimming desktop"
        } elseif ($consentPrompt -eq 5 -and $secureDesktop -eq 1) {
            $output.UACLevel = "Default (Notify with secure desktop)"
        } elseif ($consentPrompt -eq 2 -and $secureDesktop -eq 1) {
            $output.UACLevel = "Always notify"
        } else {
            $output.UACLevel = "Unknown configuration"
        }
    } catch {
        $output.UACLevel = "Unable to determine"
    }

    # RDP
    try {
        $rdpEnabled = (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections).fDenyTSConnections
        $output.RDPEnabled = if ($rdpEnabled -eq 0) { "Enabled" } else { "Disabled" }
    } catch {
        $output.RDPEnabled = "Unable to determine"
    }

    # LSASS
    try {
        $lsass = Get-Process -Name lsass -ErrorAction SilentlyContinue
        $output.LSSAProtected = if ($lsass.ProtectedProcess) { "Protected" } else { "Not Protected" }
    } catch {
        $output.LSSAProtected = "Unable to determine"
    }

    # Video Card
    try {
        $videoCard = Get-CimInstance Win32_VideoController | Select-Object -First 1
        $output.VideoCard = [PSCustomObject]@{
            Name = $videoCard.Name
            VideoProcessor = $videoCard.VideoProcessor
            DriverVersion = $videoCard.DriverVersion
            CurrentResolution = "$($videoCard.CurrentHorizontalResolution)x$($videoCard.CurrentVerticalResolution)"
        }
    } catch {
        $output.VideoCardError = $_.Exception.Message
    }

    return $output
}

function Export-SystemInfoReport {
    param(
        [string]$OutputPath,
        [hashtable]$Data
    )

    $report = @"
====================================================================================================
SYSTEM INFORMATION REPORT
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
====================================================================================================

COMPUTER INFORMATION
----------------------------------------------------------------------------------------------------
Computer Name:          $($Data.ComputerName)
Manufacturer:           $($Data.Manufacturer)
Model:                  $($Data.Model)
Domain:                 $($Data.Domain)
Serial Number:          $($Data.SerialNumber)

OPERATING SYSTEM
----------------------------------------------------------------------------------------------------
OS:                     $($Data.OSCaption)
Version:                $($Data.OSVersion)
Architecture:           $($Data.OSArchitecture)
Install Date:           $($Data.InstallDate)
Last Boot:              $($Data.LastBootUpTime)

PROCESSOR
----------------------------------------------------------------------------------------------------
CPU:                    $($Data.CPUName)
Manufacturer:           $($Data.CPUManufacturer)
Cores:                  $($Data.CPUCores)
Logical Processors:     $($Data.CPULogicalProcessors)
Max Clock Speed:        $($Data.CPUMaxClockSpeed)

MEMORY
----------------------------------------------------------------------------------------------------
Total Physical Memory:  $($Data.TotalPhysicalMemory)

RAM Modules:
$($Data.RAMModules | Format-Table -AutoSize | Out-String)

NETWORK
----------------------------------------------------------------------------------------------------
Public IP:              $($Data.PublicIP)

Network Adapters:
$($Data.NetworkAdapters | Format-Table -AutoSize | Out-String)

SECURITY CONFIGURATION
----------------------------------------------------------------------------------------------------
UAC Level:              $($Data.UACLevel)
RDP Status:             $($Data.RDPEnabled)
LSASS Protection:       $($Data.LSSAProtected)

VIDEO
----------------------------------------------------------------------------------------------------
$($Data.VideoCard | Format-List | Out-String)

====================================================================================================
"@

    $report | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Output "System info exported to: $OutputPath"
}