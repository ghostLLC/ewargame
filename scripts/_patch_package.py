from pathlib import Path

p = Path(r"C:\Users\LLC\.codex\worktrees\ewargame-content\scripts\package.ps1")
text = p.read_text(encoding="utf-8")
# Replace the here-string preset writer with a UTF-8 no-BOM write of the known-good cfg.
old = '''	if (-not (Test-Path $presetCfg)) {
    @\''
'''
# Find and replace entire if-block by locating start and the following marker after Set-Content
start = text.find("\tif (-not (Test-Path $presetCfg)) {")
end = text.find("Write-Host \\"Wrote default export_presets.cfg\\"")
if start < 0 or end < 0:
    raise SystemExit(f"markers not found start={start} end={end}")
new_block = '''\t$exportPath = Join-Path $outDir "ewargame.exe"
\t$presetBody = @"
[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.json,*.otf,*.ttf,*.svg"
exclude_filter="export_presets.cfg,ai_accept.gd,session_smoke.gd,lan_host_smoke.gd,lan_guest_smoke.gd,tests_run.gd"
export_path="$exportPath"
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
application/file_version="0.1.0.0"
application/product_version="0.1.0.0"
application/company_name=""
application/product_name="EWarGame"
application/file_description="EWarGame operational wargame"
application/copyright=""
application/trademarks=""
application/export_angle=0
application/export_d3d12=0
ssh_remote_deploy/enabled=false
"@
\t[System.IO.File]::WriteAllText($presetCfg, $presetBody, [System.Text.UTF8Encoding]::new($false))
\tWrite-Host "Wrote default export_presets.cfg"
'''
# include the Write-Host line in replacement - we search to Write-Host and include through its line
line_end = text.find("\n", end)
text = text[:start] + new_block + text[line_end+1:]
p.write_text(text, encoding="utf-8")
print("package.ps1 preset writer updated")
