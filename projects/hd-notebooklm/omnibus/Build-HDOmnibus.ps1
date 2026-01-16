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

function Find-CommandPath([string]$Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Find-Ghostscript() {
  $cmd = Get-Command "gswin64c.exe" -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $roots = @()
  if ($env:ProgramFiles) { $roots += (Join-Path $env:ProgramFiles "gs") }
  if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} "gs") }

  foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $dirs = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($d in $dirs) {
      $p = Join-Path $d.FullName "bin\\gswin64c.exe"
      if (Test-Path -LiteralPath $p) { return $p }
    }
  }

  return $null
}

function Find-LibreOffice() {
  $cmd = Get-Command "soffice.exe" -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $roots = @()
  if ($env:ProgramFiles) { $roots += (Join-Path $env:ProgramFiles "LibreOffice\\program\\soffice.exe") }
  if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} "LibreOffice\\program\\soffice.exe") }

  foreach ($p in $roots) {
    if (Test-Path -LiteralPath $p) { return $p }
  }

  return $null
}

function Invoke-External([string]$Exe, [string[]]$ArgumentList, [string]$Label) {
  if ($DryRun) {
    Write-Host ("[DRYRUN] {0} {1}" -f $Exe, ($ArgumentList -join " "))
    return
  }
  & $Exe @ArgumentList
  if ($LASTEXITCODE -ne 0) { throw ("{0} failed (exit={1})" -f $Label, $LASTEXITCODE) }
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

function Normalize-Ascii([string]$Text) {
  if ($null -eq $Text) { return "" }
  $bytes = [Text.Encoding]::ASCII.GetBytes($Text)
  return [Text.Encoding]::ASCII.GetString($bytes)
}

function Escape-PsString([string]$Text) {
  $t = Normalize-Ascii -Text $Text
  $t = $t.Replace("\", "\\")
  $t = $t.Replace("(", "\(")
  $t = $t.Replace(")", "\)")
  return $t
}

function Wrap-Line([string]$Line, [int]$MaxChars) {
  $out = New-Object System.Collections.Generic.List[string]
  $t = $Line
  while ($t.Length -gt $MaxChars) {
    $out.Add($t.Substring(0, $MaxChars))
    $t = $t.Substring($MaxChars)
  }
  $out.Add($t)
  return $out
}

function Ghostscript-ExportTextPdf([string]$GhostscriptExe, [string]$Text, [string]$OutPdf) {
  if (-not $GhostscriptExe) { throw "Ghostscript not available for text→PDF rendering." }
  if (Test-Path -LiteralPath $OutPdf) { Remove-Item -LiteralPath $OutPdf -Force }

  $ps = Join-Path ([IO.Path]::GetDirectoryName($OutPdf)) ("hd_omnibus_{0}.ps" -f ([Guid]::NewGuid().ToString("n")))
  try {
    $rawLines = ($Text -split "\\r?\\n")
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in $rawLines) {
      foreach ($w in (Wrap-Line -Line $l -MaxChars 92)) { $lines.Add($w) }
    }

    $psLines = New-Object System.Collections.Generic.List[string]
    $psLines.Add("%!PS-Adobe-3.0")
    $psLines.Add("<< /PageSize [612 792] >> setpagedevice")
    $psLines.Add("/Helvetica findfont 10 scalefont setfont")

    $x = 54
    $y = 760
    $leading = 12
    $lineOnPage = 0

    foreach ($l in $lines) {
      if ($lineOnPage -ge 56) {
        $psLines.Add("showpage")
        $y = 760
        $lineOnPage = 0
      }
      $esc = Escape-PsString -Text $l
      $psLines.Add(("{0} {1} moveto ({2}) show" -f $x, $y, $esc))
      $y -= $leading
      $lineOnPage++
    }
    $psLines.Add("showpage")

    $psLines | Out-File -LiteralPath $ps -Encoding ascii -Force

    $args = @("-q", "-dNOPAUSE", "-dBATCH", "-sDEVICE=pdfwrite", ("-sOutputFile=" + $OutPdf), $ps)
    Invoke-External -Exe $GhostscriptExe -ArgumentList $args -Label "ghostscript text→pdf"
  } finally {
    Remove-Item -LiteralPath $ps -Force -ErrorAction SilentlyContinue
  }
}

function Export-TextPdf([object]$WordApp, [string]$GhostscriptExe, [string]$Text, [string]$OutPdf) {
  if ($WordApp) {
    Word-ExportTextPdf -WordApp $WordApp -Text $Text -OutPdf $OutPdf
    return
  }
  Ghostscript-ExportTextPdf -GhostscriptExe $GhostscriptExe -Text $Text -OutPdf $OutPdf
}

function LibreOffice-ConvertDocToPdf([string]$SofficeExe, [string]$InPath, [string]$OutPdf) {
  if (-not $SofficeExe) { throw "LibreOffice not available for DOC/DOCX→PDF conversion." }
  if (Test-Path -LiteralPath $OutPdf) { Remove-Item -LiteralPath $OutPdf -Force }

  $outDir = Split-Path -Parent $OutPdf
  New-Dir $outDir

  $args = @(
    "--headless",
    "--nologo",
    "--nofirststartwizard",
    "--convert-to", "pdf",
    "--outdir", $outDir,
    $InPath
  )
  Invoke-External -Exe $SofficeExe -ArgumentList $args -Label "libreoffice convert-to pdf"

  $expected = Join-Path $outDir (([IO.Path]::GetFileNameWithoutExtension($InPath)) + ".pdf")
  if (-not (Test-Path -LiteralPath $expected)) { throw "LibreOffice did not produce expected PDF: $expected" }
  if ($expected -ne $OutPdf) { Move-Item -LiteralPath $expected -Destination $OutPdf -Force }
}

function Convert-DocToPdf([object]$WordApp, [string]$SofficeExe, [string]$InPath, [string]$OutPdf) {
  if ($WordApp) {
    Word-ConvertDocToPdf -WordApp $WordApp -InPath $InPath -OutPdf $OutPdf
    return
  }
  LibreOffice-ConvertDocToPdf -SofficeExe $SofficeExe -InPath $InPath -OutPdf $OutPdf
}

function Pdfsam-Merge([string]$PdfsamExe, [string[]]$Inputs, [string]$OutputPdf) {
  # PDFsam Console syntax varies by version; we try the common "merge -o -f" form.
  $args = @("merge", "-o", $OutputPdf, "-f") + $Inputs
  Invoke-External -Exe $PdfsamExe -ArgumentList $args -Label "pdfsam-console merge"
}

function Ghostscript-Merge([string]$GhostscriptExe, [string[]]$Inputs, [string]$OutputPdf, [string]$PdfSettings = "/ebook") {
  if (-not $GhostscriptExe) { throw "Ghostscript not available for PDF merge." }
  $args = @(
    "-q",
    "-dNOPAUSE",
    "-dBATCH",
    "-sDEVICE=pdfwrite",
    ("-dPDFSETTINGS=" + $PdfSettings),
    ("-sOutputFile=" + $OutputPdf)
  ) + $Inputs
  Invoke-External -Exe $GhostscriptExe -ArgumentList $args -Label "ghostscript merge"
}

function Pdf-Merge([string]$PdfsamExe, [string]$GhostscriptExe, [string[]]$Inputs, [string]$OutputPdf) {
  if ($PdfsamExe) {
    Pdfsam-Merge -PdfsamExe $PdfsamExe -Inputs $Inputs -OutputPdf $OutputPdf
    return
  }
  Ghostscript-Merge -GhostscriptExe $GhostscriptExe -Inputs $Inputs -OutputPdf $OutputPdf
}

function Ensure-UnderSize([string]$Path, [int64]$MaxBytes) {
  $len = (Get-Item -LiteralPath $Path).Length
  if ($len -gt $MaxBytes) { throw ("Output exceeds size limit: {0} bytes > {1} bytes ({2})" -f $len, $MaxBytes, $Path) }
}

$archive = Resolve-FullPath $ArchiveRoot
$experiment = Resolve-FullPath $ExperimentRoot
if (-not (Test-Path -LiteralPath $archive)) { throw "ARCHIVE not found: $archive" }
if (-not (Test-Path -LiteralPath $SelectionCsv)) { throw "Selection CSV not found: $SelectionCsv" }

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

  $needsPdf = ($incl | Where-Object { $_.volume_kind -eq "pdf_merge" } | Measure-Object).Count -gt 0
  $needsVideo = ($incl | Where-Object { $_.volume_kind -like "video_*" } | Measure-Object).Count -gt 0
  $needsDocs = ($incl | Where-Object { $_.source_type -in @("doc", "docx") } | Measure-Object).Count -gt 0

  $pdfsamExe = Find-CommandPath -Name "pdfsam-console"
  $ghostscriptExe = Find-Ghostscript
  $sofficeExe = Find-LibreOffice
  $word = Word-Ensure

  if ($needsVideo) {
    Require-Command -Name "ffmpeg" -Help "Install ffmpeg and add it to PATH."
    Require-Command -Name "ffprobe" -Help "ffprobe should ship with ffmpeg."
  }

  if ($needsPdf -and (-not $pdfsamExe) -and (-not $ghostscriptExe)) {
    throw "No PDF merge tool available. Install pdfsam-console or Ghostscript (gswin64c.exe)."
  }

  if ($needsPdf -and (-not $word) -and (-not $ghostscriptExe)) {
    throw "No text→PDF renderer available for TOC/dividers. Install Microsoft Word (COM) or Ghostscript."
  }

  if ($needsDocs -and (-not $word) -and (-not $sofficeExe)) {
    throw "DOC/DOCX conversion requested but neither Word (COM) nor LibreOffice is available."
  }

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

      if ((Test-Path -LiteralPath $outPdf) -and (-not $DryRun)) {
        try {
          Ensure-UnderSize -Path $outPdf -MaxBytes $maxBytes
          Write-Host ("Skip existing (under limit): {0}" -f $outPdf)
          continue
        } catch {
          Write-Warning ("Existing output will be rebuilt: {0}" -f $outPdf)
        }
      }

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
      Export-TextPdf -WordApp $word -GhostscriptExe $ghostscriptExe -Text ($tocText -join "`r`n") -OutPdf $tocPdf
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
          Convert-DocToPdf -WordApp $word -SofficeExe $sofficeExe -InPath $src -OutPdf $srcPdf
        }

        $divider = Join-Path $stageDir ("{0:D3}_DIVIDER.pdf" -f $i)
        $dividerText = @(
          "SOURCE $i",
          "",
          ("Path: {0}" -f $r.source_rel_path),
          ("SHA256: {0}" -f (Get-Sha256 -Path $srcPdf))
        ) -join "`r`n"
        Export-TextPdf -WordApp $word -GhostscriptExe $ghostscriptExe -Text $dividerText -OutPdf $divider

        $inputs.Add($divider)
        $inputs.Add($srcPdf)
      }

      if ($DryRun) {
        Write-Host ("[DRYRUN] Would write: {0} (sources={1}, inputs={2})" -f $outPdf, $g.Group.Count, $inputs.Count)
        continue
      }

      try {
        Pdf-Merge -PdfsamExe $pdfsamExe -GhostscriptExe $ghostscriptExe -Inputs $inputs.ToArray() -OutputPdf $outPdf
        Ensure-UnderSize -Path $outPdf -MaxBytes $maxBytes
      } catch {
        $oversize = ($_.Exception.Message -match "Output exceeds size limit")
        if (-not $oversize) { throw }
        if ($pdfsamExe) { throw }

        Write-Warning ("Oversize output; retrying Ghostscript merge with /screen: {0}" -f $outPdf)
        Ghostscript-Merge -GhostscriptExe $ghostscriptExe -Inputs $inputs.ToArray() -OutputPdf $outPdf -PdfSettings "/screen"
        Ensure-UnderSize -Path $outPdf -MaxBytes $maxBytes
      }

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
