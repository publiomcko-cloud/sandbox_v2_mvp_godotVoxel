$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$editor = Join-Path $root '.tools/godot.exe'
if (-not (Test-Path $editor)) { throw 'Run scripts/bootstrap-windows.ps1 first' }
if (-not (Test-Path (Join-Path $root 'godot/bin/sandbox_native.windows.template_debug.x86_64.dll'))) {
    throw 'Run scripts/bootstrap-windows.ps1 -Target template_debug first'
}
& $editor --headless --path (Join-Path $root 'godot') --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Editor project import failed' }
& $editor --headless --path (Join-Path $root 'godot') --script 'res://tests/smoke.gd'
if ($LASTEXITCODE -ne 0) { throw "A0_SMOKE_FAIL exit=$LASTEXITCODE" }
Write-Host 'A0_SMOKE_PASS'
