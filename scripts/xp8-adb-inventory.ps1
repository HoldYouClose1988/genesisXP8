<#
.SYNOPSIS
  Collect Sonim XP8 device inventory over adb (and optionally fastboot).

.DESCRIPTION
  Gathers build, carrier, unlock-related props, slots, root indicators, and
  (optional) fastboot unlock state. Writes a timestamped report next to the script
  (or under -OutDir) and prints the path when done.

.PARAMETER OutDir
  Directory for the report. Default: same folder as this script.

.PARAMETER ToolsDir
  Folder containing both adb.exe and fastboot.exe. If omitted, search order is:
  1) this script's folder, 2) directory of adb found on PATH.
  adb and fastboot are always resolved as a pair from the same folder.

.PARAMETER SkipFastboot
  Do not reboot into fastboot. Use when you only want adb props.

.PARAMETER FastbootTimeoutSec
  Seconds to wait for a fastboot device after reboot. Default: 90.

.EXAMPLE
  .\xp8-adb-inventory.ps1

.EXAMPLE
  .\xp8-adb-inventory.ps1 -ToolsDir C:\platform-tools

.EXAMPLE
  .\xp8-adb-inventory.ps1 -SkipFastboot

.NOTES
  Requires adb.exe; fastboot.exe is expected beside it in the same folder.
  Test phone / throwaway units only if you allow the reboot path.
#>
[CmdletBinding()]
param(
    [string]$OutDir = "",
    [string]$ToolsDir = "",
    [switch]$SkipFastboot,
    [int]$FastbootTimeoutSec = 90
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

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & $script:AdbExe @Args 2>&1 | ForEach-Object { "$_" }
}

function Invoke-Fastboot {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & $script:FastbootExe @Args 2>&1 | ForEach-Object { "$_" }
}

function Get-Prop {
    param([string]$Name)
    $raw = (Invoke-Adb shell getprop $Name) -join "`n"
    return ($raw -replace "`r", "").Trim()
}

function Wait-AdbDevice {
    param([int]$TimeoutSec = 120)
    Write-Host "Waiting for adb device (up to ${TimeoutSec}s)..."
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $state = (Invoke-Adb get-state) -join ""
        if ($state -match "device") { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Wait-FastbootDevice {
    param([int]$TimeoutSec = 90)
    Write-Host "Waiting for fastboot device (up to ${TimeoutSec}s)..."
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $devs = (Invoke-Fastboot devices) -join "`n"
        if ($devs -match "\s+fastboot") { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
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

# --- Preconditions -----------------------------------------------------------

$resolvedToolsDir = Resolve-PlatformTools -PreferredDir $ToolsDir
if (-not $script:AdbExe) {
    Write-Error "adb.exe not found. Pass -ToolsDir to the platform-tools folder (adb + fastboot together), or put this script beside them / add that folder to PATH."
    exit 1
}

if (-not $SkipFastboot -and -not $script:FastbootExe) {
    Write-Warning "fastboot.exe missing next to adb ($resolvedToolsDir); continuing with adb-only. Use -SkipFastboot to silence this."
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
$reportPath = Join-Path $OutDir "xp8-inventory-$stamp.txt"
$sb = New-Object System.Text.StringBuilder

[void]$sb.AppendLine("Sonim XP8 inventory")
[void]$sb.AppendLine("Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')")
[void]$sb.AppendLine("Host: (omitted)")
[void]$sb.AppendLine("ToolsDir: $resolvedToolsDir")
[void]$sb.AppendLine("adb: $script:AdbExe")
[void]$sb.AppendLine("fastboot: $script:FastbootExe")
[void]$sb.AppendLine("SkipFastboot: $SkipFastboot")

# --- adb device presence -----------------------------------------------------

Write-Host "Checking adb..."
$devices = (Invoke-Adb devices -l) -join "`n"
Add-Section $sb "adb devices -l" $devices

if ($devices -notmatch "\sdevice\b") {
    Write-Error "No authorized adb device in 'device' state. Unlock phone, accept RSA prompt, retry."
    $sb.ToString() | Set-Content -Path $reportPath -Encoding UTF8
    Write-Host "Partial report: $reportPath"
    exit 2
}

if (-not (Wait-AdbDevice -TimeoutSec 30)) {
    Write-Error "adb device not ready."
    exit 2
}

# --- Core identity props -----------------------------------------------------

Write-Host "Collecting getprop / settings..."

$propNames = @(
    "ro.product.model",
    "ro.product.device",
    "ro.product.name",
    "ro.product.manufacturer",
    "ro.product.brand",
    "ro.build.product",
    "ro.build.display.id",
    "ro.build.description",
    "ro.build.fingerprint",
    "ro.build.id",
    "ro.build.version.release",
    "ro.build.version.sdk",
    "ro.build.version.security_patch",
    "ro.build.version.incremental",
    "ro.build.type",
    "ro.build.tags",
    "ro.build.user",
    "ro.build.host",
    "ro.build.flavor",
    "ro.build.version.codename",
    "ro.serialno",
    "ro.boot.serialno",
    "ro.boot.slot_suffix",
    "ro.boot.verifiedbootstate",
    "ro.boot.flash.locked",
    "ro.boot.vbmeta.device_state",
    "ro.boot.veritymode",
    "ro.bootmode",
    "ro.hardware",
    "ro.board.platform",
    "ro.baseband",
    "gsm.version.baseband",
    "gsm.sim.operator.alpha",
    "gsm.sim.operator.numeric",
    "gsm.operator.alpha",
    "gsm.operator.numeric",
    "ro.carrier",
    "ro.boot.carrier",
    "ro.boot.hardware.sku",
    "ro.boot.product.hardware.sku",
    "ro.vendor.build.fingerprint",
    "ro.system.build.fingerprint",
    "ro.oem_unlock_supported",
    "sys.oem_unlock_allowed",
    "ro.secure",
    "ro.debuggable",
    "ro.adb.secure",
    "service.adb.root",
    "persist.sys.usb.config",
    "ro.crypto.state",
    "ro.boot.dynamic_partitions"
)

$propLines = New-Object System.Collections.Generic.List[string]
foreach ($p in $propNames) {
    $v = Get-Prop $p
    $propLines.Add("${p}=${v}")
}
Add-Section $sb "Key getprop values" ($propLines -join "`n")

# Full getprop dump (large but useful for SKU / Sonim-specific keys)
Write-Host "Dumping full getprop..."
$allProps = (Invoke-Adb shell getprop) -join "`n"
Add-Section $sb "Full getprop" $allProps

# Filter Sonim / carrier-ish keys for a quick skim
$interesting = ($allProps -split "`n" | Where-Object {
    $_ -match "(?i)sonim|xp8|carrier|sku|oem|unlock|verity|vbmeta|att|verizon|telus|baseband|radio|imei|ril|abl|xbl|magisk|kernel"
}) -join "`n"
Add-Section $sb "Filtered props (carrier/unlock/radio/sku)" $interesting

# --- Settings / unlock toggle ------------------------------------------------

$oemSetting = (Invoke-Adb shell settings get global oem_unlock_allowed) -join "`n"
$devSettings = (Invoke-Adb shell settings list global) -join "`n"
$devFiltered = ($devSettings -split "`n" | Where-Object {
    $_ -match "(?i)oem|unlock|adb|development|verifier|boot"
}) -join "`n"
Add-Section $sb "settings get global oem_unlock_allowed" $oemSetting
Add-Section $sb "Filtered global settings" $devFiltered

# --- Root / Magisk indicators ------------------------------------------------

Write-Host "Checking root / Magisk..."
$rootBits = New-Object System.Text.StringBuilder
[void]$rootBits.AppendLine("--- id ---")
[void]$rootBits.AppendLine(((Invoke-Adb shell id) -join "`n"))
[void]$rootBits.AppendLine("--- which su ---")
[void]$rootBits.AppendLine(((Invoke-Adb shell which su) -join "`n"))
[void]$rootBits.AppendLine("--- su -c id (may fail) ---")
[void]$rootBits.AppendLine(((Invoke-Adb shell su -c id) -join "`n"))
[void]$rootBits.AppendLine("--- magisk -v / magisk --path ---")
[void]$rootBits.AppendLine(((Invoke-Adb shell magisk -v) -join "`n"))
[void]$rootBits.AppendLine(((Invoke-Adb shell magisk --path) -join "`n"))
[void]$rootBits.AppendLine("--- ls /data/adb ---")
[void]$rootBits.AppendLine(((Invoke-Adb shell ls -la /data/adb) -join "`n"))
[void]$rootBits.AppendLine("--- getprop | grep -i magisk ---")
[void]$rootBits.AppendLine((($allProps -split "`n" | Where-Object { $_ -match "(?i)magisk" }) -join "`n"))
Add-Section $sb "Root / Magisk indicators" $rootBits.ToString()

# --- Slots / partitions (best-effort from adb) -------------------------------

Write-Host "Collecting slot / bootctl / partitions..."
$slotBits = New-Object System.Text.StringBuilder
[void]$slotBits.AppendLine("--- bootctl get-current-slot / get-number-slots ---")
[void]$slotBits.AppendLine(((Invoke-Adb shell bootctl get-current-slot) -join "`n"))
[void]$slotBits.AppendLine(((Invoke-Adb shell bootctl get-number-slots) -join "`n"))
[void]$slotBits.AppendLine("--- getprop ro.boot.slot_suffix ---")
[void]$slotBits.AppendLine((Get-Prop "ro.boot.slot_suffix"))
[void]$slotBits.AppendLine("--- ls -l /dev/block/bootdevice/by-name (head) ---")
[void]$slotBits.AppendLine(((Invoke-Adb shell ls -l /dev/block/bootdevice/by-name) -join "`n"))
[void]$slotBits.AppendLine("--- cat /proc/version ---")
[void]$slotBits.AppendLine(((Invoke-Adb shell cat /proc/version) -join "`n"))
[void]$slotBits.AppendLine("--- uname -a ---")
[void]$slotBits.AppendLine(((Invoke-Adb shell uname -a) -join "`n"))
Add-Section $sb "Slots / kernel / by-name" $slotBits.ToString()

# --- Telephony / IMEI health (baseband already known dead is fine) -----------

Write-Host "Collecting telephony / IMEI (may be empty if baseband dead)..."
$radioBits = New-Object System.Text.StringBuilder
[void]$radioBits.AppendLine("--- service call / getprop radio ---")
[void]$radioBits.AppendLine("gsm.version.baseband=$(Get-Prop 'gsm.version.baseband')")
[void]$radioBits.AppendLine("ro.baseband=$(Get-Prop 'ro.baseband')")
[void]$radioBits.AppendLine("--- dumpsys iphonesubinfo (may need root) ---")
[void]$radioBits.AppendLine(((Invoke-Adb shell dumpsys iphonesubinfo) -join "`n"))
[void]$radioBits.AppendLine("--- getprop | grep -iE 'imei|ril|radio|baseband|gsm' ---")
[void]$radioBits.AppendLine((($allProps -split "`n" | Where-Object {
    $_ -match "(?i)imei|ril\.|radio|baseband|gsm\.|CDMA|lte"
}) -join "`n"))
Add-Section $sb "Radio / IMEI props" $radioBits.ToString()

# --- Optional: packages that hint at tooling ---------------------------------

Write-Host "Listing Magisk / unlock-related packages..."
$pkgs = (Invoke-Adb shell pm list packages) -join "`n"
$pkgFiltered = ($pkgs -split "`n" | Where-Object {
    $_ -match "(?i)magisk|superuser|unlock|sonim|qualcomm|qti|edl|twrp"
}) -join "`n"
Add-Section $sb "Filtered packages" $pkgFiltered

# --- Fastboot (optional reboot) ----------------------------------------------

if (-not $SkipFastboot) {
    Write-Host ""
    Write-Host "Rebooting to fastboot for unlock vars (Ctrl+C within 5s to abort)..."
    Start-Sleep -Seconds 5

    Invoke-Adb reboot bootloader | Out-Null
    if (-not (Wait-FastbootDevice -TimeoutSec $FastbootTimeoutSec)) {
        Add-Section $sb "fastboot" "TIMEOUT: no fastboot device within ${FastbootTimeoutSec}s"
        Write-Warning "Fastboot timeout. Phone may still be in bootloader — recover manually (hold power) or: fastboot reboot"
    } else {
        Write-Host "Collecting fastboot vars..."
        $fb = New-Object System.Text.StringBuilder
        [void]$fb.AppendLine("--- fastboot devices ---")
        [void]$fb.AppendLine(((Invoke-Fastboot devices) -join "`n"))
        [void]$fb.AppendLine("--- fastboot getvar all ---")
        # getvar all prints to stderr on many platform-tools builds
        [void]$fb.AppendLine(((Invoke-Fastboot getvar all) -join "`n"))
        [void]$fb.AppendLine("--- fastboot oem device-info ---")
        [void]$fb.AppendLine(((Invoke-Fastboot oem device-info) -join "`n"))
        [void]$fb.AppendLine("--- fastboot getvar unlocked ---")
        [void]$fb.AppendLine(((Invoke-Fastboot getvar unlocked) -join "`n"))
        [void]$fb.AppendLine("--- fastboot getvar secure ---")
        [void]$fb.AppendLine(((Invoke-Fastboot getvar secure) -join "`n"))
        [void]$fb.AppendLine("--- fastboot getvar current-slot ---")
        [void]$fb.AppendLine(((Invoke-Fastboot getvar current-slot) -join "`n"))
        [void]$fb.AppendLine("--- fastboot getvar version-bootloader ---")
        [void]$fb.AppendLine(((Invoke-Fastboot getvar version-bootloader) -join "`n"))
        Add-Section $sb "fastboot unlock / slot vars" $fb.ToString()

        Write-Host "Rebooting back to Android..."
        Invoke-Fastboot reboot | Out-Null
        if (Wait-AdbDevice -TimeoutSec 180) {
            Add-Section $sb "post-fastboot adb" "device back online"
        } else {
            Add-Section $sb "post-fastboot adb" "WARNING: adb did not return within 180s"
            Write-Warning "Phone did not come back to adb. Power-cycle if needed."
        }
    }
} else {
    Add-Section $sb "fastboot" "Skipped (-SkipFastboot or fastboot missing)"
}

# --- Summary cheat sheet -----------------------------------------------------

$summary = @"
model=$(Get-Prop 'ro.product.model')
device=$(Get-Prop 'ro.product.device')
fingerprint=$(Get-Prop 'ro.build.fingerprint')
display.id=$(Get-Prop 'ro.build.display.id')
release=$(Get-Prop 'ro.build.version.release')
build.type=$(Get-Prop 'ro.build.type')
build.tags=$(Get-Prop 'ro.build.tags')
slot_suffix=$(Get-Prop 'ro.boot.slot_suffix')
verifiedbootstate=$(Get-Prop 'ro.boot.verifiedbootstate')
flash.locked=$(Get-Prop 'ro.boot.flash.locked')
oem_unlock_supported=$(Get-Prop 'ro.oem_unlock_supported')
oem_unlock_allowed(setting)=$($oemSetting.Trim())
debuggable=$(Get-Prop 'ro.debuggable')
baseband=$(Get-Prop 'gsm.version.baseband')
"@
Add-Section $sb "SUMMARY (quick)" $summary

$sb.ToString() | Set-Content -Path $reportPath -Encoding UTF8

Write-Host ""
Write-Host "Done."
Write-Host "Report: $reportPath"
Write-Host ""
Write-Host "Review the SUMMARY section before sharing; it may contain device identifiers."
