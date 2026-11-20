param(
    [ValidateSet(
        'stationary_180s','straight_18mps_600s','turns_18mps_300s',
        'out_and_back_18mps_300s','shoreline_180s','cave_180s',
        'rocks_water_180s','edit_idle_100','edit_moving_100',
        'boundary_edit_100','reopen_save'
    )]
    [string] $Scenario = 'out_and_back_18mps_300s',
    [int[]] $Seeds = @(20261119, 20261120, 20261121),
    [ValidateRange(1,10)] [int] $Repeats = 3,
    [double] $Warmup = 45,
    [double] $Duration = 0,
    [switch] $Full,
    [switch] $Capture,
    [switch] $CiSmoke
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$exe = Join-Path $root '.tools/godot.exe'
$project = Join-Path $root 'godot'
$dll = Join-Path $project 'bin/sandbox_native.windows.template_debug.x86_64.dll'
if (-not (Test-Path $exe) -or -not (Test-Path $dll)) {
    throw 'A7 requires pinned Godot + A3 native DLL (bootstrap-windows.ps1 -SkipDownload)'
}
if ($Capture -and $Full) {
    throw 'A7 refuses screenshot overhead inside comparable full performance campaign; use a separate -Capture evidence run'
}
if ($CiSmoke -and ($Full -or $Capture)) {
    throw 'Headless CI is only a short integration smoke'
}
if ($Seeds.Count -lt 1 -or (@($Seeds | Select-Object -Unique)).Count -ne $Seeds.Count) {
    throw 'A7 requires at least one unique seed'
}
$routes = @('stationary_180s','straight_18mps_600s','turns_18mps_300s',
            'out_and_back_18mps_300s','shoreline_180s','cave_180s','rocks_water_180s')
$edits = @('edit_idle_100','edit_moving_100','boundary_edit_100')
if ($Full -and ($Seeds.Count -lt 3 -or $Repeats -lt 3)) {
    throw 'A7 Full requires >=3 seeds and >=3 repeats per route; no silent workload downgrade'
}
if ($Full -and $Duration -ne 0) {
    throw 'A7 Full requires full canonical scenario durations'
}
$scenarios = if ($Full) { $routes + $edits } else { @($Scenario) }
$runSeeds = if ($Full) { $Seeds } else { @($Seeds[0]) }
$reps = if ($Full) { $Repeats } else { 1 }
if ($CiSmoke) { $Warmup = 0.3; $Duration = 1.5 }

$cache = Join-Path $project '.godot'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
[System.IO.File]::WriteAllText(
    (Join-Path $cache 'extension_list.cfg'),
    "res://sandbox_native.gdextension" + [Environment]::NewLine,
    (New-Object System.Text.UTF8Encoding($false))
)
$rootOutput = if ($env:A7_CAMPAIGN_DIR) { $env:A7_CAMPAIGN_DIR } else {
    Join-Path $root ('reports/generated/a7/campaign-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$PID")
}
if ($CiSmoke -and (Test-Path $rootOutput)) {
    Remove-Item -LiteralPath $rootOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $rootOutput -Force | Out-Null
$head = 'unknown'
try {
    $head = (& git -C $root rev-parse HEAD 2>$null).Trim()
} catch { }
$adapter = @()
try {
    $adapter = @(Get-CimInstance Win32_VideoController |
        Select-Object Name, DriverVersion, VideoProcessor, AdapterRAM)
} catch { }
$manifest = [ordered]@{
    schema='a7_campaign_v1'; started_utc=[DateTime]::UtcNow.ToString('o')
    git_sha=$head; baseline_checkpoint='0c3fee959576d0a1faec9ceecffb4b132a65558b'
    baseline='A5 CPU16 GL Compatibility'; full=[bool]$Full
    ci_smoke=[bool]$CiSmoke; capture=[bool]$Capture
    target_resolution='1920x1080'; target_speed_mps=18.0
    requested_view_distance_m=192; visual_radius_target_m=130
    mesh_block_voxels=16; lod_count=4; lod_distance=48
    seeds=@($runSeeds); repeats=$reps; scenarios=@($scenarios)
    warmup_s=$Warmup; duration_override_s=$Duration
    windows_version=[Environment]::OSVersion.VersionString
    cpu=$env:PROCESSOR_IDENTIFIER; gpu=@($adapter)
    notes='Main-game A5 is unmodified; CI and frame intervals cannot prove full GPU+present, pixels or EDIT-100.'
}
($manifest | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $rootOutput 'manifest.json') -Encoding UTF8
$quotedProject = '"' + $project + '"'
$expected = 0
foreach ($name in $scenarios) {
    if ($name -eq 'reopen_save') {
        if ($Full) { throw 'Reopen functional integration is separately gated by A3-A5; Full only includes timed routes and edits' }
        foreach ($script in @('a3-smoke-windows.ps1','a4-smoke-windows.ps1','a5-smoke-windows.ps1')) {
            & (Join-Path $root "scripts/$script")
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "A7_REOPEN_REGRESSION_FAIL $script" }
        }
        Write-Host 'A7_REOPEN_FUNCTIONAL_SMOKES_PASS (fixed seed 20261119)'
        continue
    }
    foreach ($seed in $runSeeds) {
        for ($r = 1; $r -le $reps; $r++) {
            $folder = Join-Path $rootOutput ('{0}_seed{1}_rep{2:D2}' -f $name,$seed,$r)
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            $env:A7_OUTPUT_DIR = $folder
            $env:A3_SAVE_PATH = Join-Path $folder 'world.sqlite'
            $env:A4_ROCK_STATE_PATH = Join-Path $folder 'rocks.json'
            $isEdit = $edits -contains $name
            $script = if ($isEdit) { 'res://tests/a7_edit_runner.gd' } else { 'res://tests/a7_route_runner.gd' }
            $argsList = @()
            if ($CiSmoke) {
                $argsList += '--headless'
            } else {
                $argsList += @('--rendering-method','gl_compatibility','--rendering-driver','opengl3')
            }
            $argsList += @('--path',$quotedProject,'--script',$script,'--')
            if ($isEdit) {
                $count = if ($CiSmoke) { 2 } else { 100 }
                $argsList += @("--scenario=$name","--seed=$seed","--warmup=$Warmup","--count=$count")
            } else {
                $argsList += @("--route=$name","--seed=$seed","--warmup=$Warmup")
                if ($Duration -gt 0) { $argsList += "--duration=$Duration" }
            }
            if ($Capture) { $argsList += '--capture' }
            if ($CiSmoke) { $argsList += '--ci-smoke' }
            Write-Host "A7_START scenario=$name seed=$seed rep=$r/$reps output=$folder"
            $p = Start-Process -FilePath $exe -ArgumentList $argsList -PassThru -Wait -NoNewWindow
            if ($p.ExitCode -ne 0) {
                throw "A7_RUN_FAIL scenario=$name seed=$seed rep=$r code=$($p.ExitCode)"
            }
            $summary = Join-Path $folder ($(if ($isEdit) { 'a7_edits.json' } else { 'a7_route.json' }))
            if (-not (Test-Path $summary)) { throw "A7 missing report $summary" }
            $data = Get-Content -LiteralPath $summary -Raw | ConvertFrom-Json
            if ($data.seed -ne $seed -or $data.ci_smoke -ne [bool]$CiSmoke) {
                throw "A7 report provenance mismatch: $summary"
            }
            if ($isEdit) {
                if ($data.schema -ne 'a7_edit_v1' -or $data.requested_count -ne $count -or
                    $data.edit_100_gate -ne 'NOT_QUALIFIED') {
                    throw "A7 invalid edit report: $summary"
                }
            } else {
                if ($data.schema -ne 'a7_route_v1' -or $data.frame_count -le 0 -or
                    $data.perf_60_full_present_gate -ne 'NOT_QUALIFIED') {
                    throw "A7 invalid route report: $summary"
                }
            }
            $expected++
            Write-Host "A7_RUN_RECORDED scenario=$name seed=$seed rep=$r strict_gates=NOT_QUALIFIED"
        }
    }
}
Write-Host "A7_CAMPAIGN_DONE=$rootOutput reports=$expected"
& python (Join-Path $root 'scripts/a7_report.py') $rootOutput
if ($LASTEXITCODE -ne 0) { throw 'A7 REPORT compiler failed' }
Write-Host 'A7_NO_AUTOMATIC_ACCEPTANCE: graphics, depth pixels and full CPU+GPU+present require independent evidence.'
