$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$editor = Join-Path $root '.tools/godot.exe'
if (-not (Test-Path $editor)) { throw 'Run scripts/bootstrap-windows.ps1 first' }
if (-not (Test-Path (Join-Path $root 'godot/bin/sandbox_native.windows.template_debug.x86_64.dll'))) {
    throw 'Run scripts/bootstrap-windows.ps1 -Target template_debug first'
}
$godotProject = Join-Path $root 'godot'
$quotedPath = '"' + $godotProject + '"'
$import = Start-Process -FilePath $editor -ArgumentList @('--headless','--editor','--path',$quotedPath,'--import','--quit') -Wait -PassThru -NoNewWindow
if ($import.ExitCode -ne 0) { throw "Editor project import failed: exit=$($import.ExitCode)" }
$smoke = Start-Process -FilePath $editor -ArgumentList @('--headless','--path',$quotedPath,'--script','res://tests/smoke.gd') -Wait -PassThru -NoNewWindow
if ($smoke.ExitCode -ne 0) { throw "A0_SMOKE_FAIL exit=$($smoke.ExitCode)" }
Write-Host 'A0_SMOKE_PASS'
