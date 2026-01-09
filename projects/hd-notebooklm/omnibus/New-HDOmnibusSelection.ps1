Param(
  [Parameter(Mandatory = $true)]
  [string]$ArchiveRoot,

  [Parameter(Mandatory = $true)]
  [string]$ExperimentRoot,

  [Parameter(Mandatory = $true)]
  [string]$ManifestGlob,

  [switch]$IncludeVideos,

  [switch]$IncludeDocs
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

function Guess-Notebook([string]$RelPath) {
  $p = $RelPath.ToLowerInvariant()
  if ($p -match "incarnation crosses") { return "INCARNATION_CROSSES" }
  if ($p -match "\\bg5\\") { return "BG5" }
  if ($p -match "phs|nutrition") { return "PHS_NUTRITION" }
  if ($p -match "dream rave") { return "DREAM_RAVE" }
  if ($p -match "astrology") { return "ASTROLOGY" }
  if ($p -match "center|centres") { return "CENTERS_MECHANICS" }
  return "CORE_TEACHINGS"
}

function Guess-VolumeId([string]$Notebook, [string]$RelPath) {
  # Deterministic stub ID; you’ll rename volumes during curation.
  $bucket = (Split-Path -Parent $RelPath) -replace "[^A-Za-z0-9]+", "_"
  if (-not $bucket) { $bucket = "root" }
  $bucket = $bucket.Trim("_")
  return ("{0}-{1}" -f $Notebook.ToLowerInvariant(), $bucket.ToLowerInvariant()).Substring(0, [Math]::Min(48, ("{0}-{1}" -f $Notebook.ToLowerInvariant(), $bucket.ToLowerInvariant()).Length))
}

function Get-ManifestPaths([string]$Glob) {
  # Works in Windows PowerShell 5.1 (no ** glob support) and PowerShell 7+.
  if ($Glob.Contains("\**\")) {
    # Convert "C:\root\**\*_files.txt" into a recursive scan from "C:\root" with a leaf filter.
    $root = $Glob.Split("**")[0].TrimEnd("\")
    $leaf = Split-Path -Leaf $Glob
    $paths = Get-ChildItem -LiteralPath $root -Recurse -File -Filter $leaf -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
    if (-not $paths -or $paths.Count -eq 0) { throw "No manifest files matched (recurse): $Glob" }
    return $paths
  }

  $paths = Get-ChildItem -Path $Glob -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
  if (-not $paths -or $paths.Count -eq 0) { throw "No manifest files matched: $Glob" }
  return $paths
}

function Read-ManifestLines([string]$ManifestPath) {
  # Manifest lines are expected to be file paths (absolute or relative).
  return Get-Content -LiteralPath $ManifestPath -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -and ($_ -notmatch "^\s*#") }
}

$archive = Resolve-FullPath $ArchiveRoot
$experiment = Resolve-FullPath $ExperimentRoot
if (-not (Test-Path -LiteralPath $archive)) { throw "ARCHIVE not found: $archive" }
New-Dir $experiment

$plansDir = Join-Path $experiment "_plans"
New-Dir $plansDir

$outCsv = Join-Path $plansDir "hd_omnibus_selection.csv"

$allowedExts = @(".pdf")
if ($IncludeVideos) { $allowedExts += @(".mp4", ".m4v", ".mov", ".mkv", ".avi", ".webm") }
if ($IncludeDocs) { $allowedExts += @(".doc", ".docx") }

$manifestPaths = Get-ManifestPaths -Glob $ManifestGlob
Write-Host ("Found {0} manifest file(s)." -f $manifestPaths.Count)

$rows = New-Object System.Collections.Generic.List[Object]

foreach ($m in $manifestPaths) {
  $lines = Read-ManifestLines -ManifestPath $m
  foreach ($line in $lines) {
    $full = $line
    if ($full -notmatch "^[A-Za-z]:\\") {
      $full = Join-Path $archive $full
    }
    if (-not (Test-Path -LiteralPath $full)) { continue }
    $item = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue
    if (-not $item) { continue }

    $ext = $item.Extension.ToLowerInvariant()
    if (-not ($allowedExts -contains $ext)) { continue }

    $rel = Get-RelativePath -Root $archive -FullPath $item.FullName
    $nb = Guess-Notebook -RelPath $rel
    $vid = Guess-VolumeId -Notebook $nb -RelPath $rel

    $rows.Add([PSCustomObject]@{
      action = "include"
      notebook = $nb
      volume_id = $vid
      volume_title = ""
      volume_kind = ($ext -eq ".pdf") ? "pdf_merge" : "video_single"
      source_path = $item.FullName
      source_rel_path = $rel
      source_type = $ext.TrimStart(".")
      notes = ("from_manifest={0}" -f (Split-Path -Leaf $m))
    })
  }
}

# De-dupe by relative path
$rows = $rows | Sort-Object source_rel_path -Unique

# Prefer PDF over DOC/DOCX when both exist with same basename
$byStem = @{}
foreach ($r in $rows) {
  $stem = ([IO.Path]::GetFileNameWithoutExtension($r.source_rel_path)).ToLowerInvariant()
  if (-not $byStem.ContainsKey($stem)) { $byStem[$stem] = @() }
  $byStem[$stem] += $r
}

$final = New-Object System.Collections.Generic.List[Object]
foreach ($stem in $byStem.Keys) {
  $group = $byStem[$stem]
  $hasPdf = $group | Where-Object { $_.source_type -eq "pdf" }
  if ($hasPdf -and $hasPdf.Count -gt 0) {
    foreach ($r in $group) {
      if ($r.source_type -in @("doc", "docx")) {
        $r.action = "exclude"
        $r.notes = ($r.notes + ";excluded_duplicate_prefer_pdf")
      }
    }
  }
  $final.AddRange($group)
}

$final | Export-Csv -LiteralPath $outCsv -NoTypeInformation -Encoding UTF8
Write-Host ("Wrote selection CSV: {0}" -f $outCsv)
Write-Host "Next: edit volume_id/volume_title/notebook to group into 10–15 sources per notebook."
