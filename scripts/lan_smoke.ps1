# Dual-process LAN smoke for EWarGame.
# Usage: powershell -File scripts/lan_smoke.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = "E:\EWarGame\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if (-not (Test-Path $godot)) {
    $godot = Join-Path $root "tools\godot\Godot_v4.7.2-stable_win64_console.exe"
}
if (-not (Test-Path $godot)) { throw "Godot console binary not found" }
$project = Join-Path $root "game"
$hostLog = Join-Path $env:TEMP "ewargame-lan-host.log"
$guestLog = Join-Path $env:TEMP "ewargame-lan-guest.log"
Remove-Item $hostLog, $guestLog -ErrorAction SilentlyContinue

$hostArgs = @("--path", $project, "--headless", "-s", "res://lan_host_smoke.gd")
$guestArgs = @("--path", $project, "--headless", "-s", "res://lan_guest_smoke.gd")

$hostProc = Start-Process -FilePath $godot -ArgumentList $hostArgs -PassThru -NoNewWindow -RedirectStandardOutput $hostLog -RedirectStandardError "$hostLog.err"
Start-Sleep -Seconds 2
$guestProc = Start-Process -FilePath $godot -ArgumentList $guestArgs -PassThru -NoNewWindow -RedirectStandardOutput $guestLog -RedirectStandardError "$guestLog.err"

$hostProc.WaitForExit(45000) | Out-Null
$guestProc.WaitForExit(45000) | Out-Null
if (-not $hostProc.HasExited) { $hostProc.Kill(); $hostProc.WaitForExit(5000) | Out-Null }
if (-not $guestProc.HasExited) { $guestProc.Kill(); $guestProc.WaitForExit(5000) | Out-Null }

$hostCode = $hostProc.ExitCode
$guestCode = $guestProc.ExitCode
Write-Host "=== HOST exit=$hostCode ==="
Get-Content $hostLog -ErrorAction SilentlyContinue
Get-Content "$hostLog.err" -ErrorAction SilentlyContinue
Write-Host "=== GUEST exit=$guestCode ==="
Get-Content $guestLog -ErrorAction SilentlyContinue
Get-Content "$guestLog.err" -ErrorAction SilentlyContinue

$hostText = (Get-Content $hostLog -Raw -ErrorAction SilentlyContinue) + (Get-Content "$hostLog.err" -Raw -ErrorAction SilentlyContinue)
$guestText = (Get-Content $guestLog -Raw -ErrorAction SilentlyContinue) + (Get-Content "$guestLog.err" -Raw -ErrorAction SilentlyContinue)
if (($hostText -notmatch "LAN_HOST_OK") -or ($guestText -notmatch "LAN_GUEST_OK")) {
    Write-Error "LAN smoke failed (hostCode=$hostCode guestCode=$guestCode)"
    exit 1
}
Write-Host "LAN SMOKE PASS (same-machine dual process; not dual-physical-machine evidence)"
exit 0

