# Windows packaging & signing notes

## Export

```powershell
powershell -File scripts/package.ps1
# output: artifacts/win/ewargame.exe
```

Requires Godot 4.7.2 and matching export templates at
`%APPDATA%\Godot\export_templates\4.7.2.stable\`.

Application icon: `game/assets/icons/ewargame_icon.png` (also `.ico`).
Version: see `game/project.godot` (`0.1.2`) and `scripts/package.ps1`.

## Code signing (optional)

Unsigned builds may trigger Windows SmartScreen. This repo does **not** ship a
certificate. To sign on a machine that has one:

```powershell
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
  /a artifacts/win/ewargame.exe
signtool verify /pa artifacts/win/ewargame.exe
```

Use your organization’s code-signing cert / EV token. Self-signed certs only
help on machines that already trust that cert; they do not clear SmartScreen
for the public.

## Cleanup after packaging

Safe to delete large one-off downloads if disk space is needed:

- `tools/export_templates.official.tpz` (~1.2GB)
- `tools/export_templates.zip` / broken `export_templates.tpz` (if unused)

Installed templates under `%APPDATA%\Godot\export_templates\` should stay.
