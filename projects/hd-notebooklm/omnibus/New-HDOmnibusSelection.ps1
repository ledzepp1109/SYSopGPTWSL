Param(
  [Parameter(Mandatory = $true)]
  [string]$ArchiveRoot,

  [Parameter(Mandatory = $true)]
  [string]$ExperimentRoot,

  [Parameter(Mandatory = $true)]
  [string]$ManifestGlob,

  [string]$ArchiveSnapshotCsv = "",

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
  if ($p -match "incarnation\\s+cross") { return "INCARNATION_CROSSES" }
  if ($p -match "\\bg5\\|\\bbg5\\b") { return "BG5" }
  if ($p -match "phs|nutrition|determination|environment|primary health system") { return "PHS_NUTRITION" }
  if ($p -match "dream rave|variable|tone|base|color|bardo") { return "ADVANCED" }
  if ($p -match "astrology|ephemer|fixed stars|zodiac") { return "ASTROLOGY" }
  if ($p -match "type|strategy|authority|profile|\\blines\\b|\\bline\\b") { return "TYPES_STRATEGY_AUTHORITY" }
  if ($p -match "gate|channel|circuit|center|centres|mechanics|anatomy") { return "CENTERS_MECHANICS" }
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

function Build-SnapshotIndex([string]$SnapshotCsv) {
  if (-not $SnapshotCsv) { return $null }
  if (-not (Test-Path -LiteralPath $SnapshotCsv)) { throw "Archive snapshot CSV not found: $SnapshotCsv" }

  $rows = Import-Csv -LiteralPath $SnapshotCsv
  $idx = @{}

  foreach ($r in $rows) {
    $name = $r.Name
    if (-not $name) { continue }
    $key = $name.ToLowerInvariant()
    if (-not $idx.ContainsKey($key)) { $idx[$key] = @() }
    $idx[$key] += $r
  }

  return $idx
}

function Select-BestSnapshotMatch([object[]]$Candidates) {
  if (-not $Candidates -or $Candidates.Count -eq 0) { return $null }

  $sorted = $Candidates | Sort-Object `
    @{ Expression = { if ($_.RelativePath -match "\\\\assets\\\\") { 1 } else { 0 } } }, `
    @{ Expression = { if ($_.RelativePath) { $_.RelativePath.Length } else { 999999 } } }, `
    @{ Expression = { try { -[int64]$_.SizeBytes } catch { 0 } } }

  return ($sorted | Select-Object -First 1)
}

$archive = Resolve-FullPath $ArchiveRoot
$experiment = Resolve-FullPath $ExperimentRoot
if (-not (Test-Path -LiteralPath $archive)) { throw "ARCHIVE not found: $archive" }
New-Dir $experiment

$plansDir = Join-Path $experiment "_plans"
New-Dir $plansDir

$outCsv = Join-Path $plansDir "hd_omnibus_selection.csv"

$snapshotIndex = $null
if ($ArchiveSnapshotCsv) {
  $snapshotIndex = Build-SnapshotIndex -SnapshotCsv $ArchiveSnapshotCsv
  Write-Host ("Loaded archive snapshot index: {0} distinct names" -f $snapshotIndex.Keys.Count)
}

$allowedExts = @(".pdf")
if ($IncludeVideos) { $allowedExts += @(".mp4", ".m4v", ".mov", ".mkv", ".avi", ".webm") }
if ($IncludeDocs) { $allowedExts += @(".doc", ".docx") }

$manifestPaths = Get-ManifestPaths -Glob $ManifestGlob
Write-Host ("Found {0} manifest file(s)." -f $manifestPaths.Count)

$rows = New-Object System.Collections.Generic.List[Object]
$resolvedViaSnapshot = 0
$unresolved = 0

foreach ($m in $manifestPaths) {
  $lines = Read-ManifestLines -ManifestPath $m
  foreach ($line in $lines) {
    $resolved = $false
    $lineExt = ([IO.Path]::GetExtension($line)).ToLowerInvariant()
    if (-not ($allowedExts -contains $lineExt)) { continue }

    $full = $line
    if ($full -notmatch "^[A-Za-z]:\\") {
      $full = Join-Path $archive $full
    }

    $rel = $null
    if (-not (Test-Path -LiteralPath $full)) {
      if ($snapshotIndex) {
        $leaf = [IO.Path]::GetFileName($full)
        if ($leaf) {
          $key = $leaf.ToLowerInvariant()
          if ($snapshotIndex.ContainsKey($key)) {
            $best = Select-BestSnapshotMatch -Candidates $snapshotIndex[$key]
            if ($best -and $best.Path -and (Test-Path -LiteralPath $best.Path)) {
              $full = $best.Path
              $rel = $best.RelativePath
              $resolvedViaSnapshot++
              $resolved = $true
            }
          }
        }
      }
    }

    if (-not (Test-Path -LiteralPath $full)) { $unresolved++; continue }
    $item = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue
    if (-not $item) { continue }

    $ext = $item.Extension.ToLowerInvariant()
    if (-not ($allowedExts -contains $ext)) { continue }

    if (-not $rel) { $rel = Get-RelativePath -Root $archive -FullPath $item.FullName }
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
      notes = ("from_manifest={0}{1}" -f (Split-Path -Leaf $m), ($resolved ? ";resolved_via_snapshot" : ""))
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
if ($snapshotIndex) {
  Write-Host ("Resolved via snapshot: {0} (unresolved manifest lines: {1})" -f $resolvedViaSnapshot, $unresolved)
}
Write-Host "Next: edit volume_id/volume_title/notebook to group into 10–15 sources per notebook."
