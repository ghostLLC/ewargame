# Package EWarGame Windows build into artifacts/.
# Requires Godot 4.7.2 + matching export templates.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$candidates = @(
    (Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64_console.exe"),
    (Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64.exe"),
    "E:\EWarGame\tools\godot\Godot_v4.7.2-stable_win64_console.exe",
    "E:\EWarGame\tools\godot\Godot_v4.7.2-stable_win64.exe"
)
$godot = $null
foreach ($c in $candidates) {
    if (Test-Path $c) { $godot = $c; break }
}
if (-not $godot) {
    throw "Godot 4.7.2 not found. Place it under tools/godot or E:\EWarGame\tools\godot."
}

$project = Join-Path $root "game"
$outDir = Join-Path $root "artifacts\win"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$exportPath = Join-Path $outDir "ewargame.exe"
$presetCfg = Join-Path $project "export_presets.cfg"
$presetBody = @"
[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.json,*.otf,*.ttf,*.svg"
exclude_filter="export_presets.cfg,ai_accept.gd,session_smoke.gd,lan_host_smoke.gd,lan_guest_smoke.gd,lan_rehost_smoke.gd,lan_reguest_smoke.gd,tests_run.gd"
export_path="../artifacts/win/ewargame.exe"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=1
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=true
application/icon=""
application/console_wrapper_icon=""
application/icon_interpolation=4
application/file_version="0.1.1.0"
application/product_version="0.1.1.0"
application/company_name=""
application/product_name="EWarGame"
application/file_description="EWarGame operational wargame"
application/copyright=""
application/trademarks=""
application/export_angle=0
application/export_d3d12=0
ssh_remote_deploy/enabled=false
"@
[System.IO.File]::WriteAllText($presetCfg, $presetBody, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote export_presets.cfg"

& $godot --headless --path $project --import
if ($LASTEXITCODE -ne 0) { throw "Godot import failed ($LASTEXITCODE)" }

& $godot --headless --path $project --export-release "Windows Desktop" $exportPath
if ($LASTEXITCODE -ne 0) { throw "Export failed ($LASTEXITCODE)" }

Get-ChildItem $outDir | Format-Table Name, Length
Write-Host "Packaged to $outDir"
