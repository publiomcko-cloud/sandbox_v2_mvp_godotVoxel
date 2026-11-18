param(
    [ValidateSet('template_debug','template_release')]
    [string] $Target = 'template_debug',
    [switch] $SkipDownload
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$lock = Get-Content (Join-Path $root 'third_party.lock') -Raw | ConvertFrom-Json
$toolsDir = Join-Path $root '.tools'
$cppDir = Join-Path $root 'third_party/godot-cpp'
$editor = Join-Path $toolsDir 'godot.exe'
$archive = Join-Path $toolsDir 'godot-editor.zip'
New-Item -ItemType Directory -Force $toolsDir | Out-Null

if (-not $SkipDownload) {
    Write-Host 'Fetching locked custom Godot editor...'
    Invoke-WebRequest -Uri $lock.godot.editor_windows.url -OutFile $archive
    $actual = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $lock.godot.editor_windows.sha256) {
        throw "Editor SHA-256 mismatch: expected $($lock.godot.editor_windows.sha256), got $actual"
    }
    $unzip = Join-Path $toolsDir 'unpacked'
    New-Item -ItemType Directory -Force $unzip | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $unzip -Force
    $executable = Get-ChildItem $unzip -Recurse -File -Filter 'godot.windows.editor.x86_64.exe' | Select-Object -First 1
    if ($null -eq $executable) { throw 'Godot editor EXE absent from verified release archive' }
    Copy-Item -LiteralPath $executable.FullName -Destination $editor -Force
}
if (-not (Test-Path $editor)) { throw "Missing editor: $editor" }

if (-not (Test-Path (Join-Path $cppDir '.git'))) {
    New-Item -ItemType Directory -Force $cppDir | Out-Null
    & git -C $cppDir init -q
    if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
    & git -C $cppDir remote add origin $lock.godot_cpp.repository
    if ($LASTEXITCODE -ne 0) { throw 'git remote add failed' }
}
& git -C $cppDir fetch --depth 1 origin $lock.godot_cpp.commit
if ($LASTEXITCODE -ne 0) { throw 'git fetch godot-cpp failed' }
& git -C $cppDir checkout --detach --force FETCH_HEAD
if ($LASTEXITCODE -ne 0) { throw 'git checkout godot-cpp failed' }
$actualCommit = (& git -C $cppDir rev-parse HEAD).Trim()
if ($actualCommit -ne $lock.godot_cpp.commit) { throw "godot-cpp commit mismatch: $actualCommit" }

Write-Host 'Generating extension_api.json from the locked custom engine...'
Push-Location $root
try {
    & $editor --headless --dump-extension-api
    if ($LASTEXITCODE -ne 0) { throw 'Godot --dump-extension-api failed' }
} finally { Pop-Location }
$api = Join-Path $root 'extension_api.json'
if (-not (Test-Path $api)) { throw "extension_api.json missing: $api" }
$apiData = Get-Content $api -Raw | ConvertFrom-Json
if (-not ($apiData.classes | Where-Object { $_.name -eq 'VoxelLodTerrain' })) {
    throw 'Custom Godot API contains no VoxelLodTerrain; wrong engine binary'
}

Write-Host "Building native GDExtension ($Target)..."
& scons -C (Join-Path $root 'native') 'platform=windows' "target=$Target" "custom_api_file=$api" '-j4'
if ($LASTEXITCODE -ne 0) { throw "SCons failed: exit $LASTEXITCODE" }
$dll = Join-Path $root "godot/bin/sandbox_native.windows.$Target.x86_64.dll"
if (-not (Test-Path $dll)) { throw "Expected GDExtension DLL missing: $dll" }
Write-Host "A0_BUILD_PASS: $dll"
