#Requires -RunAsAdministrator
# ==============================================================================
#   _    _                       __      __  _____           _        _ _
#  | |  | |                      \ \    / / |_   _|         | |      | | |
#  | |__| |_   _ _ __   ___ _ __ \ \  / /    | |  _ __  ___| |_ __ _| | | ___ _ __
#  |  __  | | | | '_ \ / _ \ '__| \ \/ /     | | | '_ \/ __| __/ _` | | |/ _ \ '__|
#  | |  | | |_| | |_) |  __/ |     \  /     _| |_| | | \__ \ || (_| | | |  __/ |
#  |_|  |_|\__, | .__/ \___|_|      \/     |_____|_| |_|___/\__\__,_|_|_|\___|_|
#            __/ | |
#           |___/|_|
#
#   Hyper-V Enabler for Windows Home Edition
#   Developer : Vignesh Vijay K
#   GitHub    : https://github.com/VigneshVijayK
#   Version   : 2.0.0
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"      # Fail loud; each call site suppresses locally

# ── Constants ──────────────────────────────────────────────────────────────────
$SCRIPT_VERSION = "2.0.0"
$SCRIPT_AUTHOR  = "Vignesh Vijay K"
$SCRIPT_GITHUB  = "https://github.com/VigneshVijayK"
$LOG_PATH       = "$env:TEMP\HyperV-Installer.log"
$DISM_EXE       = "$env:SystemRoot\System32\dism.exe"

# ── Logging ────────────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts  [$Level]  $Message" | Out-File -FilePath $LOG_PATH -Append -Encoding UTF8
}

# ── Console Helpers ────────────────────────────────────────────────────────────
function Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║        HYPER-V ENABLER FOR WINDOWS HOME EDITION             ║" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "  ║  Developer  : $SCRIPT_AUTHOR                               ║" -ForegroundColor DarkCyan
    Write-Host "  ║  GitHub     : $SCRIPT_GITHUB             ║" -ForegroundColor DarkCyan
    Write-Host "  ║  Version    : $SCRIPT_VERSION                                         ║" -ForegroundColor DarkCyan
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "  Log: $LOG_PATH" -ForegroundColor DarkGray
    Write-Host ""
}

function Section {
    param([string]$Title)
    # FIX: was (60 - $Title.Length) — crashes/negative on long titles
    $pad = [Math]::Max(0, 58 - $Title.Length)
    Write-Host ""
    Write-Host "  ── $Title " -ForegroundColor Yellow -NoNewline
    Write-Host ("─" * $pad) -ForegroundColor DarkGray
    Write-Log "SECTION" $Title
}

function Write-Ok   { param([string]$m) Write-Host "  [✓] $m" -ForegroundColor Green;   Write-Log "OK"   $m }
function Write-Info { param([string]$m) Write-Host "  [i] $m" -ForegroundColor Cyan;    Write-Log "INFO" $m }
function Write-Warn { param([string]$m) Write-Host "  [!] $m" -ForegroundColor Yellow;  Write-Log "WARN" $m }
function Write-Err  { param([string]$m) Write-Host "  [✗] $m" -ForegroundColor Red;     Write-Log "ERR"  $m }

function Invoke-Prompt {
    param([string]$Message)
    Write-Host "  [?] $Message " -ForegroundColor Magenta -NoNewline
    return (Read-Host)
}

function Invoke-Pause {
    Write-Host ""
    Write-Host "  Press any key to return to menu..." -ForegroundColor DarkGray
    try {
        # FIX: ReadKey throws in non-interactive / piped sessions — fall back to Read-Host
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {
        $null = Read-Host
    }
}

# ── System Information ─────────────────────────────────────────────────────────
function Show-SystemInfo {
    Section "System Information"

    # FIX: Get-WmiObject is deprecated in PowerShell 7+ — use Get-CimInstance
    $os  = Get-CimInstance Win32_OperatingSystem
    # FIX: Select-Object -First 1 prevents array return on multi-CPU systems
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1

    # FIX: TotalVisibleMemorySize is in KILOBYTES.
    #      Old code divided by 1MB (1048576) giving ~0.003 GB.
    #      Correct: KB / 1024 / 1024 = GB
    $ramGB = [Math]::Round($os.TotalVisibleMemorySize / 1024 / 1024, 1)

    Write-Info "OS       : $($os.Caption)"
    Write-Info "Build    : $($os.BuildNumber)"
    Write-Info "Arch     : $env:PROCESSOR_ARCHITECTURE"
    Write-Info "CPU      : $($cpu.Name.Trim())"
    Write-Info "RAM      : ${ramGB} GB"

    # FIX: Cast to [bool] — on multi-CPU, property returns an array; [bool] coerces safely
    $virtEnabled = [bool]($cpu.VirtualizationFirmwareEnabled)
    if ($virtEnabled) {
        Write-Ok "Virtualization is ENABLED in BIOS/UEFI"
    } else {
        Write-Warn "Virtualization may be DISABLED — enable it in BIOS before using Hyper-V"
    }

    # Check if Hyper-V already installed — return $true/$false
    # FIX: store result before accessing .State — direct property access on $null
    #      throws PropertyNotFoundException under Set-StrictMode -Version Latest
    try {
        $hvFeature = Get-WindowsOptionalFeature -Online `
            -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
        if ($hvFeature -and $hvFeature.State -eq "Enabled") {
            Write-Ok "Hyper-V is ALREADY enabled on this machine"
            return $true
        }
    } catch {
        # Non-critical — swallow and continue
    }
    return $false
}

# ── Main Menu ──────────────────────────────────────────────────────────────────
function Show-Menu {
    Banner
    # FIX: $already was captured but never used — now drives menu label
    $alreadyInstalled = Show-SystemInfo

    Section "Options"
    if ($alreadyInstalled) {
        Write-Host "  [1]  Re-enable / Repair Hyper-V                   [INSTALLED]" -ForegroundColor DarkGreen
    } else {
        Write-Host "  [1]  Enable Hyper-V (Force Method for Windows Home)" -ForegroundColor White
    }
    Write-Host "  [2]  Check Hyper-V Status"                             -ForegroundColor White
    Write-Host "  [3]  Download VirtualBox (Free Alternative)"           -ForegroundColor White
    Write-Host "  [4]  How to Enable Virtualization in BIOS"             -ForegroundColor White
    Write-Host "  [5]  About / Developer Info"                           -ForegroundColor White
    Write-Host "  [0]  Exit"                                             -ForegroundColor DarkGray
    Write-Host ""

    return (Invoke-Prompt "Enter your choice")
}

# ── Option 1 – Enable Hyper-V ──────────────────────────────────────────────────
function Enable-HyperV {
    Banner
    Section "Enabling Hyper-V on Windows Home"

    Write-Warn "This method injects Hyper-V packages using DISM."
    Write-Warn "It is UNOFFICIAL on Windows Home — use at your own risk."
    Write-Host ""

    $confirm = Invoke-Prompt "Do you want to continue? (Y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Warn "Aborted by user."
        Invoke-Pause
        return
    }

    # ── Step 1: Scan & Inject packages ────────────────────────────────────────
    Section "Step 1 of 3 — Scanning for Hyper-V Packages"
    Write-Info "Scanning $env:SystemRoot\servicing\Packages ..."

    $packages = @(Get-ChildItem "$env:SystemRoot\servicing\Packages" `
        -Filter "*Hyper-V*.mum" -ErrorAction SilentlyContinue)

    if ($packages.Count -eq 0) {
        Write-Err "No Hyper-V packages found in your Windows image."
        Write-Err "Your edition may not ship the Hyper-V servicing files."
        Write-Warn "Try Option 3 — VirtualBox is a full-featured free alternative."
        Write-Log "ERR" "No Hyper-V .mum packages found under servicing\Packages"
        Invoke-Pause
        return
    }

    Write-Info "Found $($packages.Count) package(s). Injecting — this may take a few minutes..."
    $injected = 0
    $skipped  = 0

    for ($i = 0; $i -lt $packages.Count; $i++) {
        $pkg = $packages[$i]
        $pct = [int](($i / $packages.Count) * 100)
        Write-Progress -Activity "Injecting Hyper-V packages" `
            -Status "$($i + 1) / $($packages.Count)  ($pct%)  —  $($pkg.Name)" `
            -PercentComplete $pct

        # FIX: removed dead $result variable; pipe DISM output directly to log
        & $DISM_EXE /online /norestart /add-package:"`"$($pkg.FullName)`"" 2>&1 |
            Out-File -FilePath $LOG_PATH -Append -Encoding UTF8

        switch ($LASTEXITCODE) {
            0    { $injected++ }          # Success
            2    { $skipped++  }          # Already present — not an error
            3010 { $injected++ }          # Success, reboot pending
            default {
                Write-Warn "Unexpected exit code $LASTEXITCODE for: $($pkg.Name)"
                $skipped++
            }
        }
    }

    Write-Progress -Activity "Injecting Hyper-V packages" -Completed
    Write-Ok "Injection complete — $injected added, $skipped skipped."

    # ── Step 2: Enable the feature ─────────────────────────────────────────────
    Section "Step 2 of 3 — Enabling Hyper-V Feature"
    Write-Info "Running DISM enable-feature ..."

    # FIX: removed duplicate /ALL flag (old: /All /LimitAccess /ALL)
    & $DISM_EXE /online /enable-feature /featurename:Microsoft-Hyper-V `
        /All /LimitAccess 2>&1 |
        Out-File -FilePath $LOG_PATH -Append -Encoding UTF8

    switch ($LASTEXITCODE) {
        0    { Write-Ok "Hyper-V feature enabled successfully." }
        2    { Write-Ok "Hyper-V feature was already enabled." }
        3010 { Write-Ok "Hyper-V feature enabled — reboot required." }
        default {
            Write-Err "DISM returned exit code $LASTEXITCODE — check log for details."
            Write-Warn "Log: $LOG_PATH"
        }
    }

    # ── Step 3: Management Tools ────────────────────────────────────────────────
    Section "Step 3 of 3 — Enabling Hyper-V Management Tools"
    try {
        # FIX: was Out-Null — errors swallowed silently; now caught and reported
        $toolResult = Enable-WindowsOptionalFeature `
            -Online -FeatureName Microsoft-Hyper-V-Tools-All `
            -All -NoRestart -ErrorAction Stop
        Write-Ok "Management tools enabled (RestartNeeded: $($toolResult.RestartNeeded))."
    } catch {
        Write-Warn "Could not enable management tools: $_"
        Write-Warn "Add later via: Settings → Optional Features → Hyper-V Management Tools"
    }

    # ── Reboot ─────────────────────────────────────────────────────────────────
    Section "Installation Complete"
    Write-Ok "All steps finished. A restart is required to activate Hyper-V."
    Write-Host ""
    $rb = Invoke-Prompt "Restart now? (Y/N)"
    if ($rb -match '^[Yy]$') {
        Write-Info "Restarting in 5 seconds  (Ctrl+C to cancel) ..."
        Start-Sleep 5
        Restart-Computer -Force
    } else {
        Write-Warn "Please restart manually before launching Hyper-V Manager."
        Invoke-Pause
    }
}

# ── Option 2 – Status Check ────────────────────────────────────────────────────
function Show-HyperVStatus {
    Banner
    Section "Hyper-V Feature Status"

    $features = [ordered]@{
        "Microsoft-Hyper-V-All"                = "Top-level bundle"
        "Microsoft-Hyper-V"                    = "Core hypervisor"
        "Microsoft-Hyper-V-Tools-All"          = "Management tools"
        "Microsoft-Hyper-V-Management-Clients" = "MMC snap-in"
        "Microsoft-Hyper-V-Hypervisor"         = "Hypervisor kernel"
    }

    foreach ($name in $features.Keys) {
        try {
            $feat  = Get-WindowsOptionalFeature -Online -FeatureName $name -ErrorAction Stop
            $label = $features[$name]
            if ($feat.State -eq "Enabled") {
                Write-Ok   "$name  ($label)"
            } else {
                Write-Warn "$name  ($label)  :  $($feat.State)"
            }
        } catch {
            Write-Err "$name : Not found in this Windows image"
        }
    }

    Section "Hyper-V Service  (vmms)"
    try {
        $svc = Get-Service -Name vmms -ErrorAction Stop
        if ($svc.Status -eq "Running") {
            Write-Ok "Hyper-V Virtual Machine Management : Running"
        } else {
            Write-Warn "Hyper-V Virtual Machine Management : $($svc.Status)"
        }
    } catch {
        Write-Err "vmms service not found — Hyper-V is not installed."
    }

    Invoke-Pause
}

# ── Option 3 – VirtualBox ─────────────────────────────────────────────────────
function Open-VirtualBoxPage {
    Banner
    Section "VirtualBox — Free Alternative to Hyper-V"
    Write-Info "VirtualBox is a free, open-source Type-2 hypervisor by Oracle."
    Write-Info "Supports Windows, Linux, and macOS guest VMs."
    Write-Info "Works on ALL Windows editions including Home — no workarounds needed."
    Write-Host ""
    Write-Info "Opening: https://www.virtualbox.org/wiki/Downloads"
    try {
        Start-Process "https://www.virtualbox.org/wiki/Downloads" -ErrorAction Stop
        Write-Ok "Browser launched successfully."
    } catch {
        Write-Warn "Could not open browser automatically."
        Write-Info "Manually visit: https://www.virtualbox.org/wiki/Downloads"
    }
    Invoke-Pause
}

# ── Option 4 – BIOS Guide ─────────────────────────────────────────────────────
function Show-BiosGuide {
    Banner
    Section "Enabling Virtualization in BIOS / UEFI"
    Write-Host ""
    Write-Host "  Hyper-V requires hardware virtualization enabled in BIOS." -ForegroundColor White
    Write-Host ""
    Write-Host "  ┌─ Steps ──────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
    Write-Host "  │  1. Restart your PC                                          │" -ForegroundColor White
    Write-Host "  │  2. Press your BIOS key immediately after the POST screen    │" -ForegroundColor White
    Write-Host "  │  3. Navigate to:  Advanced  ›  CPU Configuration             │" -ForegroundColor White
    Write-Host "  │  4. Find:  'Intel VT-x'  or  'AMD-V / SVM Mode'             │" -ForegroundColor White
    Write-Host "  │  5. Set to:  ENABLED                                         │" -ForegroundColor White
    Write-Host "  │  6. Save & Exit (usually F10)                                │" -ForegroundColor White
    Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  ┌─ BIOS Entry Keys by Manufacturer ───────────────────────────┐" -ForegroundColor DarkCyan
    Write-Host "  │  Dell        :  F2  or F12                                   │" -ForegroundColor White
    Write-Host "  │  HP          :  F10 or Esc                                   │" -ForegroundColor White
    Write-Host "  │  Lenovo      :  F1  or F2  or Fn+F2                          │" -ForegroundColor White
    Write-Host "  │  ASUS        :  F2  or Del                                   │" -ForegroundColor White
    Write-Host "  │  Acer        :  F2  or Del                                   │" -ForegroundColor White
    Write-Host "  │  MSI         :  Del                                          │" -ForegroundColor White
    Write-Host "  │  Gigabyte    :  Del or F2                                    │" -ForegroundColor White
    Write-Host "  │  Samsung     :  F2                                           │" -ForegroundColor White
    Write-Host "  │  Toshiba     :  F2  or Esc                                   │" -ForegroundColor White
    Write-Host "  └──────────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
    Write-Host ""
    Invoke-Pause
}

# ── Option 5 – About ───────────────────────────────────────────────────────────
function Show-About {
    Banner
    Section "About This Script"
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "  ║                  DEVELOPER INFORMATION                      ║" -ForegroundColor Magenta
    Write-Host "  ╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Magenta
    Write-Host "  ║                                                              ║" -ForegroundColor Magenta
    Write-Host "  ║   Name     : $SCRIPT_AUTHOR                                ║" -ForegroundColor White
    Write-Host "  ║   GitHub   : $SCRIPT_GITHUB              ║" -ForegroundColor White
    Write-Host "  ║   Script   : Hyper-V Enabler for Windows Home               ║" -ForegroundColor White
    Write-Host "  ║   Version  : $SCRIPT_VERSION                                          ║" -ForegroundColor White
    Write-Host "  ║   Log File : %TEMP%\HyperV-Installer.log                   ║" -ForegroundColor White
    Write-Host "  ║                                                              ║" -ForegroundColor Magenta
    Write-Host "  ╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Helps Windows Home users enable Hyper-V via DISM package injection." -ForegroundColor Gray
    Write-Host "  Provided as-is for educational purposes. Always backup your system." -ForegroundColor Gray
    Write-Host ""

    try {
        Start-Process $SCRIPT_GITHUB -ErrorAction Stop
        Write-Info "GitHub profile opened in browser."
    } catch {
        Write-Info "Visit: $SCRIPT_GITHUB"
    }
    Invoke-Pause
}

# ── Entry Point ────────────────────────────────────────────────────────────────
# FIX: wrap startup log in try/catch — if $env:TEMP is missing or read-only
#      the old bare Write-Log call crashed before the UI ever rendered
try {
    Write-Log "START" "HyperV-Installer v$SCRIPT_VERSION launched by $env:USERNAME"
} catch {
    # Log unavailable — not fatal; carry on without it
}
$Host.UI.RawUI.WindowTitle = "Hyper-V Installer $SCRIPT_VERSION | by $SCRIPT_AUTHOR"

do {
    $choice = Show-Menu
    switch ($choice.Trim()) {
        "1" { Enable-HyperV       }
        "2" { Show-HyperVStatus   }
        "3" { Open-VirtualBoxPage }
        "4" { Show-BiosGuide      }
        "5" { Show-About          }
        "0" {
            Banner
            Write-Host "  Goodbye! — $SCRIPT_AUTHOR" -ForegroundColor Cyan
            try { Write-Log "EXIT" "User exited cleanly" } catch { }
            Write-Host ""
            Start-Sleep 1
            Exit 0
        }
        default {
            Banner
            Write-Warn "Invalid choice '$($choice.Trim())' — please enter 0 to 5."
            Start-Sleep 1
        }
    }
} while ($true)
