<#
.SYNOPSIS
  Patch a Sonim XP8 devinfo dump so DeviceInfo +0x10 is 1 (unlock-allow candidate).

.DESCRIPTION
  ASCII-only. Reads a QFIL dump of the devinfo partition, writes a sibling
  patched image with little-endian uint32 1 at offset 0x10, and prints a
  short hex check plus QFIL / fastboot follow-up commands.

  This does not talk to the phone and does not flash by itself. Flash the
  output with QFIL Partition Manager onto the devinfo partition only after
  you keep the original dump as a backup.

.PARAMETER Source
  Path to the original devinfo dump (usually 4096 bytes, often all zeros).

.PARAMETER Destination
  Output path. Default: devinfo_plus10.bin next to Source.

.PARAMETER Offset
  Byte offset of the 4-byte flag. Default: 0x10 (Claude DeviceInfo gate).

.PARAMETER Value
  UInt32 value to write (little-endian). Default: 1.

.EXAMPLE
  .\xp8-patch-devinfo.ps1 -Source .\devinfo.bin

.NOTES
  Test phone only. Keep the original dump. Restore it with QFIL if boot fails.
  Manual adb/fastboot examples use .\adb.exe and .\fastboot.exe.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Source,
    [string]$Destination = "",
    [int]$Offset = 0x10,
    [uint32]$Value = 1
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Source)) {
    Write-Error "Source not found: $Source"
    exit 1
}

$srcPath = (Resolve-Path -LiteralPath $Source).Path
if ([string]::IsNullOrWhiteSpace($Destination)) {
    $dir = Split-Path -Parent $srcPath
    $Destination = Join-Path $dir "devinfo_plus10.bin"
}

$bytes = [System.IO.File]::ReadAllBytes($srcPath)
if ($Offset -lt 0 -or ($Offset + 4) -gt $bytes.Length) {
    Write-Error "Offset $Offset is outside the dump (length $($bytes.Length))."
    exit 1
}

$before = [BitConverter]::ToUInt32($bytes, $Offset)
$le = [BitConverter]::GetBytes($Value)
[Array]::Copy($le, 0, $bytes, $Offset, 4)
$after = [BitConverter]::ToUInt32($bytes, $Offset)

[System.IO.File]::WriteAllBytes($Destination, $bytes)

Write-Host "Source:      $srcPath"
Write-Host "Length:      $($bytes.Length) bytes"
Write-Host "Offset:      0x$('{0:X}' -f $Offset)"
Write-Host "Before:      $before"
Write-Host "After:       $after"
Write-Host "Wrote:       $Destination"
Write-Host ""
Write-Host "First 32 bytes of patched file:"

$show = [Math]::Min(32, $bytes.Length)
$line = New-Object System.Text.StringBuilder
for ($i = 0; $i -lt $show; $i++) {
    if (($i % 16) -eq 0) {
        if ($i -gt 0) {
            Write-Host $line.ToString()
            $line.Clear() | Out-Null
        }
        [void]$line.Append(("{0:X4}  " -f $i))
    }
    [void]$line.Append(("{0:X2} " -f $bytes[$i]))
}
if ($line.Length -gt 0) { Write-Host $line.ToString() }

Write-Host ""
Write-Host "Expect 01 00 00 00 starting at offset 0010 when Value is 1."
Write-Host ""
Write-Host "Next (manual):"
Write-Host "1. Keep the original dump. Do not overwrite it."
Write-Host "2. Phone in EDL (9008). QFIL Partition Manager."
Write-Host "3. Write the patched file to partition devinfo only."
Write-Host "4. Exit EDL, boot Android, confirm OEM unlocking is on."
Write-Host "5. From platform-tools:"
Write-Host "   .\adb.exe reboot bootloader"
Write-Host "   .\fastboot.exe devices"
Write-Host "   .\fastboot.exe flashing get_unlock_ability"
Write-Host "   .\fastboot.exe flashing unlock"
Write-Host "   .\fastboot.exe oem unlock"
Write-Host "   .\fastboot.exe getvar unlocked"
Write-Host ""
Write-Host "If the phone will not boot, QFIL-write the original dump back to devinfo."
