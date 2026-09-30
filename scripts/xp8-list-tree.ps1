<#
.SYNOPSIS
  Recursively list all subfolders and files into a text file.

.DESCRIPTION
  ASCII-only. Defaults to the current directory. Writes a sorted path listing
  with file sizes. Useful for sharing firmware / tool folder layouts.

.PARAMETER Root
  Folder to scan. Default: current working directory.

.PARAMETER OutFile
  Output text path. Default: list-tree-YYYYMMDD-HHMMSS.txt in Root.

.PARAMETER FilesOnly
  Omit directory-only lines (still walks the tree for files).

.EXAMPLE
  .\xp8-list-tree.ps1

.EXAMPLE
  .\xp8-list-tree.ps1 -Root D:\xp8-firmware
#>
[CmdletBinding()]
param(
    [string]$Root = "",
    [string]$OutFile = "",
    [switch]$FilesOnly
)

$ErrorActionPreference = "Continue"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Get-Location).Path
}
$Root = (Resolve-Path -LiteralPath $Root).Path

if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutFile = Join-Path $Root "list-tree-$stamp.txt"
}

Write-Host "Scanning: $Root"
Write-Host "Output:   $OutFile"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Root: $Root")
$lines.Add("Captured: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')")
$lines.Add(("=" * 72))

$dirCount = 0
$fileCount = 0
$totalBytes = [int64]0

Get-ChildItem -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object FullName | ForEach-Object {
    $rel = $_.FullName.Substring($Root.Length).TrimStart('\', '/')
    if ([string]::IsNullOrEmpty($rel)) { return }

    if ($_.PSIsContainer) {
        $dirCount++
        if (-not $FilesOnly) {
            $lines.Add("[DIR]  $rel")
        }
    } else {
        $fileCount++
        $totalBytes += $_.Length
        $lines.Add(("{0,14}  {1}" -f $_.Length, $rel))
    }
}

$lines.Add(("=" * 72))
$lines.Add("Directories: $dirCount")
$lines.Add("Files:       $fileCount")
$lines.Add("Total bytes: $totalBytes")

$lines -join "`r`n" | Set-Content -Path $OutFile -Encoding ASCII

Write-Host "Done. Dirs=$dirCount Files=$fileCount Bytes=$totalBytes"
Write-Host "List: $OutFile"
