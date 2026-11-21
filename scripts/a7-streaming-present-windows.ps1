param(
    [string] $PresentMonExe,
    [int] $Seed = 20261119,
    [ValidateRange(20,120)] [int] $Warmup = 45,
    [switch] $FastSmoke
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runner = Join-Path $root 'scripts/a7-run-windows.ps1'
$reporter = Join-Path $root 'scripts/a7_streaming_present_report.py'
$presentMonHash = 'B2A706BC6AD475749E3B7E3409263AA1E6906D45BDCF993F6DBC0F660188F1AF'
if (-not $PresentMonExe -or -not (Test-Path -LiteralPath $PresentMonExe)) {
    throw 'A7_PRESENTMON_REQUIRED: verified Intel PresentMon 2.6.0 standalone exe is mandatory for the paired stress diagnostics'
}
if ((Get-FileHash -LiteralPath $PresentMonExe -Algorithm SHA256).Hash -ne $presentMonHash) {
    throw 'A7_PRESENTMON_HASH_MISMATCH: external executable does not match the pinned release'
}
if ([System.Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0) {
    throw 'A7_STREAMING_REQUIRES_INTERACTIVE_DESKTOP (Session 0 is not acceptable)'
}
$gpu = @(Get-CimInstance Win32_VideoController | ForEach-Object Name)
if ($env:COMPUTERNAME -ne 'DESKTOP-SAFGO15' -or -not ($gpu -contains 'NVIDIA GeForce GTX 1050 Ti')) {
    throw 'A7_STREAMING_HOST_MISMATCH: A7 baseline requires DESKTOP-SAFGO15 and NVIDIA GTX 1050 Ti'
}

# A5/CPU16 unchanged; same seed, automatic VoxelEngine worker count,
# all telemetry enabled in both arms. Higher sustained streaming stress.
$routes = @(
    [pscustomobject]@{name='straight_18mps_600s'; duration=300},
    [pscustomobject]@{name='turns_18mps_300s'; duration=180},
    [pscustomobject]@{name='rocks_water_180s'; duration=180},
    [pscustomobject]@{name='shoreline_180s'; duration=180}
)
if ($FastSmoke) {
    $routes = @([pscustomobject]@{name='shoreline_180s'; duration=30})
    $Warmup = 20
}
$campaign = Join-Path $root ('reports/generated/a7-streaming-present/campaign-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$PID")
New-Item -ItemType Directory -Force -Path $campaign | Out-Null
$previous = $env:A7_CAMPAIGN_DIR
$manifest = [ordered]@{
    schema='a7_streaming_present_manifest_v1'
    git_sha=(& git -C $root rev-parse HEAD).Trim()
    baseline='A5 CPU16 GL Compatibility, VoxelEngine automatic workers'
    presentmon_version='2.6.0'
    presentmon_sha256=$presentMonHash.ToLowerInvariant()
    display_target='1920x1080 window'
    gpu_expected='NVIDIA GeForce GTX 1050 Ti'
    speed_mps=18
    warmup_s=$Warmup
    seed=$Seed
    routes=@($routes)
    process_telemetry_sample_period_s=1
    diagnostics='identical process and ETW instrumentation for both VSync arms'
    strict_acceptance='NOT_QUALIFIED'
    runs=@()
}
$seq=0
try {
    foreach ($route in $routes) {
        # Alternate which arm runs first by route, without changing the game.
        $arms = if ($FastSmoke) { @('on') } elseif ($seq % 2 -eq 0) { @('on','off') } else { @('off','on') }
        foreach ($arm in $arms) {
            $seq++
            $label = "s{0:D2}_{1}_{2}" -f $seq,$route.name,("vsync_"+$arm)
            $target = Join-Path $campaign $label
            $env:A7_CAMPAIGN_DIR = $target
            $row = [ordered]@{
                sequence=$seq; directory=$label; profile=("vsync_"+$arm)
                route=$route.name; duration_s=$route.duration
                seed=$Seed; voxel_threads_requested=0
            }
            $manifest.runs += $row
            $manifest | ConvertTo-Json -Depth 8 |
                Set-Content -LiteralPath (Join-Path $campaign 'streaming_manifest.json') -Encoding UTF8
            Write-Host "A7_STREAM_PRESENT_START sequence=$seq profile=$($row.profile) route=$($route.name) seconds=$($route.duration)"
            $params = @{
                Scenario=$route.name
                Seeds=@($Seed)
                Warmup=[double]$Warmup
                Duration=[double]$route.duration
                VsyncOff=($arm -eq 'off')
                ResourceTelemetry=$true
                VoxelThreads=0
                PresentMonExe=$PresentMonExe
            }
            & $runner @params
            if (-not $?) { throw "A7_STREAMING_CHILD_FAILED $label" }
            $pmStatusPath = Get-ChildItem -LiteralPath $target -Recurse -File -Filter 'a7_presentmon_status.json' |
                Select-Object -First 1
            if ($null -eq $pmStatusPath) { throw "A7_PRESENTMON_STATUS_MISSING $label" }
            $pm = Get-Content -LiteralPath $pmStatusPath.FullName -Raw | ConvertFrom-Json
            if (-not $pm.collection_started -or $pm.exit_code -ne 0 -or $pm.csv_bytes -lt 1024) {
                throw "A7_PRESENTMON_CAPTURE_FAILED $label exit=$($pm.exit_code) csv_bytes=$($pm.csv_bytes) error=$($pm.capture_error)"
            }
            Write-Host "A7_STREAM_PRESENT_CAPTURED $label csv_bytes=$($pm.csv_bytes) etw_session=$($pm.etw_session_name)"
        }
    }
    & python $reporter $campaign
    if ($LASTEXITCODE -ne 0) { throw 'A7_STREAMING_REPORT_FAILED' }
    $comparison = Get-Content -LiteralPath (Join-Path $campaign 'streaming_comparison.json') -Raw | ConvertFrom-Json
    if ($FastSmoke -and $comparison.etw_aligned_count -ne $comparison.route_count) {
        throw "A7_PRESENTMON_PREFLIGHT_NOT_ALIGNED: $($comparison.etw_aligned_count)/$($comparison.route_count); refusing longer GPU benchmark"
    }
    foreach ($run in $comparison.runs) {
        if ($run.presentation_status -ne 'ETW_ALIGNED') {
            Write-Warning "A7_ETW_NOT_QUALIFIED route=$($run.route) profile=$($run.profile) status=$($run.presentation_status) reason=$($run.reason)"
        }
    }
    Write-Host "A7_STREAMING_CAMPAIGN_DONE=$campaign"
    Write-Host "A7_STREAMING_ETW_ALIGNED=$($comparison.etw_aligned_count)/$($comparison.route_count)"
    Write-Host 'A7_STRICT_GATES_REMAIN_NOT_QUALIFIED'
} finally {
    $env:A7_CAMPAIGN_DIR = $previous
    # Preserve original ETW data in lossless compressed files for GitHub upload.
    # Avoid uploading uncompressed hundreds of MB of frame-level CSV.
    if (Test-Path -LiteralPath $campaign) {
        Get-ChildItem -LiteralPath $campaign -Recurse -Filter 'a7_presentmon.csv' -File | ForEach-Object {
            try {
                Compress-Archive -LiteralPath $_.FullName -DestinationPath ($_.FullName+'.zip') -CompressionLevel Optimal -Force
                Remove-Item -LiteralPath $_.FullName -Force
            } catch {
                Write-Warning "A7_PRESENTMON_ARCHIVE_WARNING $($_.Exception.Message)"
            }
        }
    }
}
