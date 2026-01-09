Param(
  [Parameter(Mandatory = $true)]
  [string]$ArchiveRoot,

  [Parameter(Mandatory = $true)]
  [string]$ExperimentRoot,

  [int]$HashMaxMB = 25,

  [switch]$VerifyOnly,

  [string]$BaselineCsv = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Resolve-FullPath([string]$Path) {
  try { return (Resolve-Path -LiteralPath $Path).Path } catch { return $Path }
}

function Get-RelativePath([string]$Root, [string]$FullPath) {
  $rootFull = (Resolve-FullPath $Root).TrimEnd("\")
  $full = (Resolve-FullPath $FullPath)
  if ($full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
    return $full.Substring($rootFull.Length).TrimStart("\")
  }
  return (Split-Path -Leaf $full)
}

function Get-Sha256([string]$Path) {
  $h = Get-FileHash -Algorithm SHA256 -LiteralPath $Path
  return $h.Hash.ToLowerInvariant()
}

$archive = Resolve-FullPath $ArchiveRoot
$experiment = Resolve-FullPath $ExperimentRoot
if (-not (Test-Path -LiteralPath $archive)) { throw "ARCHIVE not found: $archive" }

$freezeDir = Join-Path $experiment "_freeze"
New-Dir $freezeDir

$outCsv = Join-Path $freezeDir "archive_snapshot.csv"
if ($BaselineCsv) { $outCsv = $BaselineCsv }

if ($VerifyOnly) {
  if (-not (Test-Path -LiteralPath $outCsv)) { throw "Baseline snapshot not found: $outCsv" }
  $baseline = Import-Csv -LiteralPath $outCsv

  $current = @{}
  Get-ChildItem -LiteralPath $archive -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    $rel = Get-RelativePath -Root $archive -FullPath $_.FullName
    $current[$rel] = @{
      size = $_.Length
      mtimeUtc = $_.LastWriteTimeUtc.ToString("o")
    }
  }

  $missing = 0
  $changed = 0
  foreach ($row in $baseline) {
    $rel = $row.rel_path
    if (-not $current.ContainsKey($rel)) { $missing++; continue }
    if (($current[$rel].size -ne [int64]$row.size_bytes) -or ($current[$rel].mtimeUtc -ne $row.mtime_utc)) {
      $changed++
    }
  }

  $added = 0
  foreach ($k in $current.Keys) {
    if (-not ($baseline.rel_path -contains $k)) { $added++ }
  }

  Write-Host ("VerifyOnly results: missing={0} changed={1} added={2}" -f $missing, $changed, $added)
  if ($missing -eq 0 -and $changed -eq 0 -and $added -eq 0) {
    Write-Host "ARCHIVE matches baseline snapshot."
    exit 0
  }
  Write-Warning "ARCHIVE drift detected. Re-snapshot or investigate differences."
  exit 2
}

"rel_path,size_bytes,mtime_utc,sha256" | Out-File -LiteralPath $outCsv -Encoding UTF8 -Force

$hashMaxBytes = [int64]$HashMaxMB * 1024 * 1024
$count = 0

Get-ChildItem -LiteralPath $archive -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName | ForEach-Object {
  $rel = Get-RelativePath -Root $archive -FullPath $_.FullName
  $sha = ""
  if ($_.Length -le $hashMaxBytes) {
    try { $sha = Get-Sha256 -Path $_.FullName } catch { $sha = "" }
  }
  ('"{0}",{1},"{2}","{3}"' -f ($rel -replace '"','""'), $_.Length, $_.LastWriteTimeUtc.ToString("o"), $sha) |
    Add-Content -LiteralPath $outCsv -Encoding UTF8
  $count++
  if (($count % 1000) -eq 0) { Write-Host ("Snapshotted {0} files..." -f $count) }
}

Write-Host ("Wrote snapshot: {0}" -f $outCsv)

