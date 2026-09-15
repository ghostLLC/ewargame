# Development ledger — 2026-09-10-ewargame

Approved scope in spec. Branch `codex/first-playable` carried core/session/UI/MCP implementation.

Preflight interfaces: Core -> Content uses exact scenario schema; Core -> Session uses WarEngine static methods; Session -> UI uses observation only; Session -> MCP uses scoped loopback JSON.

## 2026-09-15 — content remediation + acceptance (worktree `codex/content-fix`)

### Content
- Rewrote generator/validator; regenerated seven scenarios; CONTENT PASS.
- Explicit types, scenario-scoped rosters/maps, legal deployment, tutorial staging.
- Reinforcements: Golan T2, Sinai T3, breakout T4. Sinai `night_cycle` + weather fields. Tutorial staged practice text.

### Session / UI
- `start_game` accepts `play_mode="lan"` (host/join still required to open sockets).
- Observer pause exposed (`observer_paused()`, menu + commit button label).
- Save slots slot1–3 in campaign menu.

### Acceptance (same machine)
| Check | Result |
|---|---|
| content validate | PASS |
| core_test | PASS 56 |
| AI 7 scenarios | PASS 7/7 |
| session_smoke | PASS 13 |
| lan_smoke dual-process | PASS (not dual-physical-machine) |
| bridge/test.mjs | PASS 3/3 |
| UI smoke | captured |
| Windows export | artifacts/win/ewargame.exe |

### Scripts added
- `game/session_smoke.gd`, `scripts/integration_smoke.ps1`
- `game/lan_host_smoke.gd`, `game/lan_guest_smoke.gd`, `scripts/lan_smoke.ps1`
- `game/ai_accept.gd` (headless AI runner)
- `scripts/package.ps1` (export preset + release)

### Residual
- Dual physical machine LAN not claimed
- No live Agent full match (excluded)
- Smoke helper scripts excluded from export preset

## 2026-09-16 — polish pass (worktree `codex/content-fix`)

- Replay timeline slider + jump; after-action report export (`user://after_action_report.txt`)
- Weather schedule/cycle (breakout, sinai+night, golan); fixed bool/array weather_cycle crash
- Upcoming-reinforcement hint in command bar
- AI difficulty easy/normal/hard (menu + in-game)
- Save manager (list timestamps, load/overwrite/delete)
- LAN reconnect smoke (`scripts/lan_reconnect_smoke.ps1`)
- Acceptance gate `scripts/run_acceptance.ps1`; version 0.1.1; package rebuilt

### Evidence
core 56 · AI 7/7 · session 13 · MCP 3/3 · LAN · LAN reconnect · CONTENT PASS · export exe
