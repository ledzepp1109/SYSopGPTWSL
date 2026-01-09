Param(
  [Parameter(Mandatory = $true)]
  [string]$ArchiveRoot,

  [Parameter(Mandatory = $true)]
  [string]$ExperimentRoot,

  [string]$VideoListPath = "",

  [int]$StartAfter = 0,

  [switch]$Resume,

  [int]$MaxSourceMB = 200,

  [int]$Retries = 2,

  [int]$MinCrf = 26,

  [int]$MaxCrf = 34,

  [switch]$AllowSplit = $true,

  [int]$MaxFailures = 200,

  [int]$ThrottleMs = 250,

  [switch]$SelfTest,

  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-FullPath([string]$Path) {
  try { return (Resolve-Path -LiteralPath $Path).Path } catch { return $Path }
}

function Test-Command([string]$Name) {
  return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function New-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-JsonFile([string]$Path, $Obj) {
  $json = $Obj | ConvertTo-Json -Depth 10
  [IO.File]::WriteAllText($Path, $json, [Text.Encoding]::UTF8)
}

function Read-JsonFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8) | ConvertFrom-Json
}

function Csv-AppendRow([string]$Path, [hashtable]$Row, [string[]]$Header) {
  $exists = Test-Path -LiteralPath $Path
  if (-not $exists) {
    ($Header -join ",") | Out-File -LiteralPath $Path -Encoding UTF8 -Force
  }
  $line = ($Header | ForEach-Object {
    $value = $Row[$_]
    if ($null -eq $value) { $value = "" }
    $s = [string]$value
    '"' + ($s -replace '"', '""') + '"'
  }) -join ","
  Add-Content -LiteralPath $Path -Encoding UTF8 -Value $line
}

function Get-RelativePath([string]$Root, [string]$FullPath) {
  $rootFull = (Resolve-FullPath $Root).TrimEnd("\")
  $full = (Resolve-FullPath $FullPath)
  if ($full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
    $rel = $full.Substring($rootFull.Length).TrimStart("\")
    return $rel
  }
  return (Split-Path -Leaf $full)
}

function Get-VideoDurationSeconds([string]$InputPath, [string]$Ffprobe = "ffprobe") {
  $args = @(
    "-v", "quiet",
    "-print_format", "json",
    "-show_format",
    $InputPath
  )
  $p = Start-Process -FilePath $Ffprobe -ArgumentList $args -NoNewWindow -PassThru -Wait -RedirectStandardOutput "$env:TEMP\ffprobe_out.json" -RedirectStandardError "$env:TEMP\ffprobe_err.txt"
  if ($p.ExitCode -ne 0) { return $null }
  $obj = Get-Content -LiteralPath "$env:TEMP\ffprobe_out.json" -Raw -Encoding UTF8 | ConvertFrom-Json
  $duration = $obj.format.duration
  if ($null -eq $duration) { return $null }
  return [double]$duration
}

function Invoke-FfmpegEncode(
  [string]$InputPath,
  [string]$OutputPath,
  [int]$Crf,
  [string]$Ffmpeg = "ffmpeg"
) {
  $outDir = Split-Path -Parent $OutputPath
  New-Dir $outDir

  $tmp = "$OutputPath.tmp.mp4"
  if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }

  $args = @(
    "-hide_banner",
    "-y",
    "-i", $InputPath,
    "-map", "0",
    "-c:v", "libx264",
    "-preset", "veryfast",
    "-crf", "$Crf",
    "-pix_fmt", "yuv420p",
    "-c:a", "aac",
    "-b:a", "96k",
    "-movflags", "+faststart",
    $tmp
  )

  if ($DryRun) {
    Write-Host ("[DRYRUN] {0} {1}" -f $Ffmpeg, ($args -join " "))
    return @{ ok = $true; method = "dryrun_encode"; tmp = $tmp; exitCode = 0 }
  }

  $p = Start-Process -FilePath $Ffmpeg -ArgumentList $args -NoNewWindow -PassThru -Wait
  if ($p.ExitCode -ne 0) {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    return @{ ok = $false; method = "encode_failed"; tmp = $tmp; exitCode = $p.ExitCode }
  }

  Move-Item -LiteralPath $tmp -Destination $OutputPath -Force
  return @{ ok = $true; method = "h264_crf_$Crf"; tmp = $null; exitCode = 0 }
}

function Invoke-FfmpegSegmentCopy(
  [string]$InputPath,
  [string]$OutputDir,
  [int]$SegmentSeconds,
  [string]$BaseName,
  [string]$Ffmpeg = "ffmpeg"
) {
  New-Dir $OutputDir
  $pattern = Join-Path $OutputDir ("{0}.part%03d.mp4" -f $BaseName)

  $args = @(
    "-hide_banner",
    "-y",
    "-i", $InputPath,
    "-map", "0",
    "-c", "copy",
    "-f", "segment",
    "-segment_time", "$SegmentSeconds",
    "-reset_timestamps", "1",
    $pattern
  )

  if ($DryRun) {
    Write-Host ("[DRYRUN] {0} {1}" -f $Ffmpeg, ($args -join " "))
    return @{ ok = $true; outputs = @($pattern) }
  }

  $p = Start-Process -FilePath $Ffmpeg -ArgumentList $args -NoNewWindow -PassThru -Wait
  if ($p.ExitCode -ne 0) {
    return @{ ok = $false; outputs = @(); exitCode = $p.ExitCode }
  }

  $outs = Get-ChildItem -LiteralPath $OutputDir -Filter ("{0}.part*.mp4" -f $BaseName) | Sort-Object Name | ForEach-Object { $_.FullName }
  return @{ ok = $true; outputs = $outs; exitCode = 0 }
}

function Get-VideoQueue([string]$ArchiveRoot, [string]$VideoListPath) {
  $exts = @(".mp4", ".m4v", ".mov", ".mkv", ".avi", ".webm")
  if ($VideoListPath -and (Test-Path -LiteralPath $VideoListPath)) {
    $lines = Get-Content -LiteralPath $VideoListPath -Encoding UTF8 | Where-Object { $_ -and ($_ -notmatch "^\s*#") }
    $paths = @()
    foreach ($line in $lines) {
      $p = $line.Trim()
      if (-not $p) { continue }
      if ($p -match "^[A-Za-z]:\\") {
        $paths += $p
      } else {
        $paths += (Join-Path $ArchiveRoot $p)
      }
    }
    return $paths
  }

  $root = Resolve-FullPath $ArchiveRoot
  $files = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } |
    Sort-Object FullName
  return $files | ForEach-Object { $_.FullName }
}

$archive = Resolve-FullPath $ArchiveRoot
$experiment = Resolve-FullPath $ExperimentRoot

if (-not (Test-Command "ffmpeg")) { throw "ffmpeg not found on PATH. Install ffmpeg and retry." }
if (-not (Test-Command "ffprobe")) { throw "ffprobe not found on PATH. Install ffmpeg (includes ffprobe) and retry." }

$ffmpegVer = (& ffmpeg -version 2>$null | Select-Object -First 1)
$ffprobeVer = (& ffprobe -version 2>$null | Select-Object -First 1)
Write-Host ("ffmpeg:  {0}" -f $ffmpegVer)
Write-Host ("ffprobe: {0}" -f $ffprobeVer)

if ($SelfTest) {
  Write-Host "SelfTest OK (tools found)."
  Write-Host "Next: re-run without -SelfTest (and optionally with -DryRun)."
  exit 0
}

if (-not (Test-Path -LiteralPath $archive)) { throw "ARCHIVE not found: $archive" }
New-Dir $experiment

$logsDir = Join-Path $experiment "_logs"
New-Dir $logsDir

$inventoryCsv = Join-Path $logsDir "video_inventory.csv"
$manifestCsv = Join-Path $logsDir "video_processing_manifest.csv"
$checkpointPath = Join-Path $logsDir "checkpoint.json"

$manifestHeader = @(
  "queue_index",
  "source_path",
  "rel_path",
  "source_size_bytes",
  "dest_paths_json",
  "dest_total_size_bytes",
  "max_source_mb",
  "action",
  "method",
  "crf",
  "attempt",
  "status",
  "error",
  "started_utc",
  "ended_utc"
)

$queue = Get-VideoQueue -ArchiveRoot $archive -VideoListPath $VideoListPath
if ($queue.Count -eq 0) { throw "No videos found in queue." }

# Build or refresh inventory (stable order)
if (-not (Test-Path -LiteralPath $inventoryCsv)) {
  "queue_index,source_path,rel_path,source_size_bytes" | Out-File -LiteralPath $inventoryCsv -Encoding UTF8 -Force
  for ($i = 0; $i -lt $queue.Count; $i++) {
    $src = $queue[$i]
    $rel = Get-RelativePath -Root $archive -FullPath $src
    $size = (Get-Item -LiteralPath $src).Length
    ('{0},"{1}","{2}",{3}' -f ($i + 1), ($src -replace '"','""'), ($rel -replace '"','""'), $size) | Add-Content -LiteralPath $inventoryCsv -Encoding UTF8
  }
}

# Load manifest status map (success only)
$successMap = @{}
if (Test-Path -LiteralPath $manifestCsv) {
  try {
    $rows = Import-Csv -LiteralPath $manifestCsv
    foreach ($r in $rows) {
      if ($r.status -eq "success") {
        $successMap[$r.source_path] = $true
      }
    }
  } catch {
    Write-Warning "Failed to parse existing manifest; will continue without success map: $($_.Exception.Message)"
  }
}

$checkpoint = $null
if ($Resume) { $checkpoint = Read-JsonFile -Path $checkpointPath }

$startIndex = 1
if ($checkpoint -and $checkpoint.next_queue_index) { $startIndex = [int]$checkpoint.next_queue_index }
if ($StartAfter -gt 0) { $startIndex = [Math]::Max($startIndex, $StartAfter + 1) }

$maxBytes = $MaxSourceMB * 1024 * 1024

Write-Host ("Queue size: {0} videos" -f $queue.Count)
Write-Host ("Starting at queue index: {0} (StartAfter={1}, Resume={2})" -f $startIndex, $StartAfter, [bool]$Resume)
Write-Host ("Max per output: {0} MB" -f $MaxSourceMB)
Write-Host ("Logs: {0}" -f $logsDir)

$failures = 0
$processed = 0
$skipped = 0
$succeeded = 0

for ($idx = $startIndex; $idx -le $queue.Count; $idx++) {
  $src = $queue[$idx - 1]
  $rel = Get-RelativePath -Root $archive -FullPath $src
  $destBase = Join-Path $experiment $rel
  $destBaseDir = Split-Path -Parent $destBase
  New-Dir $destBaseDir

  if ($successMap.ContainsKey($src)) {
    $skipped++
    $checkpointObj = @{
      next_queue_index = $idx + 1
      updated_utc = ([DateTime]::UtcNow.ToString("o"))
      summary = @{ processed = $processed; success = $succeeded; skipped = $skipped; failed = $failures; total = $queue.Count }
    }
    Write-JsonFile -Path $checkpointPath -Obj $checkpointObj
    continue
  }

  $sourceItem = Get-Item -LiteralPath $src -ErrorAction Stop
  $sourceSize = [int64]$sourceItem.Length

  Write-Host ("[{0}/{1}] {2}" -f $idx, $queue.Count, $rel)
  Start-Sleep -Milliseconds $ThrottleMs

  $startedUtc = [DateTime]::UtcNow.ToString("o")
  $status = "failed"
  $error = ""
  $method = ""
  $crfUsed = ""
  $destPaths = @()
  $destTotal = 0

  try {
    if ($sourceSize -le $maxBytes) {
      $out = $destBase
      if ($DryRun) {
        Write-Host ("[DRYRUN] Copy {0} -> {1}" -f $src, $out)
      } else {
        Copy-Item -LiteralPath $src -Destination $out -Force
      }
      $destPaths = @($out)
      $destTotal = $sourceSize
      $method = "copy_under_limit"
      $status = "success"
    } else {
      # Encode to a single output first, then enforce size; optionally split if still too large.
      $encoded = ([IO.Path]::ChangeExtension($destBase, ".mp4"))
      $attempt = 0
      $ok = $false

      for ($crf = $MinCrf; $crf -le $MaxCrf; $crf += 2) {
        $attempt++
        $encodeTry = 0
        while ($encodeTry -le $Retries) {
          $encodeTry++
          $res = Invoke-FfmpegEncode -InputPath $src -OutputPath $encoded -Crf $crf -Ffmpeg "ffmpeg"
          if (-not $res.ok) {
            if ($encodeTry -le $Retries) { Start-Sleep -Seconds 2; continue }
            throw ("ffmpeg encode failed (exit={0})" -f $res.exitCode)
          }

          if ($DryRun) {
            $ok = $true
            $method = $res.method
            $crfUsed = "$crf"
            break
          }

          $outSize = (Get-Item -LiteralPath $encoded).Length
          if ($outSize -le $maxBytes) {
            $ok = $true
            $method = $res.method
            $crfUsed = "$crf"
            $destPaths = @($encoded)
            $destTotal = [int64]$outSize
            break
          }

          Remove-Item -LiteralPath $encoded -Force
          break
        }

        if ($ok) { break }
      }

      if (-not $ok) {
        # Last-resort: encode at MaxCrf and split by duration.
        if (-not $AllowSplit) {
          throw "Could not compress under limit (AllowSplit disabled)."
        }

        $res2 = Invoke-FfmpegEncode -InputPath $src -OutputPath $encoded -Crf $MaxCrf -Ffmpeg "ffmpeg"
        if (-not $res2.ok) { throw ("ffmpeg encode failed (exit={0})" -f $res2.exitCode) }

        if (-not $DryRun) {
          $outSize2 = (Get-Item -LiteralPath $encoded).Length
          if ($outSize2 -le $maxBytes) {
            $destPaths = @($encoded)
            $destTotal = [int64]$outSize2
            $method = $res2.method
            $crfUsed = "$MaxCrf"
            $ok = $true
          } else {
            $dur = Get-VideoDurationSeconds -InputPath $encoded -Ffprobe "ffprobe"
            if ($null -eq $dur -or $dur -le 0) { throw "Cannot determine duration for splitting." }
            $parts = [Math]::Ceiling($outSize2 / $maxBytes)
            $segmentSeconds = [int][Math]::Ceiling($dur / $parts)
            $baseName = ([IO.Path]::GetFileNameWithoutExtension($encoded))
            $segDir = Join-Path $destBaseDir ($baseName + "_parts")

            $seg = Invoke-FfmpegSegmentCopy -InputPath $encoded -OutputDir $segDir -SegmentSeconds $segmentSeconds -BaseName $baseName -Ffmpeg "ffmpeg"
            if (-not $seg.ok) { throw ("ffmpeg segment failed (exit={0})" -f $seg.exitCode) }

            $destPaths = @($seg.outputs)
            $destTotal = ($destPaths | ForEach-Object { (Get-Item -LiteralPath $_).Length } | Measure-Object -Sum).Sum
            $method = "h264_crf_$MaxCrf_then_segment_${segmentSeconds}s"
            $crfUsed = "$MaxCrf"
            Remove-Item -LiteralPath $encoded -Force
            $ok = $true
          }
        } else {
          $destPaths = @($encoded)
          $destTotal = 0
          $method = "dryrun_encode_then_segment"
          $crfUsed = "$MaxCrf"
          $ok = $true
        }
      }

      $status = $ok ? "success" : "failed"
    }
  } catch {
    $error = $_.Exception.Message
    $failures++
    if ($failures -ge $MaxFailures) {
      Write-Warning "MaxFailures reached ($MaxFailures); stopping."
    }
  }

  $endedUtc = [DateTime]::UtcNow.ToString("o")
  $processed++
  if ($status -eq "success") { $succeeded++ }

  $row = @{
    queue_index = $idx
    source_path = $src
    rel_path = $rel
    source_size_bytes = $sourceSize
    dest_paths_json = ($destPaths | ConvertTo-Json -Compress)
    dest_total_size_bytes = $destTotal
    max_source_mb = $MaxSourceMB
    action = "process"
    method = $method
    crf = $crfUsed
    attempt = ""
    status = $status
    error = $error
    started_utc = $startedUtc
    ended_utc = $endedUtc
  }
  Csv-AppendRow -Path $manifestCsv -Row $row -Header $manifestHeader

  $checkpointObj = @{
    next_queue_index = $idx + 1
    updated_utc = ([DateTime]::UtcNow.ToString("o"))
    summary = @{ processed = $processed; success = $succeeded; skipped = $skipped; failed = $failures; total = $queue.Count }
  }
  Write-JsonFile -Path $checkpointPath -Obj $checkpointObj

  if ($failures -ge $MaxFailures) { break }
}

Write-Host ""
Write-Host "Done."
Write-Host ("Processed this run: {0} | Success: {1} | Skipped: {2} | Failed: {3} | Total queue: {4}" -f $processed, $succeeded, $skipped, $failures, $queue.Count)
Write-Host ("Manifest: {0}" -f $manifestCsv)
Write-Host ("Checkpoint: {0}" -f $checkpointPath)
