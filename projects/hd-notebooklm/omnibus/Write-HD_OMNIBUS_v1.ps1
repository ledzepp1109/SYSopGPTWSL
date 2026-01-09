Param(
  [Parameter(Mandatory = $true)]
  [string]$ExperimentRoot,

  [Parameter(Mandatory = $true)]
  [string]$SelectionCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
  try { return (Resolve-Path -LiteralPath $Path).Path } catch { return $Path }
}

$experiment = Resolve-FullPath $ExperimentRoot
if (-not (Test-Path -LiteralPath $SelectionCsv)) { throw "Selection CSV not found: $SelectionCsv" }

$out = Join-Path $experiment "HD_OMNIBUS_v1.md"
$rows = Import-Csv -LiteralPath $SelectionCsv
$incl = $rows | Where-Object { $_.action -eq "include" }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# HD_OMNIBUS_v1")
$lines.Add("")
$lines.Add("This file is a **master index** for NotebookLM upload and for downstream extraction work.")
$lines.Add("")
$lines.Add("## Section boundaries")
$lines.Add("Each notebook is wrapped in `BEGIN/END NOTEBOOK` markers to make it easy to copy/select blocks.")
$lines.Add("")

$nbGroups = $incl | Group-Object notebook | Sort-Object Name
foreach ($nb in $nbGroups) {
  $lines.Add(("<!-- BEGIN NOTEBOOK: {0} -->" -f $nb.Name))
  $lines.Add(("## Notebook: {0}" -f $nb.Name))
  $lines.Add("")
  $volGroups = $nb.Group | Group-Object volume_id, volume_kind | Sort-Object Name
  foreach ($v in $volGroups) {
    $one = $v.Group | Select-Object -First 1
    $title = $one.volume_title
    if (-not $title) { $title = $one.volume_id }
    $lines.Add(("### Source: {0} ({1})" -f $title, $one.volume_kind))
    $lines.Add("")
    $lines.Add("Included originals:")
    foreach ($r in ($v.Group | Sort-Object source_rel_path)) {
      $lines.Add(("- {0}" -f $r.source_rel_path))
    }
    $lines.Add("")
  }
  $lines.Add(("<!-- END NOTEBOOK: {0} -->" -f $nb.Name))
  $lines.Add("")
}

$lines | Out-File -LiteralPath $out -Encoding UTF8 -Force
Write-Host ("Wrote: {0}" -f $out)

