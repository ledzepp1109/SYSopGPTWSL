[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Capture-External {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter()][string[]]$Args = @()
    )

    $output = ""
    $exitCode = $null
    $errorMessage = $null

    try {
        $output = (& $Command @Args 2>&1 | Out-String).TrimEnd()
        $exitCode = $LASTEXITCODE
    }
    catch {
        $errorMessage = $_.Exception.Message
    }

    [pscustomobject]@{
        command     = if ($Args.Count -gt 0) { "$Command $($Args -join ' ')" } else { $Command }
        exit_code   = $exitCode
        output      = $output
        error       = $errorMessage
    }
}

function Try-Cim {
    param(
        [Parameter(Mandatory = $true)][string]$ClassName,
        [Parameter()][string]$Namespace = "root/cimv2",
        [Parameter()][string[]]$Select = @()
    )

    $data = $null
    $errorMessage = $null
    try {
        $query = Get-CimInstance -Namespace $Namespace -ClassName $ClassName
        if ($Select.Count -gt 0) {
            $data = $query | Select-Object -Property $Select
        }
        else {
            $data = $query
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
    }

    [pscustomobject]@{
        class = $ClassName
        namespace = $Namespace
        data = $data
        error = $errorMessage
    }
}

function Try-Registry {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $data = $null
    $errorMessage = $null
    try {
        $data = Get-ItemProperty -Path $Path | Select-Object -Property *
    }
    catch {
        $errorMessage = $_.Exception.Message
    }

    [pscustomobject]@{
        path = $Path
        data = $data
        error = $errorMessage
    }
}

$collectedAt = (Get-Date).ToString("o")
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$outDir = Join-Path $repoRoot "sysop-report\windows"
$null = New-Item -ItemType Directory -Force -Path $outDir

$outTxt = Join-Path $outDir "snapshot.txt"
$outJson = Join-Path $outDir "snapshot.json"

$cpu = Try-Cim -ClassName "Win32_Processor" -Select @(
    "Name", "Manufacturer", "NumberOfCores", "NumberOfLogicalProcessors", "MaxClockSpeed", "CurrentClockSpeed"
)
$computerSystem = Try-Cim -ClassName "Win32_ComputerSystem" -Select @(
    "Manufacturer", "Model", "TotalPhysicalMemory"
)
$bios = Try-Cim -ClassName "Win32_BIOS" -Select @(
    "Manufacturer", "SMBIOSBIOSVersion", "ReleaseDate", "SerialNumber"
)
$os = Try-Cim -ClassName "Win32_OperatingSystem" -Select @(
    "Caption", "Version", "BuildNumber", "OSArchitecture"
)
$gpu = Try-Cim -ClassName "Win32_VideoController" -Select @(
    "Name", "DriverVersion"
)

$powercfgList = Capture-External -Command "powercfg" -Args @("/L")
$powercfgActive = Capture-External -Command "powercfg" -Args @("/GETACTIVESCHEME")
$powercfgSleep = Capture-External -Command "powercfg" -Args @("/A")

$powercfgThrottleMin = Capture-External -Command "powercfg" -Args @("/Q", "SCHEME_CURRENT", "SUB_PROCESSOR", "PROCTHROTTLEMIN")
$powercfgThrottleMax = Capture-External -Command "powercfg" -Args @("/Q", "SCHEME_CURRENT", "SUB_PROCESSOR", "PROCTHROTTLEMAX")
$powercfgBoostMode = Capture-External -Command "powercfg" -Args @("/Q", "SCHEME_CURRENT", "SUB_PROCESSOR", "PERFBOOSTMODE")
$powerThrottlingReg = Try-Registry -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling"

$physicalDisks = $null
$physicalDisksError = $null
try {
    if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        $physicalDisks = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, Size, HealthStatus
    }
    else {
        $physicalDisksError = "Get-PhysicalDisk not available"
    }
}
catch {
    $physicalDisksError = $_.Exception.Message
}

$volumes = $null
$volumesError = $null
try {
    if (Get-Command Get-Volume -ErrorAction SilentlyContinue) {
        $volumes = Get-Volume | Select-Object DriveLetter, FileSystem, Size, SizeRemaining, HealthStatus
    }
    else {
        $volumesError = "Get-Volume not available"
    }
}
catch {
    $volumesError = $_.Exception.Message
}

$wslStatus = Capture-External -Command "wsl" -Args @("--status")
$wslVersion = Capture-External -Command "wsl" -Args @("--version")
$wslList = Capture-External -Command "wsl" -Args @("-l", "-v")

$snapshot = [ordered]@{
    collected_at = $collectedAt
    repo_root = $repoRoot
    windows = [ordered]@{
        os = $os
        cpu = $cpu
        computer_system = $computerSystem
        bios = $bios
        gpu = $gpu
        storage = [ordered]@{
            physical_disks = $physicalDisks
            physical_disks_error = $physicalDisksError
            volumes = $volumes
            volumes_error = $volumesError
        }
        power = [ordered]@{
            powercfg_list = $powercfgList
            powercfg_active_scheme = $powercfgActive
            powercfg_sleep_states = $powercfgSleep
            throttle_min = $powercfgThrottleMin
            throttle_max = $powercfgThrottleMax
            boost_mode = $powercfgBoostMode
            power_throttling_registry = $powerThrottlingReg
        }
        wsl = [ordered]@{
            status = $wslStatus
            version = $wslVersion
            list = $wslList
        }
    }
}

$txtLines = New-Object System.Collections.Generic.List[string]
$txtLines.Add("SYSopGPTWSL Windows Snapshot")
$txtLines.Add("CollectedAt: $collectedAt")
$txtLines.Add("RepoRoot: $repoRoot")
$txtLines.Add("")

$txtLines.Add("== CPU ==")
$txtLines.Add(($cpu.data | Format-List | Out-String).TrimEnd())
$txtLines.Add("")

$txtLines.Add("== RAM / ComputerSystem ==")
$txtLines.Add(($computerSystem.data | Format-List | Out-String).TrimEnd())
$txtLines.Add("")

$txtLines.Add("== BIOS ==")
$txtLines.Add(($bios.data | Format-List | Out-String).TrimEnd())
$txtLines.Add("")

$txtLines.Add("== OS ==")
$txtLines.Add(($os.data | Format-List | Out-String).TrimEnd())
$txtLines.Add("")

$txtLines.Add("== GPU ==")
$txtLines.Add(($gpu.data | Format-Table -AutoSize | Out-String).TrimEnd())
$txtLines.Add("")

$txtLines.Add("== Power ==")
$txtLines.Add("[powercfg /GETACTIVESCHEME]")
$txtLines.Add($powercfgActive.output)
$txtLines.Add("")
$txtLines.Add("[powercfg /L]")
$txtLines.Add($powercfgList.output)
$txtLines.Add("")
$txtLines.Add("[powercfg /A]")
$txtLines.Add($powercfgSleep.output)
$txtLines.Add("")
$txtLines.Add("[powercfg /Q SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN]")
$txtLines.Add($powercfgThrottleMin.output)
$txtLines.Add("")
$txtLines.Add("[powercfg /Q SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX]")
$txtLines.Add($powercfgThrottleMax.output)
$txtLines.Add("")
$txtLines.Add("[powercfg /Q SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE]")
$txtLines.Add($powercfgBoostMode.output)
$txtLines.Add("")
$txtLines.Add("== PowerThrottling registry ==")
if ($powerThrottlingReg.error) {
    $txtLines.Add("ERROR: $($powerThrottlingReg.error)")
}
else {
    $txtLines.Add(($powerThrottlingReg.data | Format-List | Out-String).TrimEnd())
}
$txtLines.Add("")

$txtLines.Add("== Storage ==")
if ($physicalDisksError) {
    $txtLines.Add("PhysicalDisk: ERROR: $physicalDisksError")
}
elseif ($physicalDisks) {
    $txtLines.Add(($physicalDisks | Format-Table -AutoSize | Out-String).TrimEnd())
}
$txtLines.Add("")

if ($volumesError) {
    $txtLines.Add("Volume: ERROR: $volumesError")
}
elseif ($volumes) {
    $txtLines.Add(($volumes | Format-Table -AutoSize | Out-String).TrimEnd())
}
$txtLines.Add("")

$txtLines.Add("== WSL ==")
$txtLines.Add("[wsl --status]")
$txtLines.Add($wslStatus.output)
$txtLines.Add("")
$txtLines.Add("[wsl --version]")
$txtLines.Add($wslVersion.output)
$txtLines.Add("")
$txtLines.Add("[wsl -l -v]")
$txtLines.Add($wslList.output)
$txtLines.Add("")

Set-Content -Path $outTxt -Value $txtLines -Encoding UTF8
$snapshot | ConvertTo-Json -Depth 7 | Set-Content -Path $outJson -Encoding UTF8

Write-Output "Wrote: $outTxt"
Write-Output "Wrote: $outJson"
