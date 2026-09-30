<#
.SYNOPSIS
  Attempt OEM unlock allowance + fastboot unlock on Sonim XP8.

.DESCRIPTION
  Phase A: try to grant oem_unlock_allowed on a userdebug build (adb root /
  settings / Developer options UI / optional factory reset).
  Phase B: reboot to bootloader and attempt flashing unlock / oem unlock.

  IMPORTANT: Keep this file ASCII-only. Windows PowerShell 5.1 is picky about
  Unicode quotes/dashes and will throw misleading parse errors far below the
  real bad character.

  Pass adb/fastboot args as arrays only, e.g. Invoke-Adb @('shell','getprop','ro.build.type').
  Bare flags like -a must never be loose tokens after a function name.

  This script does NOT include EDL/firehose procedures. If unlock fails, next
  step is separate offline analysis of abl/xbl (not covered here).

.PARAMETER OutDir
  Directory for the report. Default: same folder as this script.

.PARAMETER ToolsDir
  Folder containing both adb.exe and fastboot.exe. If omitted, search order is:
  1) this script's folder, 2) directory of adb found on PATH.
  adb and fastboot are always resolved as a pair from the same folder.

.PARAMETER SkipFastboot
  Stop after Phase A (allowance). Do not reboot to bootloader / unlock.

.EXAMPLE
  .\xp8-oem-unlock-attempt.ps1

.EXAMPLE
  .\xp8-oem-unlock-attempt.ps1 -SkipFastboot

.NOTES
  Requires adb.exe; fastboot.exe is expected beside it in the same folder.
  Test / disposable phone only. Unlock may wipe userdata.
  If Windows blocks the script: Unblock-File .\xp8-oem-unlock-attempt.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir = "",
    [string]$ToolsDir = "",
    [switch]$SkipFastboot
)

$ErrorActionPreference = "Continue"

$script:AdbExe = $null
$script:FastbootExe = $null

function Resolve-PlatformTools {
    param([string]$PreferredDir)

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PreferredDir)) {
        $candidates.Add($PreferredDir)
    }
    if ($PSScriptRoot) { $candidates.Add($PSScriptRoot) }

    $adbOnPath = Get-Command "adb.exe" -ErrorAction SilentlyContinue
    if (-not $adbOnPath) { $adbOnPath = Get-Command "adb" -ErrorAction SilentlyContinue }
    if ($adbOnPath) {
        $candidates.Add((Split-Path -Parent $adbOnPath.Source))
    }

    foreach ($dir in $candidates) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        $adbPath = Join-Path $dir "adb.exe"
        $fbPath = Join-Path $dir "fastboot.exe"
        if (Test-Path -LiteralPath $adbPath) {
            $script:AdbExe = (Resolve-Path -LiteralPath $adbPath).Path
            if (Test-Path -LiteralPath $fbPath) {
                $script:FastbootExe = (Resolve-Path -LiteralPath $fbPath).Path
            } else {
                $script:FastbootExe = $null
            }
            return $dir
        }
    }
    return $null
}

# Always call as: Invoke-Adb @('shell','getprop','ro.build.type')
# Never: Invoke-Adb shell getprop ro.build.type with bare -flags after the name
function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )
    & $script:AdbExe @ArgumentList 2>&1 | ForEach-Object { "$_" }
}

function Invoke-Fastboot {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )
    & $script:FastbootExe @ArgumentList 2>&1 | ForEach-Object { "$_" }
}

function Get-Prop {
    param([string]$Name)
    $raw = (Invoke-Adb -ArgumentList @('shell', 'getprop', $Name)) -join "`n"
    return ($raw -replace "`r", "").Trim()
}

function Get-OemUnlockSetting {
    $raw = (Invoke-Adb -ArgumentList @('shell', 'settings', 'get', 'global', 'oem_unlock_allowed')) -join "`n"
    return ($raw -replace "`r", "").Trim()
}

function Wait-AdbDevice {
    param([int]$TimeoutSec = 120)
    Write-Host "Waiting for adb device (up to ${TimeoutSec}s)..."
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $state = (Invoke-Adb -ArgumentList @('get-state')) -join ""
        if ($state -match "device") { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Test-FastbootPresent {
    $devs = (Invoke-Fastboot -ArgumentList @('devices')) -join "`n"
    return ($devs -match "\s+fastboot")
}

function Add-Section {
    param(
        [System.Text.StringBuilder]$Builder,
        [string]$Title,
        [string]$Body
    )
    [void]$Builder.AppendLine("")
    [void]$Builder.AppendLine(("=" * 72))
    [void]$Builder.AppendLine($Title)
    [void]$Builder.AppendLine(("=" * 72))
    if ([string]::IsNullOrWhiteSpace($Body)) {
        [void]$Builder.AppendLine("(empty)")
    } else {
        [void]$Builder.AppendLine($Body.TrimEnd())
    }
}

function Write-UnlockProps {
    param([System.Text.StringBuilder]$Builder, [string]$Label)

    $lines = New-Object System.Collections.Generic.List[string]
    $names = @(
        "ro.oem_unlock_supported",
        "sys.oem_unlock_allowed",
        "ro.boot.flash.locked",
        "ro.boot.verifiedbootstate",
        "ro.build.type",
        "ro.build.tags"
    )
    foreach ($n in $names) {
        $lines.Add("${n}=$(Get-Prop $n)")
    }
    $setting = Get-OemUnlockSetting
    $lines.Add("settings get global oem_unlock_allowed=$setting")

    $body = $lines -join "`n"
    Write-Host ""
    Write-Host "--- $Label ---"
    Write-Host $body
    Add-Section $Builder $Label $body
    return $setting
}

function Test-OemAllowedGranted {
    param([string]$SettingValue, [string]$SysProp)

    if ($SettingValue -eq "1") { return $true }
    if ($SysProp -eq "1") { return $true }
    return $false
}

# --- Preconditions -----------------------------------------------------------

$resolvedToolsDir = Resolve-PlatformTools -PreferredDir $ToolsDir
if (-not $script:AdbExe) {
    Write-Error "adb.exe not found. Pass -ToolsDir to the platform-tools folder (adb + fastboot together), or put this script beside them / add that folder to PATH."
    exit 1
}

if (-not $SkipFastboot -and -not $script:FastbootExe) {
    Write-Warning "fastboot.exe missing next to adb ($resolvedToolsDir); Phase B disabled. Use -SkipFastboot to silence this."
    $SkipFastboot = $true
}

Write-Host "Tools dir: $resolvedToolsDir"
Write-Host "adb:       $script:AdbExe"
if ($script:FastbootExe) { Write-Host "fastboot:  $script:FastbootExe" }

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    if ($PSScriptRoot) { $OutDir = $PSScriptRoot }
    else { $OutDir = (Get-Location).Path }
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportPath = Join-Path $OutDir "xp8-oem-unlock-$stamp.txt"
$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine("Sonim XP8 OEM unlock attempt")
[void]$sb.AppendLine("Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')")
[void]$sb.AppendLine("ToolsDir: $resolvedToolsDir")
[void]$sb.AppendLine("adb: $script:AdbExe")
[void]$sb.AppendLine("fastboot: $script:FastbootExe")
[void]$sb.AppendLine("SkipFastboot: $SkipFastboot")
[void]$sb.AppendLine("Device class context (inventory): XP8812 AT&T-class, Android 8.1.0 userdebug test-keys")
[void]$sb.AppendLine("WARNING: Unlock can wipe userdata. Disposable/test device assumed.")

# --- adb device presence -----------------------------------------------------

Write-Host "Checking adb..."
$devices = (Invoke-Adb -ArgumentList @('devices', '-l')) -join "`n"
Add-Section $sb "adb devices -l" $devices

if ($devices -notmatch "\sdevice\b") {
    Write-Error "No authorized adb device in 'device' state. Unlock phone, accept RSA prompt, retry."
    $sb.ToString() | Set-Content -Path $reportPath -Encoding ASCII
    Write-Host "Partial report: $reportPath"
    exit 2
}

if (-not (Wait-AdbDevice -TimeoutSec 30)) {
    Write-Error "adb device not ready."
    $sb.ToString() | Set-Content -Path $reportPath -Encoding ASCII
    Write-Host "Partial report: $reportPath"
    exit 2
}

# --- Baseline unlock props ---------------------------------------------------

$oemSetting = Write-UnlockProps -Builder $sb -Label "Baseline unlock-related props"
$sysAllowed = Get-Prop "sys.oem_unlock_allowed"
$oemSupported = Get-Prop "ro.oem_unlock_supported"

Write-Host ""
Write-Host "ro.oem_unlock_supported=$oemSupported (expected true on this class)"
Write-Host "sys.oem_unlock_allowed=$sysAllowed (inventory often shows 0 until toggled)"

# =============================================================================
# Phase A - grant OEM unlock allowance
# =============================================================================

Write-Host ""
Write-Host "========================================================================"
Write-Host "Phase A: grant OEM unlock allowance"
Write-Host "========================================================================"
Add-Section $sb "Phase A" "Attempting to set oem_unlock_allowed=1"

$forceContinue = $false

if (Test-OemAllowedGranted -SettingValue $oemSetting -SysProp $sysAllowed) {
    Write-Host "OEM unlock allowance already looks granted."
    Add-Section $sb "Phase A result" "Already granted (setting=$oemSetting sys=$sysAllowed)"
} else {
    Write-Host "Trying adb root (userdebug / test-keys)..."
    $rootOut = (Invoke-Adb -ArgumentList @('root')) -join "`n"
    Add-Section $sb "adb root" $rootOut
    Start-Sleep -Seconds 2
    if (-not (Wait-AdbDevice -TimeoutSec 60)) {
        Write-Warning "adb not ready after root; continuing anyway."
        Add-Section $sb "adb after root" "device not ready within 60s"
    }

    Write-Host "Trying remount (may fail if not needed)..."
    $remountOut = (Invoke-Adb -ArgumentList @('remount')) -join "`n"
    Add-Section $sb "adb remount" $remountOut

    Write-Host "settings put global oem_unlock_allowed 1 ..."
    $putOut = (Invoke-Adb -ArgumentList @('shell', 'settings', 'put', 'global', 'oem_unlock_allowed', '1')) -join "`n"
    Add-Section $sb "settings put global oem_unlock_allowed 1" $putOut

    $oemSetting = Write-UnlockProps -Builder $sb -Label "After settings put"
    $sysAllowed = Get-Prop "sys.oem_unlock_allowed"

    if (-not (Test-OemAllowedGranted -SettingValue $oemSetting -SysProp $sysAllowed)) {
        Write-Host ""
        Write-Host "Still not granted via settings put."
        Write-Host "On the phone:"
        Write-Host "  1) Open Settings > System > About phone"
        Write-Host "  2) Tap Build number 7 times to enable Developer options"
        Write-Host "  3) Open Settings > System > Developer options"
        Write-Host "  4) Enable OEM unlocking (if the toggle is present and not greyed out)"
        Write-Host "  5) Leave USB debugging on"
        [void](Read-Host "Press Enter after enabling OEM unlocking in the UI (or if it is greyed/missing)")

        if (-not (Wait-AdbDevice -TimeoutSec 60)) {
            Write-Warning "adb not ready after UI step."
        }
        $oemSetting = Write-UnlockProps -Builder $sb -Label "After Developer options UI"
        $sysAllowed = Get-Prop "sys.oem_unlock_allowed"
    }

    if (-not (Test-OemAllowedGranted -SettingValue $oemSetting -SysProp $sysAllowed)) {
        Write-Host ""
        Write-Host "WARNING: oem_unlock_allowed still looks blocked (0 / greyed)."
        Write-Host "Optional factory reset path (WIPES USERDATA on this device):"
        Write-Host "  Prefer Settings > System > Reset options > Erase all data (factory reset)."
        Write-Host "  adb reboot recovery alone is NOT enough to wipe."
        Write-Host "  After the wipe, complete setup, re-enable USB debugging + OEM unlocking,"
        Write-Host "  then return here. Disposable/test phone assumed."
        $doWipe = Read-Host "Did you / will you factory-reset from the UI? Type YES to wait for reset, or press Enter to skip"
        if ($doWipe -eq "YES") {
            Add-Section $sb "Factory reset path" "User chose YES - waiting for post-reset adb"
            Write-Host "Perform the factory reset on the phone now (Settings wipe preferred)."
            Write-Host "After first boot, enable Developer options, USB debugging, and OEM unlocking."
            [void](Read-Host "Press Enter when the phone is back in Android with USB debugging authorized")
            if (-not (Wait-AdbDevice -TimeoutSec 180)) {
                Write-Warning "adb not ready after factory reset wait."
                Add-Section $sb "After factory reset" "adb not ready within 180s"
            } else {
                Write-Host "Re-trying settings put after reset..."
                [void](Invoke-Adb -ArgumentList @('root'))
                Start-Sleep -Seconds 2
                [void](Wait-AdbDevice -TimeoutSec 60)
                $putOut2 = (Invoke-Adb -ArgumentList @('shell', 'settings', 'put', 'global', 'oem_unlock_allowed', '1')) -join "`n"
                Add-Section $sb "settings put after factory reset" $putOut2
                $oemSetting = Write-UnlockProps -Builder $sb -Label "After factory reset path"
                $sysAllowed = Get-Prop "sys.oem_unlock_allowed"
            }
        } else {
            Add-Section $sb "Factory reset path" "Skipped by user"
        }
    }

    if (Test-OemAllowedGranted -SettingValue $oemSetting -SysProp $sysAllowed) {
        Add-Section $sb "Phase A result" "Granted (setting=$oemSetting sys=$sysAllowed)"
        Write-Host "Phase A: OEM unlock allowance looks granted."
    } else {
        Add-Section $sb "Phase A result" "NOT granted (setting=$oemSetting sys=$sysAllowed)"
        Write-Host "Phase A: still not granted."
        $forceAns = Read-Host "Force continue to Phase B (fastboot unlock) anyway? Type YES to force, or Enter to stop"
        if ($forceAns -eq "YES") {
            $forceContinue = $true
            Add-Section $sb "Force continue" "User forced Phase B despite oem_unlock_allowed not granted"
        } else {
            Write-Host "Stopping before fastboot. See next steps at end of report."
            Add-Section $sb "Phase B" "Skipped - allowance not granted and user did not force"
            $SkipFastboot = $true
        }
    }
}

# =============================================================================
# Phase B - fastboot unlock
# =============================================================================

$unlockSucceeded = $false

if (-not $SkipFastboot) {
    $allowedNow = Test-OemAllowedGranted -SettingValue $oemSetting -SysProp $sysAllowed
    if (-not $allowedNow -and -not $forceContinue) {
        Write-Host "Skipping Phase B (allowance not granted)."
        Add-Section $sb "Phase B" "Skipped - allowance not granted"
    } else {
        Write-Host ""
        Write-Host "========================================================================"
        Write-Host "Phase B: fastboot unlock"
        Write-Host "========================================================================"
        Write-Host "This may WIPE userdata if the bootloader accepts unlock."
        Write-Host "If the phone shows a confirm screen, use volume + power to confirm on-device."
        [void](Read-Host "Press Enter to reboot to bootloader (Ctrl+C to abort)")

        Write-Host "Rebooting to bootloader..."
        $rbOut = (Invoke-Adb -ArgumentList @('reboot', 'bootloader')) -join "`n"
        Add-Section $sb "adb reboot bootloader" $rbOut

        Write-Host ""
        Write-Host "On the phone, confirm you see the fastboot / bootloader screen."
        Write-Host "USB should still be plugged in."
        $fbSkipped = $false
        while ($true) {
            [void](Read-Host "When the phone is in fastboot mode, press Enter to continue")
            if (Test-FastbootPresent) {
                Write-Host "fastboot device detected."
                break
            }
            Write-Warning "No fastboot device yet (fastboot devices was empty)."
            $retry = Read-Host "Try again? [Y]es / [S]kip Phase B / [A]bort (default Y)"
            if ($retry -match '^[sS]') {
                Add-Section $sb "fastboot wait" "Skipped by user after reboot (device not seen)"
                $fbSkipped = $true
                break
            }
            if ($retry -match '^[aA]') {
                Add-Section $sb "fastboot wait" "Aborted by user after reboot (device not seen)"
                $sb.ToString() | Set-Content -Path $reportPath -Encoding ASCII
                Write-Host "Partial report: $reportPath"
                exit 3
            }
        }

        if (-not $fbSkipped) {
            $fbLog = New-Object System.Text.StringBuilder

            Write-Host "fastboot getvar unlocked ..."
            $o = (Invoke-Fastboot -ArgumentList @('getvar', 'unlocked')) -join "`n"
            Write-Host $o
            [void]$fbLog.AppendLine("--- fastboot getvar unlocked (before) ---")
            [void]$fbLog.AppendLine($o)

            Write-Host "fastboot getvar all (or key vars) ..."
            $oAll = (Invoke-Fastboot -ArgumentList @('getvar', 'all')) -join "`n"
            Write-Host $oAll
            [void]$fbLog.AppendLine("--- fastboot getvar all ---")
            [void]$fbLog.AppendLine($oAll)

            # Key vars if getvar all was sparse
            foreach ($gv in @('secure', 'current-slot', 'version-bootloader', 'product', 'serialno')) {
                $og = (Invoke-Fastboot -ArgumentList @('getvar', $gv)) -join "`n"
                [void]$fbLog.AppendLine("--- fastboot getvar $gv ---")
                [void]$fbLog.AppendLine($og)
            }

            Write-Host "fastboot flashing get_unlock_ability (may be unsupported) ..."
            $oAbility = (Invoke-Fastboot -ArgumentList @('flashing', 'get_unlock_ability')) -join "`n"
            Write-Host $oAbility
            [void]$fbLog.AppendLine("--- fastboot flashing get_unlock_ability ---")
            [void]$fbLog.AppendLine($oAbility)

            Write-Host ""
            Write-Host "About to run: fastboot flashing unlock"
            Write-Host "If the device shows a wipe/confirm prompt, confirm ON THE PHONE (volume/power)."
            [void](Read-Host "Press Enter to send flashing unlock (Ctrl+C to abort)")

            Write-Host "fastboot flashing unlock ..."
            $oUnlock = (Invoke-Fastboot -ArgumentList @('flashing', 'unlock')) -join "`n"
            Write-Host $oUnlock
            [void]$fbLog.AppendLine("--- fastboot flashing unlock ---")
            [void]$fbLog.AppendLine($oUnlock)

            $unlockCmdFailed = $true
            if ($oUnlock -match "(?i)OKAY|finished|unlocked") {
                $unlockCmdFailed = $false
            }
            if ($oUnlock -match "(?i)FAILED|error|not allowed|unknown command") {
                $unlockCmdFailed = $true
            }

            if ($unlockCmdFailed) {
                Write-Host "flashing unlock did not clearly succeed; trying: fastboot oem unlock"
                Write-Host "Confirm on-device if prompted."
                [void](Read-Host "Press Enter to send oem unlock (Ctrl+C to abort)")
                $oOem = (Invoke-Fastboot -ArgumentList @('oem', 'unlock')) -join "`n"
                Write-Host $oOem
                [void]$fbLog.AppendLine("--- fastboot oem unlock ---")
                [void]$fbLog.AppendLine($oOem)
            } else {
                [void]$fbLog.AppendLine("--- fastboot oem unlock ---")
                [void]$fbLog.AppendLine("(skipped; flashing unlock looked OK)")
            }

            Write-Host "fastboot getvar unlocked (after) ..."
            # Device may have rebooted or left fastboot after unlock; probe carefully
            Start-Sleep -Seconds 2
            if (Test-FastbootPresent) {
                $oAfter = (Invoke-Fastboot -ArgumentList @('getvar', 'unlocked')) -join "`n"
                Write-Host $oAfter
                [void]$fbLog.AppendLine("--- fastboot getvar unlocked (after) ---")
                [void]$fbLog.AppendLine($oAfter)
                if ($oAfter -match "(?i)unlocked:\s*yes") {
                    $unlockSucceeded = $true
                }
            } else {
                [void]$fbLog.AppendLine("--- fastboot getvar unlocked (after) ---")
                [void]$fbLog.AppendLine("(fastboot device not present; may have rebooted after unlock)")
                Write-Host "fastboot device not present after unlock attempt (may have rebooted)."
            }

            Add-Section $sb "Phase B fastboot log" $fbLog.ToString()

            if (Test-FastbootPresent) {
                $rbAns = Read-Host "Reboot back to Android now? [Y]es / [N]o (default Y)"
                if ($rbAns -notmatch '^[nN]') {
                    Write-Host "Rebooting to Android..."
                    $rbFb = (Invoke-Fastboot -ArgumentList @('reboot')) -join "`n"
                    Add-Section $sb "fastboot reboot" $rbFb
                    if (Wait-AdbDevice -TimeoutSec 180) {
                        $oemSetting = Write-UnlockProps -Builder $sb -Label "Post-unlock Android props"
                        Add-Section $sb "post-unlock adb" "device back online"
                    } else {
                        Add-Section $sb "post-unlock adb" "WARNING: adb did not return within 180s"
                        Write-Warning "Phone did not come back to adb. Power-cycle if needed."
                    }
                } else {
                    Add-Section $sb "fastboot reboot" "Skipped by user"
                }
            } else {
                Write-Host "Waiting for Android adb after unlock attempt..."
                if (Wait-AdbDevice -TimeoutSec 180) {
                    $oemSetting = Write-UnlockProps -Builder $sb -Label "Post-unlock Android props"
                    Add-Section $sb "post-unlock adb" "device back online (no fastboot left)"
                } else {
                    Add-Section $sb "post-unlock adb" "WARNING: adb did not return within 180s"
                }
            }
        }
    }
} else {
    Add-Section $sb "Phase B" "Skipped (-SkipFastboot or fastboot missing or user stopped)"
}

# --- Summary / next steps ----------------------------------------------------

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add("oem_unlock_supported=$(Get-Prop 'ro.oem_unlock_supported')")
$summary.Add("sys.oem_unlock_allowed=$(Get-Prop 'sys.oem_unlock_allowed')")
$summary.Add("settings oem_unlock_allowed=$(Get-OemUnlockSetting)")
$summary.Add("flash.locked=$(Get-Prop 'ro.boot.flash.locked')")
$summary.Add("verifiedbootstate=$(Get-Prop 'ro.boot.verifiedbootstate')")
$summary.Add("build.type=$(Get-Prop 'ro.build.type')")
$summary.Add("build.tags=$(Get-Prop 'ro.build.tags')")
$summary.Add("unlockSucceededFlag=$unlockSucceeded")
$summary.Add("forceContinue=$forceContinue")
Add-Section $sb "SUMMARY" ($summary -join "`n")

$next = New-Object System.Text.StringBuilder
[void]$next.AppendLine("If unlocked:yes / flash.locked=0: proceed with custom recovery / Magisk as planned.")
[void]$next.AppendLine("If still locked (unlocked:no, secure:yes, oem_unlock_allowed=0):")
[void]$next.AppendLine("  - Carrier/OEM may hard-block unlock_ability despite userdebug.")
[void]$next.AppendLine("  - Next step (separate workflow): debug abl/xbl via EDL read-only dump")
[void]$next.AppendLine("    of GPT + persist/abl/xbl/boot BEFORE any abl experiments.")
[void]$next.AppendLine("  - Do NOT run firehose write / exploit procedures from this script.")
[void]$next.AppendLine("  - Keep baseband-dead disposable assumptions; expect wipe on any later unlock.")
Add-Section $sb "NEXT STEPS" $next.ToString()

$sb.ToString() | Set-Content -Path $reportPath -Encoding ASCII

Write-Host ""
Write-Host "Done."
Write-Host "Report: $reportPath"
Write-Host ""
if ($unlockSucceeded) {
    Write-Host "Unlock appears successful (getvar unlocked:yes). Verify on device after boot."
} else {
    Write-Host "Unlock not confirmed. If still locked, next step is EDL read-only dump of"
    Write-Host "abl/xbl (separate tooling) -- not covered by this script."
}
Write-Host "Paste the SUMMARY / NEXT STEPS sections back into the Project chat."
