param(
    [ValidateSet('cpu16','cpu32','gpu16','gpu32')]
    [string] $Profile = 'cpu16',
    [ValidateSet('stationary_180s','straight_18mps_600s','turns_18mps_300s','out_and_back_18mps_300s')]
    [string] $Route = 'out_and_back_18mps_300s',
    [double] $Duration = -1,
    [double] $Warmup = 45,
    [switch] $Campaign,
    [ValidateRange(1,10)] [int] $Repeats = 3,
    [switch] $Headless,
    [switch] $CiSmoke,
    [switch] $Capture
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$exe = Join-Path $root '.tools/godot.exe'
$project = Join-Path $root 'godot'
if (-not (Test-Path $exe)) { throw 'Missing pinned Godot; run bootstrap-windows.ps1 -RuntimeOnly' }
if (-not (Test-Path (Join-Path $project 'bin/sandbox_native.windows.template_debug.x86_64.dll'))) {
    throw 'Missing native A3 DLL; use the compiled A5 checkout or bootstrap-windows.ps1 -SkipDownload'
}
if ($Headless -and -not $CiSmoke) { throw 'A6 graphics/GPU evaluation cannot run headless; use -Headless only with -CiSmoke' }
if ($CiSmoke -and (-not $Headless -or $Campaign -or $Profile -like 'gpu*')) {
    throw 'A6 CiSmoke accepts only one CPU arm in headless mode'
}
if ($Capture -and $Campaign) { throw 'Screenshots change workload; run evidence capture separately, not in an A/B campaign' }
$nominal = switch ($Route) {
    'stationary_180s' { 180 }
    'straight_18mps_600s' { 600 }
    'turns_18mps_300s' { 300 }
    'out_and_back_18mps_300s' { 300 }
}
if ($Duration -le 0) { $Duration = $nominal }
if ($Duration -gt $nominal -or $Warmup -lt 0 -or $Warmup -gt 180) {
    throw 'Duration or warmup outside route contract'
}
if ($CiSmoke -and ($Duration -gt 10 -or $Warmup -gt 10)) {
    throw 'Headless smoke limited to 10s and is not a performance test'
}
$cache = Join-Path $project '.godot'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
[System.IO.File]::WriteAllText(
    (Join-Path $cache 'extension_list.cfg'),
    "res://sandbox_native.gdextension" + [Environment]::NewLine,
    (New-Object System.Text.UTF8Encoding($false))
)
$timeId = (Get-Date -Format 'yyyyMMdd-HHmmss')
$outputRoot = if ($env:A6_OUTPUT_DIR) { $env:A6_OUTPUT_DIR } else {
    Join-Path $root "reports/generated/a6/experiment-$timeId-$PID"
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$profiles = if ($Campaign) { @('cpu16','gpu16','cpu32','gpu32') } else { @($Profile) }
$repetitions = if ($Campaign) { $Repeats } else { 1 }
$quoted = '"' + $project + '"'
$commit = 'unknown'
try { $commit = (& git -C $root rev-parse HEAD 2>$null).Trim() } catch {}
$hostInfo = @{
    schema = 'a6_campaign_v1'; commit = $commit; timestamp_utc = [DateTime]::UtcNow.ToString('o')
    processor = $env:PROCESSOR_IDENTIFIER; os = [Environment]::OSVersion.VersionString
    route = $Route; duration_sec = $Duration; warmup_sec = $Warmup
    repeats = $repetitions; view_distance_m = 192; lod_count = 4; lod_distance_m = 48
    renderer = if ($Headless) { 'headless_cpu_smoke_ONLY' } else { 'forward_plus_vulkan' }
    gate = 'NOT_QUALIFIED: no full CPU+GPU+present or pixel coverage test'
}
($hostInfo | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath (Join-Path $outputRoot 'manifest.json') -Encoding UTF8

for ($rep = 1; $rep -le $repetitions; $rep++) {
    # Reverse order every other repetition to reduce thermal/order bias.
    $ordered = @($profiles)
    if ($Campaign -and ($rep % 2 -eq 0)) { [array]::Reverse($ordered) }
    foreach ($variant in $ordered) {
        $destination = Join-Path $outputRoot ("{0}_rep{1:d2}" -f $variant,$rep)
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        $env:A2_OUTPUT_DIR = $destination
        # Every run starts with its own empty save; never compare warm cached
        # SQLite in one arm with cold generated terrain in another.
        $env:A3_SAVE_PATH = Join-Path $destination 'world.sqlite'
        $env:A4_ROCK_STATE_PATH = Join-Path $destination 'rocks.json'
        $argsList = @()
        if ($Headless) { $argsList += '--headless' } else {
            $argsList += @('--rendering-method','forward_plus','--rendering-driver','vulkan')
        }
        $argsList += @('--path', $quoted, '--script', 'res://tests/a6_benchmark.gd', '--',
                       "--profile=$variant", "--route=$Route",
                       "--duration=$Duration", "--warmup=$Warmup")
        if ($CiSmoke) { $argsList += '--ci-smoke' }
        if ($Capture) { $argsList += '--capture' }
        Write-Host "A6: variant=$variant repetition=$rep/$repetitions route=$Route time=$Duration warmup=$Warmup reports=$destination"
        $p = Start-Process -FilePath $exe -ArgumentList $argsList -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -ne 0) {
            throw "A6_PROFILE_FAIL variant=$variant exit=$($p.ExitCode); inspect Godot logs. Baseline unchanged."
        }
        $reports = @(Get-ChildItem -LiteralPath $destination -Filter '*.json' -File)
        if ($reports.Count -ne 1) { throw "A6 expected exactly one JSON summary for $variant" }
        $d = Get-Content -LiteralPath $reports[0].FullName -Raw | ConvertFrom-Json
        $expectedMesh = if ($variant.EndsWith('32')) { 32 } else { 16 }
        $expectedGPU = $variant.StartsWith('gpu')
        if ($d.a6_profile -ne $variant -or $d.mesh_block_size -ne $expectedMesh -or
            $d.a6_gpu_requested -ne $expectedGPU -or $d.view_distance_m -ne 192 -or
            $d.lod_distance_m -ne 48 -or $d.frame_intervals_observed -le 0) {
            throw "A6_REPORT_FAIL mismatched profile/coverage or empty trace for $variant"
        }
        if (-not $Headless -and ($d.rendering_method_actual -ne 'forward_plus' -or
            $d.rendering_driver_actual -ne 'vulkan' -or $d.viewport_render_gpu_samples -le 0)) {
            throw "A6_RENDER_FAIL Vulkan/GPU timing not active for $variant"
        }
        Write-Host "A6_RUN_PASS variant=$variant p99_interval_ms=$($d.frame_interval_ms_p99) render_gpu_p99_ms=$($d.viewport_render_gpu_p99_ms)"
    }
}
Write-Host "A6_REPORTS_READY=$outputRoot"
Write-Host 'A6_NO_AUTOPROMOTION: compare results and graphical/presented-frame evidence before choosing candidate.'
