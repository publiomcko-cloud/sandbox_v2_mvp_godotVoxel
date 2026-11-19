$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script = Join-Path $root 'scripts/a6-run-windows.ps1'
$env:A6_OUTPUT_DIR = Join-Path $root 'reports/generated/a6-ci'
if (Test-Path $env:A6_OUTPUT_DIR) { Remove-Item -LiteralPath $env:A6_OUTPUT_DIR -Force -Recurse }
foreach ($profile in @('cpu16','cpu32')) {
    & $script -Profile $profile -Route out_and_back_18mps_300s -Duration 2 -Warmup 0.2 -Headless -CiSmoke
    if (-not $?) { throw "A6 CPU smoke failed for $profile" }
}
$reports = @(Get-ChildItem -LiteralPath $env:A6_OUTPUT_DIR -Recurse -Filter 'a2_*.json' -File)
if ($reports.Count -ne 2) { throw "A6 smoke expected exactly 2 CPU summaries, got $($reports.Count)" }
foreach ($file in $reports) {
    $r = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if ($r.ci_smoke -ne $true -or $r.a6_gpu_requested -ne $false -or
        $r.perf_60_gate -ne 'NOT_QUALIFIED' -or $r.a6_profile -notin @('cpu16','cpu32')) {
        throw "A6 smoke invalid report $($file.FullName)"
    }
}
Write-Host 'A6_HEADLESS_CPU_CONFIG_PASS: cpu16/cpu32 instantiate, no GPU or visual qualification claimed'
