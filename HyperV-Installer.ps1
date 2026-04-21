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
#   Version   : 2.1.0
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"      # Fail loud; each call site suppresses locally

# ── Constants ──────────────────────────────────────────────────────────────────
$SCRIPT_VERSION = "3.0.0"
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
    Write-Host "  ║        HYPER-V ENABLER FOR WINDOWS HOME EDITION              ║" -ForegroundColor Cyan
    Write-Host "  ╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "  ║  Developer  : $SCRIPT_AUTHOR                                 ║" -ForegroundColor DarkCyan
    Write-Host "  ║  GitHub     : $SCRIPT_GITHUB                                 ║" -ForegroundColor DarkCyan
    Write-Host "  ║  Version    : $SCRIPT_VERSION                                ║" -ForegroundColor DarkCyan
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
    try { Write-Log "SECTION" $Title } catch {}
}

function Write-Ok   { param([string]$m) Write-Host "  [✓] $m" -ForegroundColor Green;   try { Write-Log "OK"   $m } catch {} }
function Write-Info { param([string]$m) Write-Host "  [i] $m" -ForegroundColor Cyan;    try { Write-Log "INFO" $m } catch {} }
function Write-Warn { param([string]$m) Write-Host "  [!] $m" -ForegroundColor Yellow;  try { Write-Log "WARN" $m } catch {} }
function Write-Err  { param([string]$m) Write-Host "  [✗] $m" -ForegroundColor Red;     try { Write-Log "ERR"  $m } catch {} }

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

# ── Spinner — used during long DISM operations ────────────────────────────────
# Uses Start-Job (not raw runspace) so -ArgumentList works reliably and
# $using: scope issues are avoided entirely.
function Invoke-WithSpinner {
    param(
        [ScriptBlock]$Job,
        [object[]]$ArgumentList = @(),
        [string]$Label = "Working"
    )
    $spinChars = @('⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏')
    $idx = 0

    # Start-Job spawns a child PowerShell process; ArgumentList passes params
    # to the script block's param() block — no $using: needed
    $bgJob = Start-Job -ScriptBlock $Job -ArgumentList $ArgumentList

    [Console]::CursorVisible = $false
    while ($bgJob.State -eq 'Running') {
        $spin = $spinChars[$idx % $spinChars.Count]
        Write-Host "`r  [$spin] $Label — please wait, do not close this window..." `
            -ForegroundColor Cyan -NoNewline
        $idx++
        Start-Sleep -Milliseconds 120
    }
    # Drain output/errors into log, clean up job
    $null = Receive-Job -Job $bgJob -Wait -ErrorAction SilentlyContinue
    Remove-Job  -Job $bgJob -Force  -ErrorAction SilentlyContinue
    [Console]::CursorVisible = $true
    Write-Host "`r  [✓] $Label — done.                                              " `
        -ForegroundColor Green
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
    Section "Step 1 of 4 — Scanning for Hyper-V Packages"
    Write-Info "Scanning $env:SystemRoot\servicing\Packages ..."

    $packages = @(Get-ChildItem "$env:SystemRoot\servicing\Packages" `
        -Filter "*Hyper-V*.mum" -ErrorAction SilentlyContinue)

    if ($packages.Count -eq 0) {
        Write-Err "No Hyper-V packages found in your Windows image."
        Write-Err "Your edition may not ship the Hyper-V servicing files."
        Write-Warn "Try Option 3 — VirtualBox is a full-featured free alternative."
        try { Write-Log "ERR" "No Hyper-V .mum packages found under servicing\Packages" } catch {}
        Invoke-Pause
        return
    }

    Write-Info "Found $($packages.Count) package(s). Injecting — this may take a few minutes..."
    $injected = 0
    $skipped  = 0
    $code50   = 0   # track "not injectable online" separately — not a real error

    for ($i = 0; $i -lt $packages.Count; $i++) {
        $pkg = $packages[$i]
        $pct = [int](($i / $packages.Count) * 100)
        Write-Progress -Activity "Injecting Hyper-V packages" `
            -Status "$($i + 1) / $($packages.Count)  ($pct%)  —  $($pkg.Name)" `
            -PercentComplete $pct

        & $DISM_EXE /online /norestart /add-package:"`"$($pkg.FullName)`"" 2>&1 |
            Out-File -FilePath $LOG_PATH -Append -Encoding UTF8

        switch ($LASTEXITCODE) {
            0    { $injected++ }
            2    { $skipped++  }          # Already present — fine
            3010 { $injected++ }          # Success, reboot pending
            50   {
                # Exit 50 = "online-merged" package — cannot be injected manually.
                # This is NORMAL for ~5 packages on Windows 11 22H2+. Not an error.
                $code50++
                $skipped++
            }
            default {
                Write-Warn "Exit code $LASTEXITCODE for: $($pkg.Name)"
                $skipped++
            }
        }
    }

    Write-Progress -Activity "Injecting Hyper-V packages" -Completed
    Write-Ok "Injection complete — $injected added, $skipped skipped."
    if ($code50 -gt 0) {
        Write-Info "$code50 package(s) skipped with code 50 — these are online-merged"
        Write-Info "bundles managed by Windows Update. This is normal and expected."
    }

    # ── Step 2: Enable core Hyper-V feature ───────────────────────────────────
    Section "Step 2 of 4 — Enabling Hyper-V Core Feature"
    Write-Info "This step runs silently and can take 5–15 minutes on HDDs."
    Write-Info "An animated spinner shows it is actively working."
    Write-Host ""

    # Script block uses param() — values injected via -ArgumentList, not $using:
    $step2Job = {
        param([string]$dismExe, [string]$logPath)
        & $dismExe /online /enable-feature /featurename:Microsoft-Hyper-V `
            /All /LimitAccess 2>&1 | Out-File -FilePath $logPath -Append -Encoding UTF8
    }

    Invoke-WithSpinner -Job $step2Job -ArgumentList @($DISM_EXE, $LOG_PATH) `
        -Label "DISM enabling Microsoft-Hyper-V"

    # Read exit code from log (last DISM line contains "The operation completed")
    $logTail = Get-Content $LOG_PATH -Tail 20 -ErrorAction SilentlyContinue
    if ($logTail -match "3010|reboot|restart") {
        Write-Ok "Hyper-V core enabled — reboot will be required."
    } elseif ($logTail -match "0x80070002|not found") {
        Write-Err "DISM could not find feature — packages may be incomplete."
        Write-Warn "Log: $LOG_PATH"
    } else {
        Write-Ok "Hyper-V core feature enable command completed."
    }

    # ── Step 3: Enable all sub-features ───────────────────────────────────────
    Section "Step 3 of 4 — Enabling All Hyper-V Sub-Features"

    # Based on real-world testing: these are ALL the features needed for
    # Hyper-V Manager + VM creation to work correctly on Windows Home.
    $subFeatures = [ordered]@{
        "Microsoft-Hyper-V-All"                = "Complete Hyper-V bundle"
        "Microsoft-Hyper-V-Tools-All"          = "Management tools (Hyper-V Manager)"
        "Microsoft-Hyper-V-Management-Clients" = "MMC snap-in for Hyper-V Manager"
        "Microsoft-Hyper-V-Management-PowerShell" = "Hyper-V PowerShell module"
        "Microsoft-Hyper-V-Services"           = "Hyper-V host services"
        "Microsoft-Hyper-V-Hypervisor"         = "Core hypervisor kernel"
    }

    foreach ($feat in $subFeatures.Keys) {
        $label = $subFeatures[$feat]
        Write-Host "  [~] Enabling: $label" -ForegroundColor DarkCyan -NoNewline

        try {
            $null = Enable-WindowsOptionalFeature -Online -FeatureName $feat `
                -All -NoRestart -ErrorAction Stop
            Write-Host "`r  [✓] Enabled : $label                              " `
                -ForegroundColor Green
            Write-Log "OK" "Enabled $feat"
        } catch {
            # Feature may already be enabled or not present in this image
            $errMsg = $_.Exception.Message
            if ($errMsg -match "already enabled") {
                Write-Host "`r  [✓] Already : $label                          " `
                    -ForegroundColor DarkGreen
            } else {
                Write-Host "`r  [!] Skipped : $label — $errMsg               " `
                    -ForegroundColor Yellow
                try { Write-Log "WARN" "Could not enable $feat : $errMsg" } catch {}
            }
        }
    }

    # ── Step 4: Verify installation ───────────────────────────────────────────
    Section "Step 4 of 4 — Verifying Installation"

    $allGood = $true
    $criticalFeatures = @("Microsoft-Hyper-V", "Microsoft-Hyper-V-Hypervisor")
    foreach ($cf in $criticalFeatures) {
        try {
            $state = (Get-WindowsOptionalFeature -Online -FeatureName $cf `
                -ErrorAction Stop).State
            if ($state -eq "Enabled") {
                Write-Ok "$cf : Enabled"
            } else {
                Write-Warn "$cf : $state  (reboot may be needed to finalise)"
                $allGood = $false
            }
        } catch {
            Write-Warn "$cf : Could not verify — will confirm after reboot"
            $allGood = $false
        }
    }

    if ($allGood) {
        Write-Ok "All critical features verified as Enabled."
    } else {
        Write-Warn "Some features show pending state — this is normal before reboot."
    }

    # ── Reboot ─────────────────────────────────────────────────────────────────
    Section "Installation Complete"
    Write-Ok "All steps finished. Restart is required to activate Hyper-V."
    Write-Info "After reboot: press Win+S and search 'Hyper-V Manager'"
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
