param(
    [ValidateSet('all','t007','t064','t135','t236','t250')]
    [string] $Site = 'all',
    [switch] $CiSmoke,
    [switch] $Capture
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$editor = Join-Path $root '.tools/godot.exe'
$project = Join-Path $root 'godot'
$dll = Join-Path $project 'bin/sandbox_native.windows.template_debug.x86_64.dll'
if (-not (Test-Path $editor) -or -not (Test-Path $dll)) {
    throw 'A6B requires pinned Godot and A3 DLL; run scripts/bootstrap-windows.ps1 -RuntimeOnly'
}
if ($CiSmoke -and ($Capture -or $Site -ne 't007')) {
    throw 'CI headless accepts only first site t007, without GPU screenshots'
}
$cache = Join-Path $project '.godot'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
[System.IO.File]::WriteAllText(
    (Join-Path $cache 'extension_list.cfg'),
    "res://sandbox_native.gdextension" + [Environment]::NewLine,
    (New-Object System.Text.UTF8Encoding($false))
)
if ($CiSmoke) {
    $output = Join-Path $root 'reports/generated/a6b-ci'
    if (Test-Path $output) { Remove-Item -LiteralPath $output -Recurse -Force }
} else {
    $output = Join-Path $root ('reports/generated/a6b/diagnostic-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$PID")
}
New-Item -ItemType Directory -Path $output -Force | Out-Null
$expectedSites = if ($CiSmoke -or $Site -ne 'all') { 1 } else { 5 }
$quoted = '"' + $project + '"'
$summary = @()
foreach ($profile in @('cpu16','cpu32')) {
    $folder = Join-Path $output $profile
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $env:A6B_OUTPUT_DIR = $folder
    $env:A3_SAVE_PATH = Join-Path $folder 'world.sqlite'
    $env:A4_ROCK_STATE_PATH = Join-Path $folder 'rocks.json'
    $argsList = @()
    if ($CiSmoke) { $argsList += '--headless' }
    else { $argsList += @('--rendering-method','forward_plus','--rendering-driver','vulkan') }
    $argsList += @('--path',$quoted,'--script','res://tests/a6b_probe_diagnostic.gd','--',
                   "--profile=$profile", "--site=$Site")
    if ($CiSmoke) { $argsList += '--ci-smoke' }
    if ($Capture) { $argsList += '--capture' }
    Write-Host "A6B_START profile=$profile site=$Site headless=$CiSmoke screenshots=$Capture"
    $p = Start-Process -FilePath $editor -ArgumentList $argsList -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { throw "A6B_DIAG_FAIL profile=$profile exit=$($p.ExitCode)" }
    $path = Join-Path $folder ("a6b_$profile.json")
    if (-not (Test-Path $path)) { throw "A6B missing report $path" }
    $r = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $expectedBlock = if ($profile.EndsWith('32')) { 32 } else { 16 }
    if ($r.schema -ne 'a6b_probe_v1' -or $r.profile -ne $profile -or
        $r.mesh_block_size -ne $expectedBlock -or $r.view_distance_m -ne 192 -or
        $r.seed -ne 20261119 -or $r.gpu_generation -ne $false -or
        @($r.sites).Count -ne $expectedSites -or $r.candidate_promoted -ne $false) {
        throw "A6B report/coverage drift in $path"
    }
    if (-not $CiSmoke -and ($r.rendering_method -ne 'forward_plus' -or $r.rendering_driver -ne 'vulkan')) {
        throw "A6B renderer mismatch: $($r.rendering_method)/$($r.rendering_driver)"
    }
    foreach ($s in $r.sites) {
        $summary += [pscustomobject]@{
            profile = $profile; site = $s.site; player_x = $s.player_x;
            arrival_hits = $s.arrival.original_hits_8;
            settled_hits = $s.settled.original_hits_8;
            missing_dirs = (@($s.settled.original_missing_directions) -join ',');
            boundary_dirs = (@($s.settled.missing_directions_crossing_128m_grid) -join ',');
            split_covered_dirs = (@($s.settled.split_covered_but_original_failed) -join ',');
            screenshots = $s.screen_images
        }
    }
    Write-Host "A6B_PROFILE_PASS profile=$profile sites=$(@($r.sites).Count)"
}
$csv = Join-Path $output 'a6b_probe_summary.csv'
$summary | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
python (Join-Path $root 'scripts/a6b_probe_geometry.py') | Out-File -LiteralPath (Join-Path $output 'a6b_geometry.json') -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw 'A6B Python geometry audit failed' }
Write-Host "A6B_DIAGNOSTIC_PASS output=$output"
Write-Host 'A6B_BASELINE_RETAINED: no promotion without moving 18m/s graphical pixel proof'
