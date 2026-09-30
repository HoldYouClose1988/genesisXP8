<#
.SYNOPSIS
  Prep helper: enter EDL and READ-ONLY dump abl/xbl (+ related) for XP8 unlock work.

.DESCRIPTION
  Documents and optionally runs standard bkerler/edl (or prints QFIL-style templates)
  for a read-only dump of GPT, abl/xbl, devinfo, and vbmeta partitions on Sonim XP8
  (sdm660 eMMC). Default is DUMP ONLY.

  IMPORTANT: Keep this file ASCII-only. Windows PowerShell 5.1 is picky about
  Unicode quotes/dashes and will throw misleading parse errors far below the
  real bad character.

  Manual confirmation is required before any reboot into EDL and before any
  optional write. This script does not invent exploits; it wraps or documents
  normal Firehose partition read/write via bkerler/edl.

  Prefer calling `edl` if found on PATH or beside this script. If missing,
  prints clear manual command templates. Write automation is opt-in and still
  prints templates (or runs only after typed CONFIRM) for user-supplied images.

.PARAMETER OutDir
  Directory for dumps and the text log. Default: dump-YYYYMMDD-HHMMSS under
  this script's folder.

.PARAMETER ToolsDir
  Folder containing adb.exe (and preferably fastboot.exe). Search order:
  1) this value, 2) script folder, 3) directory of adb found on PATH.

.PARAMETER Loader
  Path to Firehose programmer ELF. Default name expected beside script or cwd:
  prog_emmc_ufs_firehose_Sdm660_ddr.elf

.PARAMETER Memory
  edl --memory value. Default: eMMC for XP8.

.PARAMETER SkipEdlReboot
  Do not offer adb reboot edl; assume phone is already in EDL / 9008.

.PARAMETER AllowWrite
  Opt-in write path. Still requires typing CONFIRM. Only documents/flashes
  user-supplied abl/xbl image paths (-AblImage / -XblImage / -XblConfigImage).
  If edl is unavailable, prints command templates only.

.PARAMETER AblImage
  User-supplied Sonim-signed debug abl image (required for write to abl*).

.PARAMETER XblImage
  User-supplied Sonim-signed debug xbl image (optional companion write).

.PARAMETER XblConfigImage
  User-supplied xbl_config image if your package includes one.

.PARAMETER DryRun
  Never invoke edl; only print the command lines that would run.

.EXAMPLE
  .\xp8-edl-abl-prep.ps1

.EXAMPLE
  .\xp8-edl-abl-prep.ps1 -SkipEdlReboot -Loader .\prog_emmc_ufs_firehose_Sdm660_ddr.elf

.EXAMPLE
  .\xp8-edl-abl-prep.ps1 -AllowWrite -AblImage .\debug\abl.elf -XblImage .\debug\xbl.elf

.NOTES
  Test / disposable phone only. Bad abl/xbl writes can hard-brick.
  If Windows blocks the script: Unblock-File .\xp8-edl-abl-prep.ps1
  Manual adb/fastboot examples use .\adb.exe and .\fastboot.exe from the
  platform-tools folder beside your scripts.
#>
[CmdletBinding()]
param(
    [string]$OutDir = "",
    [string]$ToolsDir = "",
    [string]$Loader = "",
    [string]$Memory = "eMMC",
    [switch]$SkipEdlReboot,
    [switch]$AllowWrite,
    [string]$AblImage = "",
    [string]$XblImage = "",
    [string]$XblConfigImage = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

$script:AdbExe = $null
$script:EdlCmd = $null
$script:LogPath = $null
$script:Stamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $Message
    if ($script:LogPath) {
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding ASCII
    }
}

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
        if (Test-Path -LiteralPath $adbPath) {
            $script:AdbExe = (Resolve-Path -LiteralPath $adbPath).Path
            return $dir
        }
    }
    return $null
}

function Resolve-Edl {
    $edlOnPath = Get-Command "edl" -ErrorAction SilentlyContinue
    if ($edlOnPath) {
        $script:EdlCmd = $edlOnPath.Source
        return $script:EdlCmd
    }
    if ($PSScriptRoot) {
        foreach ($name in @("edl.exe", "edl", "edl.py")) {
            $p = Join-Path $PSScriptRoot $name
            if (Test-Path -LiteralPath $p) {
                $script:EdlCmd = (Resolve-Path -LiteralPath $p).Path
                return $script:EdlCmd
            }
        }
    }
    $script:EdlCmd = $null
    return $null
}

function Resolve-Loader {
    param([string]$Preferred)

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($Preferred)) {
        $candidates.Add($Preferred)
    }
    $defaultName = "prog_emmc_ufs_firehose_Sdm660_ddr.elf"
    if ($PSScriptRoot) {
        $candidates.Add((Join-Path $PSScriptRoot $defaultName))
    }
    $candidates.Add((Join-Path (Get-Location).Path $defaultName))

    foreach ($p in $candidates) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p) {
            return (Resolve-Path -LiteralPath $p).Path
        }
    }
    return $null
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )
    & $script:AdbExe @ArgumentList 2>&1 | ForEach-Object { "$_" }
}

function Confirm-Step {
    param(
        [string]$Prompt,
        [string]$Expected = "y"
    )
    Write-Host ""
    Write-Host $Prompt
    $ans = Read-Host "Type '$Expected' to continue (anything else aborts)"
    if ($ans -ne $Expected) {
        Write-Log "User declined confirm (expected '$Expected', got '$ans'). Stopping."
        return $false
    }
    Write-Log "User confirmed: $Expected"
    return $true
}

function Get-EdlBaseArgs {
    param([string]$LoaderPath)
    $args = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($LoaderPath)) {
        $args.Add("--loader=$LoaderPath")
    }
    if (-not [string]::IsNullOrWhiteSpace($Memory)) {
        $args.Add("--memory=$Memory")
    }
    return ,$args.ToArray()
}

function Format-EdlLine {
    param(
        [string]$EdlBinary,
        [string[]]$BaseArgs,
        [string[]]$ActionArgs
    )
    $parts = New-Object System.Collections.Generic.List[string]
    if ($EdlBinary) {
        $parts.Add($EdlBinary)
    } else {
        $parts.Add("edl")
    }
    foreach ($a in $BaseArgs) { $parts.Add($a) }
    foreach ($a in $ActionArgs) { $parts.Add($a) }
    return ($parts -join " ")
}

function Invoke-EdlOrPrint {
    param(
        [string]$Label,
        [string[]]$BaseArgs,
        [string[]]$ActionArgs,
        [switch]$ForcePrintOnly
    )

    $line = Format-EdlLine -EdlBinary $script:EdlCmd -BaseArgs $BaseArgs -ActionArgs $ActionArgs
    Write-Log "CMD: $line"

    if ($DryRun -or $ForcePrintOnly -or -not $script:EdlCmd) {
        if (-not $script:EdlCmd) {
            Write-Log "edl not found; printed manual template only for: $Label"
        } else {
            Write-Log "DryRun/print-only: skipped invoke for: $Label"
        }
        return $true
    }

    Write-Log "Running edl: $Label"
    try {
        $out = & $script:EdlCmd @BaseArgs @ActionArgs 2>&1 | ForEach-Object { "$_" }
        foreach ($o in $out) {
            Write-Log "  $o"
        }
        return $true
    } catch {
        Write-Log ("edl failed for {0}: {1}" -f $Label, $_.Exception.Message)
        return $false
    }
}

function Show-ManualEdlBlock {
    param(
        [string]$LoaderPath,
        [string]$DumpDir
    )

    Write-Host ""
    Write-Host "========================================================================"
    Write-Host "Manual bkerler/edl READ-ONLY dump templates"
    Write-Host "Install: https://github.com/bkerler/edl"
    Write-Host "Phone must already be in EDL (Qualcomm 9008) with a matching Firehose."
    Write-Host "========================================================================"
    Write-Host ""

    $loaderArg = if ($LoaderPath) { "--loader=`"$LoaderPath`"" } else { "--loader=`"prog_emmc_ufs_firehose_Sdm660_ddr.elf`"" }
    $memArg = "--memory=$Memory"
    $base = "edl $loaderArg $memArg"

    Write-Host "# 1) Print GPT (discover exact partition names on this unit)"
    Write-Host "$base printgpt"
    Write-Host ""
    Write-Host "# 2) Dump GPT table binary (optional but useful)"
    Write-Host "$base r gpt `"$DumpDir\gpt.bin`""
    Write-Host ""
    Write-Host "# 3) ABL (A/B names first; if printgpt shows plain 'abl', use that instead)"
    Write-Host "$base r abl_a `"$DumpDir\abl_a.bin`""
    Write-Host "$base r abl_b `"$DumpDir\abl_b.bin`""
    Write-Host "# fallback if single abl:"
    Write-Host "$base r abl `"$DumpDir\abl.bin`""
    Write-Host ""
    Write-Host "# 4) XBL (+ config if present)"
    Write-Host "$base r xbl_a `"$DumpDir\xbl_a.bin`""
    Write-Host "$base r xbl_b `"$DumpDir\xbl_b.bin`""
    Write-Host "$base r xbl_config_a `"$DumpDir\xbl_config_a.bin`""
    Write-Host "$base r xbl_config_b `"$DumpDir\xbl_config_b.bin`""
    Write-Host "# fallbacks:"
    Write-Host "$base r xbl `"$DumpDir\xbl.bin`""
    Write-Host "$base r xbl_config `"$DumpDir\xbl_config.bin`""
    Write-Host ""
    Write-Host "# 5) Policy / AVB related"
    Write-Host "$base r devinfo `"$DumpDir\devinfo.bin`""
    Write-Host "$base r vbmeta_a `"$DumpDir\vbmeta_a.bin`""
    Write-Host "$base r vbmeta_b `"$DumpDir\vbmeta_b.bin`""
    Write-Host "$base r vbmeta_system_a `"$DumpDir\vbmeta_system_a.bin`""
    Write-Host "$base r vbmeta_system_b `"$DumpDir\vbmeta_system_b.bin`""
    Write-Host ""
    Write-Host "# QFIL-style note: same partitions via Partition Manager Read Data;"
    Write-Host "# use the same Firehose ELF and save raw dumps with matching names."
    Write-Host ""
}

function Show-ManualWriteBlock {
    param(
        [string]$LoaderPath,
        [string]$AblPath,
        [string]$XblPath,
        [string]$XblConfigPath
    )

    Write-Host ""
    Write-Host "========================================================================"
    Write-Host "WRITE templates (USER-SUPPLIED Sonim-signed debug images only)"
    Write-Host "DANGER: wrong images can hard-brick. Dump first. Test phone only."
    Write-Host "========================================================================"
    Write-Host ""

    $loaderArg = if ($LoaderPath) { "--loader=`"$LoaderPath`"" } else { "--loader=`"prog_emmc_ufs_firehose_Sdm660_ddr.elf`"" }
    $memArg = "--memory=$Memory"
    $base = "edl $loaderArg $memArg"

    if (-not [string]::IsNullOrWhiteSpace($AblPath)) {
        Write-Host "# ABL writes (match names from printgpt: abl_a/abl_b or abl)"
        Write-Host "$base w abl_a `"$AblPath`""
        Write-Host "$base w abl_b `"$AblPath`""
        Write-Host "# fallback: $base w abl `"$AblPath`""
        Write-Host ""
    } else {
        Write-Host "# Pass -AblImage path\to\sonim-signed-debug-abl to fill write templates."
        Write-Host ""
    }

    if (-not [string]::IsNullOrWhiteSpace($XblPath)) {
        Write-Host "# XBL writes"
        Write-Host "$base w xbl_a `"$XblPath`""
        Write-Host "$base w xbl_b `"$XblPath`""
        Write-Host "# fallback: $base w xbl `"$XblPath`""
        Write-Host ""
    }

    if (-not [string]::IsNullOrWhiteSpace($XblConfigPath)) {
        Write-Host "# XBL_CONFIG writes (only if your package includes it)"
        Write-Host "$base w xbl_config_a `"$XblConfigPath`""
        Write-Host "$base w xbl_config_b `"$XblConfigPath`""
        Write-Host "# fallback: $base w xbl_config `"$XblConfigPath`""
        Write-Host ""
    }

    Write-Host "# After successful write, leave EDL with a long-press power or:"
    Write-Host "#   (from platform-tools) .\adb.exe wait-for-device"
    Write-Host "# Then bootloader check:"
    Write-Host "#   .\fastboot.exe getvar unlocked"
    Write-Host "#   .\fastboot.exe flashing unlock"
    Write-Host "#   .\fastboot.exe oem unlock"
    Write-Host ""
}

# --- Setup -------------------------------------------------------------------

$resolvedToolsDir = Resolve-PlatformTools -PreferredDir $ToolsDir
$null = Resolve-Edl
$loaderPath = Resolve-Loader -Preferred $Loader

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $baseDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $OutDir = Join-Path $baseDir ("dump-" + $script:Stamp)
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}
$script:LogPath = Join-Path $OutDir ("xp8-edl-abl-prep-" + $script:Stamp + ".log")
Set-Content -LiteralPath $script:LogPath -Value ("xp8-edl-abl-prep log " + $script:Stamp) -Encoding ASCII

Write-Log "OutDir: $OutDir"
Write-Log "Log: $script:LogPath"
if ($resolvedToolsDir) {
    Write-Log "Tools dir: $resolvedToolsDir"
    Write-Log "adb: $script:AdbExe"
} else {
    Write-Log "adb.exe not found beside script/PATH. EDL reboot steps will be documented only."
}
if ($script:EdlCmd) {
    Write-Log "edl: $script:EdlCmd"
} else {
    Write-Log "edl: NOT FOUND (will print manual bkerler/edl templates)"
}
if ($loaderPath) {
    Write-Log "Loader: $loaderPath"
} else {
    Write-Log "Loader ELF not found yet. Place prog_emmc_ufs_firehose_Sdm660_ddr.elf beside the script or pass -Loader."
}
Write-Log "Memory: $Memory"
Write-Log "DryRun: $DryRun"
Write-Log "AllowWrite: $AllowWrite"

Write-Host ""
Write-Host "XP8 EDL abl/xbl prep (READ-ONLY by default)"
Write-Host "Device class: XP8812 / sdm660 eMMC / userdebug path"
Write-Host "No serials logged by this script."
Write-Host ""

# --- Step A: document + optional reboot to EDL -------------------------------

Write-Host "------------------------------------------------------------------------"
Write-Host "STEP A: Enter EDL (manual confirm required)"
Write-Host "------------------------------------------------------------------------"
Write-Host ""
Write-Host "From the folder that contains platform-tools (adb beside this script):"
Write-Host "  1) USB debugging authorized, phone booted to Android if possible"
Write-Host "  2) .\adb.exe devices"
Write-Host "  3) .\adb.exe reboot edl"
Write-Host "  4) Confirm Windows Device Manager shows Qualcomm HS-USB QDLoader 9008"
Write-Host ""
Write-Host "If adb cannot reboot (already soft-bricked / no OS): use the hardware"
Write-Host "EDL key combo / cable method you already use for QFIL on this unit."
Write-Host ""

if (-not $SkipEdlReboot) {
    if (-not (Confirm-Step -Prompt "Ready to run .\adb.exe reboot edl now?" -Expected "y")) {
        Write-Log "Aborted before EDL reboot."
        Write-Host "Re-run with -SkipEdlReboot when the phone is already in 9008."
        exit 1
    }

    if (-not $script:AdbExe) {
        Write-Log "Cannot auto-reboot: adb.exe missing. Run manually: .\adb.exe reboot edl"
        if (-not (Confirm-Step -Prompt "Confirm phone is NOW in EDL/9008 after your manual reboot." -Expected "y")) {
            exit 1
        }
    } else {
        Write-Log "Invoking adb reboot edl"
        $rebootOut = Invoke-Adb -ArgumentList @('reboot', 'edl')
        foreach ($o in $rebootOut) { Write-Log "  $o" }
        Write-Host ""
        Write-Host "Wait for 9008. Do not proceed until Device Manager shows QDLoader 9008."
        if (-not (Confirm-Step -Prompt "Confirm phone is in EDL (Qualcomm 9008) now." -Expected "y")) {
            Write-Log "Aborted: EDL not confirmed."
            exit 1
        }
    }
} else {
    Write-Log "SkipEdlReboot set; assuming device already in EDL."
    if (-not (Confirm-Step -Prompt "Confirm phone is already in EDL/9008." -Expected "y")) {
        exit 1
    }
}

# --- Step B: READ-ONLY dump --------------------------------------------------

Write-Host ""
Write-Host "------------------------------------------------------------------------"
Write-Host "STEP B: READ-ONLY dump (gpt, abl*, xbl*, devinfo, vbmeta*)"
Write-Host "------------------------------------------------------------------------"

if (-not (Confirm-Step -Prompt "Proceed with READ-ONLY partition dump plan?" -Expected "y")) {
    Write-Log "Aborted before dump."
    exit 1
}

$baseArgs = @(Get-EdlBaseArgs -LoaderPath $loaderPath)

# Prefer A/B names; also try single-name fallbacks. Missing partitions are OK.
$readPlan = @(
    @{ Name = "printgpt"; Args = @("printgpt"); Out = $null },
    @{ Name = "gpt"; Args = @("r", "gpt", (Join-Path $OutDir "gpt.bin")); Out = "gpt.bin" },
    @{ Name = "abl_a"; Args = @("r", "abl_a", (Join-Path $OutDir "abl_a.bin")); Out = "abl_a.bin" },
    @{ Name = "abl_b"; Args = @("r", "abl_b", (Join-Path $OutDir "abl_b.bin")); Out = "abl_b.bin" },
    @{ Name = "abl"; Args = @("r", "abl", (Join-Path $OutDir "abl.bin")); Out = "abl.bin" },
    @{ Name = "xbl_a"; Args = @("r", "xbl_a", (Join-Path $OutDir "xbl_a.bin")); Out = "xbl_a.bin" },
    @{ Name = "xbl_b"; Args = @("r", "xbl_b", (Join-Path $OutDir "xbl_b.bin")); Out = "xbl_b.bin" },
    @{ Name = "xbl"; Args = @("r", "xbl", (Join-Path $OutDir "xbl.bin")); Out = "xbl.bin" },
    @{ Name = "xbl_config_a"; Args = @("r", "xbl_config_a", (Join-Path $OutDir "xbl_config_a.bin")); Out = "xbl_config_a.bin" },
    @{ Name = "xbl_config_b"; Args = @("r", "xbl_config_b", (Join-Path $OutDir "xbl_config_b.bin")); Out = "xbl_config_b.bin" },
    @{ Name = "xbl_config"; Args = @("r", "xbl_config", (Join-Path $OutDir "xbl_config.bin")); Out = "xbl_config.bin" },
    @{ Name = "devinfo"; Args = @("r", "devinfo", (Join-Path $OutDir "devinfo.bin")); Out = "devinfo.bin" },
    @{ Name = "vbmeta_a"; Args = @("r", "vbmeta_a", (Join-Path $OutDir "vbmeta_a.bin")); Out = "vbmeta_a.bin" },
    @{ Name = "vbmeta_b"; Args = @("r", "vbmeta_b", (Join-Path $OutDir "vbmeta_b.bin")); Out = "vbmeta_b.bin" },
    @{ Name = "vbmeta_system_a"; Args = @("r", "vbmeta_system_a", (Join-Path $OutDir "vbmeta_system_a.bin")); Out = "vbmeta_system_a.bin" },
    @{ Name = "vbmeta_system_b"; Args = @("r", "vbmeta_system_b", (Join-Path $OutDir "vbmeta_system_b.bin")); Out = "vbmeta_system_b.bin" }
)

if (-not $script:EdlCmd -or $DryRun) {
    Show-ManualEdlBlock -LoaderPath $loaderPath -DumpDir $OutDir
}

foreach ($item in $readPlan) {
    $null = Invoke-EdlOrPrint -Label $item.Name -BaseArgs $baseArgs -ActionArgs $item.Args
}

Write-Log "READ-ONLY dump phase finished (see log + OutDir). Missing partition names may error; that is expected if GPT uses only one naming style."

# --- Step C: optional write (templates / guarded) ----------------------------

if ($AllowWrite) {
    Write-Host ""
    Write-Host "------------------------------------------------------------------------"
    Write-Host "STEP C: OPTIONAL WRITE (-AllowWrite)"
    Write-Host "------------------------------------------------------------------------"
    Write-Host "Only flash Sonim-signed debug abl/xbl from YOUR userdebug package."
    Write-Host "This script will not download or invent images."
    Write-Host ""

    Show-ManualWriteBlock -LoaderPath $loaderPath -AblPath $AblImage -XblPath $XblImage -XblConfigPath $XblConfigImage

    if (-not (Confirm-Step -Prompt "Type CONFIRM to acknowledge write danger and continue with templates/run." -Expected "CONFIRM")) {
        Write-Log "Write phase declined."
    } else {
        # Keep automation conservative: print + optionally run only when edl + images exist.
        # Always re-print exact commands into the log.
        $writeOps = New-Object System.Collections.Generic.List[object]
        if (-not [string]::IsNullOrWhiteSpace($AblImage)) {
            if (-not (Test-Path -LiteralPath $AblImage)) {
                Write-Log "AblImage not found: $AblImage"
            } else {
                $ablResolved = (Resolve-Path -LiteralPath $AblImage).Path
                $writeOps.Add(@{ Label = "w abl_a"; Args = @("w", "abl_a", $ablResolved) })
                $writeOps.Add(@{ Label = "w abl_b"; Args = @("w", "abl_b", $ablResolved) })
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($XblImage)) {
            if (-not (Test-Path -LiteralPath $XblImage)) {
                Write-Log "XblImage not found: $XblImage"
            } else {
                $xblResolved = (Resolve-Path -LiteralPath $XblImage).Path
                $writeOps.Add(@{ Label = "w xbl_a"; Args = @("w", "xbl_a", $xblResolved) })
                $writeOps.Add(@{ Label = "w xbl_b"; Args = @("w", "xbl_b", $xblResolved) })
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($XblConfigImage)) {
            if (-not (Test-Path -LiteralPath $XblConfigImage)) {
                Write-Log "XblConfigImage not found: $XblConfigImage"
            } else {
                $xcResolved = (Resolve-Path -LiteralPath $XblConfigImage).Path
                $writeOps.Add(@{ Label = "w xbl_config_a"; Args = @("w", "xbl_config_a", $xcResolved) })
                $writeOps.Add(@{ Label = "w xbl_config_b"; Args = @("w", "xbl_config_b", $xcResolved) })
            }
        }

        if ($writeOps.Count -eq 0) {
            Write-Log "No usable -AblImage/-XblImage/-XblConfigImage paths; write left as printed templates only."
        } elseif (-not $script:EdlCmd) {
            Write-Log "edl missing: write left as printed templates only (safer without local edl setup)."
        } else {
            Write-Host ""
            Write-Host "edl is available. Default remains TEMPLATE-FIRST to avoid silent bricks."
            Write-Host "Commands for each write were logged above."
            if (Confirm-Step -Prompt "Type RUNWRITE to actually invoke edl write now (second gate)." -Expected "RUNWRITE") {
                foreach ($op in $writeOps) {
                    $null = Invoke-EdlOrPrint -Label $op.Label -BaseArgs $baseArgs -ActionArgs $op.Args
                }
            } else {
                Write-Log "Second gate declined; no write invoked."
            }
        }
    }
} else {
    Write-Host ""
    Write-Log "Write skipped (default). Re-run with -AllowWrite -AblImage <path> [-XblImage <path>] after dumps look good."
}

Write-Host ""
Write-Host "Done. Log saved to:"
Write-Host "  $script:LogPath"
Write-Host "Dumps (if edl ran) under:"
Write-Host "  $OutDir"
Write-Host ""
Write-Host "Tonight checklist (PC):"
Write-Host "  1) Copy this script beside .\adb.exe / .\fastboot.exe and your Firehose ELF"
Write-Host "  2) Run: .\xp8-edl-abl-prep.ps1   (confirm EDL, dump only)"
Write-Host "  3) Verify abl_*/xbl_* files exist and sizes look sane"
Write-Host "  4) Extract Sonim-signed debug abl/xbl from your userdebug package"
Write-Host "  5) Only then: .\xp8-edl-abl-prep.ps1 -AllowWrite -AblImage ... -XblImage ..."
Write-Log "Script finished."
