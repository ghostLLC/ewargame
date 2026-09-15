# Dual-process LAN reconnect smoke.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = "E:\EWarGame\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) { $godot = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64_console.exe" }
$project = Join-Path $root "game"
$hostLog = Join-Path $env:TEMP "ewargame-lan-rehost.log"
$guestLog = Join-Path $env:TEMP "ewargame-lan-reguest.log"
Remove-Item $hostLog, $guestLog -ErrorAction SilentlyContinue

$hostProc = Start-Process -FilePath $godot -ArgumentList @("--path", $project, "--headless", "-s", "res://lan_rehost_smoke.gd") -PassThru -NoNewWindow -RedirectStandardOutput $hostLog -RedirectStandardError "$hostLog.err"
Start-Sleep -Seconds 2
$guestProc = Start-Process -FilePath $godot -ArgumentList @("--path", $project, "--headless", "-s", "res://lan_reguest_smoke.gd") -PassThru -NoNewWindow -RedirectStandardOutput $guestLog -RedirectStandardError "$guestLog.err"
$hostProc.WaitForExit(60000) | Out-Null
$guestProc.WaitForExit(60000) | Out-Null
if (-not $hostProc.HasExited) { $hostProc.Kill(); $hostProc.WaitForExit(5000) | Out-Null }
if (-not $guestProc.HasExited) { $guestProc.Kill(); $guestProc.WaitForExit(5000) | Out-Null }
Write-Host "=== HOST ==="
Get-Content $hostLog -ErrorAction SilentlyContinue
Get-Content "$hostLog.err" -ErrorAction SilentlyContinue
Write-Host "=== GUEST ==="
Get-Content $guestLog -ErrorAction SilentlyContinue
Get-Content "$guestLog.err" -ErrorAction SilentlyContinue
$ht = (Get-Content $hostLog -Raw -ErrorAction SilentlyContinue)
$gt = (Get-Content $guestLog -Raw -ErrorAction SilentlyContinue)
if (($ht -notmatch "LAN_REHOST_OK") -or ($gt -notmatch "LAN_REGUEST_OK")) {
    Write-Error "LAN reconnect smoke failed"
    exit 1
}
Write-Host "LAN RECONNECT SMOKE PASS"
exit 0
