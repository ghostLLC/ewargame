# EWarGame acceptance gate (same machine). Excludes live Agent match and dual-physical LAN.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = "E:\EWarGame\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) { $godot = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64_console.exe" }
$project = Join-Path $root "game"
$failed = @()

function Invoke-Step($name, [scriptblock]$block) {
    Write-Host "==> $name"
    try {
        & $block
        if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
            throw "exit $LASTEXITCODE"
        }
        Write-Host "OK $name"
    } catch {
        Write-Host "FAIL $name : $_"
        $script:failed += $name
    }
}

Invoke-Step "content" { Set-Location $root; python scripts\validate_content.py all }
Invoke-Step "core" {
    Copy-Item (Join-Path $root "tests\core_test.gd") (Join-Path $project "tests_run.gd") -Force
    & $godot --path $project --headless -s res://tests_run.gd
}
Invoke-Step "ai" { & $godot --path $project --headless -s res://ai_accept.gd }
Invoke-Step "session" { & $godot --path $project --headless -s res://session_smoke.gd }
Invoke-Step "mcp" { Set-Location (Join-Path $root "bridge"); node --test test.mjs }
Invoke-Step "lan" { powershell -ExecutionPolicy Bypass -File (Join-Path $root "scripts\lan_smoke.ps1") }
Invoke-Step "lan_reconnect" { powershell -ExecutionPolicy Bypass -File (Join-Path $root "scripts\lan_reconnect_smoke.ps1") }

Remove-Item (Join-Path $project "tests_run.gd") -ErrorAction SilentlyContinue

if ($failed.Count -gt 0) {
    Write-Host "ACCEPTANCE FAIL: $($failed -join ', ')"
    exit 1
}
Write-Host "ACCEPTANCE PASS (same-machine; dual-physical LAN and live Agent excluded)"
exit 0
