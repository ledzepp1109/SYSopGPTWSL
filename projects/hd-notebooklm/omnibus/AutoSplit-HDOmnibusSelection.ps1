Param(
  [Parameter(Mandatory = $true)]
  [string]$ArchiveRoot,

  [Parameter(Mandatory = $true)]
  [string]$SelectionCsv,

  [Parameter(Mandatory = $true)]
  [string]$OutCsv,

  [int]$TargetVolumeMB = 170,

  [int]$MaxPerVolume = 25
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

function Resolve-SourcePath([string]$Archive, [object]$Row) {
  $src = $Row.source_path
  if ($src -and (Test-Path -LiteralPath $src)) { return $src }
  if ($Row.source_rel_path) {
    $p = Join-Path $Archive $Row.source_rel_path
    if (Test-Path -LiteralPath $p) { return $p }
  }
  return $null
}

$archive = Resolve-FullPath $ArchiveRoot
if (-not (Test-Path -LiteralPath $archive)) { throw "ARCHIVE not found: $archive" }
if (-not (Test-Path -LiteralPath $SelectionCsv)) { throw "Selection CSV not found: $SelectionCsv" }

New-Dir (Split-Path -Parent $OutCsv)

$rows = Import-Csv -LiteralPath $SelectionCsv
$incl = @($rows | Where-Object { $_.action -eq "include" })
$excl = @($rows | Where-Object { $_.action -ne "include" })

$targetBytes = [int64]$TargetVolumeMB * 1024 * 1024
$outIncl = New-Object System.Collections.Generic.List[Object]

$groups = $incl | Group-Object notebook, volume_id, volume_kind

foreach ($g in $groups) {
  $one = $g.Group | Select-Object -First 1
  if ($one.volume_kind -ne "pdf_merge") {
    foreach ($r in $g.Group) { $outIncl.Add($r) }
    continue
  }

  $sorted = $g.Group | Sort-Object source_rel_path
  $buckets = New-Object System.Collections.Generic.List[Object]
  $bucket = New-Object System.Collections.Generic.List[Object]
  $bucketBytes = [int64]0

  foreach ($r in $sorted) {
    $src = Resolve-SourcePath -Archive $archive -Row $r
    if (-not $src) { throw "Missing source for row: $($r.source_path)" }
    $len = (Get-Item -LiteralPath $src).Length

    $exceeds = ($bucket.Count -ge $MaxPerVolume) -or (($bucket.Count -gt 0) -and (($bucketBytes + $len) -gt $targetBytes))
    if ($exceeds) {
      $buckets.Add(@($bucket.ToArray()))
      $bucket = New-Object System.Collections.Generic.List[Object]
      $bucketBytes = [int64]0
    }

    $bucket.Add($r)
    $bucketBytes += $len
  }

  if ($bucket.Count -gt 0) { $buckets.Add(@($bucket.ToArray())) }

  if ($buckets.Count -le 1) {
    foreach ($r in $sorted) { $outIncl.Add($r) }
    continue
  }

  $baseId = $one.volume_id
  $baseTitle = $one.volume_title
  if (-not $baseTitle) { $baseTitle = $baseId }

  $idx = 0
  foreach ($b in $buckets) {
    $idx++
    $newId = ("{0}-p{1:D2}" -f $baseId, $idx)
    $newTitle = ("{0} (Part {1})" -f $baseTitle, $idx)
    foreach ($r in $b) {
      $r.volume_id = $newId
      if (-not $r.volume_title) { $r.volume_title = $newTitle }
      $outIncl.Add($r)
    }
  }
}

$outAll = New-Object System.Collections.Generic.List[Object]
$outAll.AddRange($outIncl)
$outAll.AddRange($excl)

$outAll | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
Write-Host ("Wrote: {0}" -f $OutCsv)

$vols = ($outIncl | Group-Object notebook, volume_id, volume_kind)
Write-Host ("Volumes: {0}" -f $vols.Count)
($vols | Sort-Object Count -Descending | Select-Object -First 10 Count, Name) | Format-Table -AutoSize
