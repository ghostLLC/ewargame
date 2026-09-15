# Single-process session integration smoke.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = "E:\EWarGame\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) { $godot = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64_console.exe" }
$project = Join-Path $root "game"
& $godot --path $project --headless -s res://session_smoke.gd
exit $LASTEXITCODE
