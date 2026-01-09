Param(
  [Parameter(Mandatory = $true)]
  [string]$ArchiveRoot,

  [Parameter(Mandatory = $true)]
  [string]$ExperimentRoot,

  [Parameter(Mandatory = $true)]
  [string]$SelectionCsv,

  [int]$MaxSourceMB = 200,

  [switch]$EnforceWordLimit,

  [int]$MaxWords = 500000,

  [switch]$DryRun
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

function Test-Command([string]$Name) {
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Require-Command([string]$Name, [string]$Help) {
  if (-not (Test-Command $Name)) { throw "$Name not found on PATH. $Help" }
}

function Get-PdfWordCountEstimate([string]$PdfPath) {
  if (-not (Test-Command "pdftotext")) { return $null }

  $tmp = Join-Path $env:TEMP ("hd_omnibus_words_{0}.txt" -f ([Guid]::NewGuid().ToString("n")))
  try {
    $args = @("-enc","UTF-8","-nopgbrk",$PdfPath,$tmp)
    $p = Start-Process -FilePath "pdftotext" -ArgumentList $args -NoNewWindow -PassThru -Wait
    if ($p.ExitCode -ne 0) { return $null }

    $count = 0
    Get-Content -LiteralPath $tmp -ReadCount 2000 -Encoding UTF8 | ForEach-Object {
      foreach ($line in $_) {
        $parts = $line -split "\s+"
        foreach ($w in $parts) { if ($w) { $count++ } }
      }
    }
    return $count
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Word-Ensure() {
  try {
    $app = New-Object -ComObject Word.Application
    $app.Visible = $false
    return $app
  } catch {
    return $null
  }
}

function Word-ExportTextPdf([object]$WordApp, [string]$Text, [string]$OutPdf) {
  $tmpDocx = [IO.Path]::ChangeExtension($OutPdf, ".docx")
  if (Test-Path -LiteralPath $tmpDocx) { Remove-Item -LiteralPath $tmpDocx -Force }
  if (Test-Path -LiteralPath $OutPdf) { Remove-Item -LiteralPath $OutPdf -Force }

  $doc = $WordApp.Documents.Add()
  $doc.Content.Text = $Text
  $doc.SaveAs([ref]$tmpDocx)
  # 17 = wdFormatPDF
  $doc.ExportAsFixedFormat($OutPdf, 17)
  $doc.Close()
  Remove-Item -LiteralPath $tmpDocx -Force -ErrorAction SilentlyContinue
}

function Word-ConvertDocToPdf([object]$WordApp, [string]$InPath, [string]$OutPdf) {
  if (Test-Path -LiteralPath $OutPdf) { Remove-Item -LiteralPath $OutPdf -Force }
  $doc = $WordApp.Documents.Open($InPath, $false, $true) # read-only
  $doc.ExportAsFixedFormat($OutPdf, 17)
  $doc.Close()
}

function Pdfsam-Merge([string[]]$Inputs, [string]$OutputPdf) {
  # PDFsam Console syntax varies by version; we try the common "merge -o -f" form.
  $args = @("merge", "-o", $OutputPdf, "-f") + $Inputs
  if ($DryRun) {
    Write-Host ("[DRYRUN] pdfsam-console {0}" -f ($args -join " "))
    return
  }
  $p = Start-Process -FilePath "pdfsam-console" -ArgumentList $args -NoNewWindow -PassThru -Wait
  if ($p.ExitCode -ne 0) { throw "pdfsam-console merge failed (exit=$($p.ExitCode))" }
}

function Ensure-UnderSize([string]$Path, [int64]$MaxBytes) {
  $len = (Get-Item -LiteralPath $Path).Length
  if ($len -gt $MaxBytes) { throw ("Output exceeds size limit: {0} bytes > {1} bytes ({2})" -f $len, $MaxBytes, $Path) }
}

$archive = Resolve-FullPath $ArchiveRoot
$experiment = Resolve-FullPath $ExperimentRoot
if (-not (Test-Path -LiteralPath $archive)) { throw "ARCHIVE not found: $archive" }
if (-not (Test-Path -LiteralPath $SelectionCsv)) { throw "Selection CSV not found: $SelectionCsv" }

Require-Command -Name "pdfsam-console" -Help "Install PDFsam Console and add it to PATH."
Require-Command -Name "ffmpeg" -Help "Install ffmpeg and add it to PATH."
Require-Command -Name "ffprobe" -Help "ffprobe should ship with ffmpeg."

$word = Word-Ensure
if (-not $word) { throw "Microsoft Word COM automation not available. Install Office or add LibreOffice fallback to this script." }

try {
  $maxBytes = [int64]$MaxSourceMB * 1024 * 1024
  $buildDir = Join-Path $experiment "_build"
  $logsDir = Join-Path $experiment "_logs"
  New-Dir $buildDir
  New-Dir $logsDir

  $pdfOutRoot = Join-Path $buildDir "pdf"
  $vidOutRoot = Join-Path $buildDir "video"
  New-Dir $pdfOutRoot
  New-Dir $vidOutRoot

  $rows = Import-Csv -LiteralPath $SelectionCsv
  $incl = $rows | Where-Object { $_.action -eq "include" }

  $groups = $incl | Group-Object notebook, volume_id, volume_kind

  foreach ($g in $groups) {
    $one = $g.Group | Select-Object -First 1
    $notebook = $one.notebook
    $volumeId = $one.volume_id
    $kind = $one.volume_kind
    $title = $one.volume_title
    if (-not $title) { $title = $volumeId }

    Write-Host ("Building {0} / {1} ({2})" -f $notebook, $volumeId, $kind)

    if ($kind -eq "pdf_merge") {
      $volDir = Join-Path $pdfOutRoot $notebook
      New-Dir $volDir

      $safeName = ($title -replace "[^A-Za-z0-9 _\\-]+", "").Trim()
      if (-not $safeName) { $safeName = $volumeId }
      $outPdf = Join-Path $volDir ("{0}.pdf" -f $safeName.Replace(" ", "_"))

      $stageDir = Join-Path $logsDir ("stage_{0}_{1}" -f $notebook, $volumeId)
      New-Dir $stageDir

      $tocText = @()
      $tocText += $title
      $tocText += ("Notebook: {0}" -f $notebook)
      $tocText += ("Volume: {0}" -f $volumeId)
      $tocText += ""
      $tocText += "Included sources:"

      $inputs = New-Object System.Collections.Generic.List[string]
      $tocPdf = Join-Path $stageDir "000_TOC.pdf"
      Word-ExportTextPdf -WordApp $word -Text ($tocText -join "`r`n") -OutPdf $tocPdf
      $inputs.Add($tocPdf)

      $i = 0
      foreach ($r in ($g.Group | Sort-Object source_rel_path)) {
        $i++
        $src = $r.source_path
        if (-not (Test-Path -LiteralPath $src)) {
          # If the selection uses rel paths, resolve against ARCHIVE.
          $src = Join-Path $archive $r.source_rel_path
        }
        if (-not (Test-Path -LiteralPath $src)) { throw "Missing source: $($r.source_path)" }

        $ext = ([IO.Path]::GetExtension($src)).ToLowerInvariant()
        $srcPdf = $src

        if ($ext -in @(".doc", ".docx")) {
          $convDir = Join-Path $stageDir "converted"
          New-Dir $convDir
          $srcPdf = Join-Path $convDir (([IO.Path]::GetFileNameWithoutExtension($src)) + ".pdf")
          Word-ConvertDocToPdf -WordApp $word -InPath $src -OutPdf $srcPdf
        }

        $divider = Join-Path $stageDir ("{0:D3}_DIVIDER.pdf" -f $i)
        $dividerText = @(
          "SOURCE $i",
          "",
          ("Path: {0}" -f $r.source_rel_path),
          ("SHA256: {0}" -f (Get-Sha256 -Path $srcPdf))
        ) -join "`r`n"
        Word-ExportTextPdf -WordApp $word -Text $dividerText -OutPdf $divider

        $inputs.Add($divider)
        $inputs.Add($srcPdf)
      }

      Pdfsam-Merge -Inputs $inputs.ToArray() -OutputPdf $outPdf
      Ensure-UnderSize -Path $outPdf -MaxBytes $maxBytes

      $words = Get-PdfWordCountEstimate -PdfPath $outPdf
      if ($null -eq $words) {
        Write-Warning "Word-count estimate unavailable (install poppler pdftotext to enforce 500k-word rule)."
      } else {
        Write-Host ("Estimated words: {0}" -f $words)
        if ($EnforceWordLimit -and $words -gt $MaxWords) {
          throw ("Estimated words exceed limit: {0} > {1} ({2})" -f $words, $MaxWords, $outPdf)
        }
      }

      Write-Host ("Wrote: {0}" -f $outPdf)
      continue
    }

    if ($kind -eq "video_single") {
      $outDir = Join-Path $vidOutRoot $notebook
      New-Dir $outDir
      foreach ($r in $g.Group) {
        $src = $r.source_path
        if (-not (Test-Path -LiteralPath $src)) { $src = Join-Path $archive $r.source_rel_path }
        if (-not (Test-Path -LiteralPath $src)) { throw "Missing source: $($r.source_path)" }

        $base = [IO.Path]::GetFileNameWithoutExtension($src)
        $out = Join-Path $outDir ($base + ".mp4")

        $args = @(
          "-hide_banner","-y",
          "-i",$src,
          "-map","0",
          "-c:v","libx264","-preset","veryfast","-crf","30",
          "-c:a","aac","-b:a","96k",
          "-movflags","+faststart",
          $out
        )
        if ($DryRun) {
          Write-Host ("[DRYRUN] ffmpeg {0}" -f ($args -join " "))
        } else {
          $p = Start-Process -FilePath "ffmpeg" -ArgumentList $args -NoNewWindow -PassThru -Wait
          if ($p.ExitCode -ne 0) { throw "ffmpeg failed (exit=$($p.ExitCode)) for $src" }
          Ensure-UnderSize -Path $out -MaxBytes $maxBytes
        }
      }
      continue
    }

    if ($kind -eq "video_concat") {
      # Concatenate by re-encoding the whole pack once (stable output); keep packs small to stay under 200MB.
      $outDir = Join-Path $vidOutRoot $notebook
      New-Dir $outDir

      $safeTitle = ($title -replace "[^A-Za-z0-9 _\\-]+", "").Trim()
      if (-not $safeTitle) { $safeTitle = $volumeId }
      $out = Join-Path $outDir ($safeTitle.Replace(" ", "_") + ".mp4")

      $listFile = Join-Path $logsDir ("concat_{0}_{1}.txt" -f $notebook, $volumeId)
      $lines = @()
      foreach ($r in ($g.Group | Sort-Object source_rel_path)) {
        $src = $r.source_path
        if (-not (Test-Path -LiteralPath $src)) { $src = Join-Path $archive $r.source_rel_path }
        if (-not (Test-Path -LiteralPath $src)) { throw "Missing source: $($r.source_path)" }
        $lines += ("file '{0}'" -f ($src -replace "'", "''"))
      }
      $lines | Out-File -LiteralPath $listFile -Encoding UTF8 -Force

      $args = @(
        "-hide_banner","-y",
        "-f","concat","-safe","0",
        "-i",$listFile,
        "-c:v","libx264","-preset","veryfast","-crf","30",
        "-c:a","aac","-b:a","96k",
        "-movflags","+faststart",
        $out
      )
      if ($DryRun) {
        Write-Host ("[DRYRUN] ffmpeg {0}" -f ($args -join " "))
      } else {
        $p = Start-Process -FilePath "ffmpeg" -ArgumentList $args -NoNewWindow -PassThru -Wait
        if ($p.ExitCode -ne 0) { throw "ffmpeg concat failed (exit=$($p.ExitCode))" }
        Ensure-UnderSize -Path $out -MaxBytes $maxBytes
      }
      continue
    }

    throw "Unknown volume_kind: $kind"
  }

  Write-Host "Build complete."
} finally {
  if ($word) {
    try { $word.Quit() | Out-Null } catch {}
  }
}
