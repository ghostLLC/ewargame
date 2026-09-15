# Content review — remediation record

Original findings in this file required fixes before approval. Remediation completed 2026-09-15 on branch `codex/content-fix`.

## Findings closed

1. **P1 HQ inference** — Closed. `scripts/validate_content.py` uses explicit `type`/`size` per formation. Tutorial 2 HQ / 9 combat; historical scenarios 1–3 HQ each. Validator enforces combat floor and HQ ceiling.
2. **P1 Sinai water spawn + canal** — Closed. Canal belt at q=7–8 with three bridges; Egyptian bridgeheads on east bank; Israeli counterattack depth east; objectives tied to Ismailia / Chinese Farm / Deversoir / central bridge. Validator rejects impassable unit/depot/objective/reinforcement tiles.
3. **P2 roster front/date mixing** — Closed. Bridgehead roster excludes 4th Armored (July landing); breakout uses late-July armor set; Sinai (143/162/252) and Golan (7th/188th/Golani) Israeli lists are separate. `docs/history.md` records the policy.
4. **P2 generic maps** — Closed. Distinct geography and labels: Utah causeways/Carentan, Saint-Lô bocage, Suez canal, Golan ridge, Wadi al-Batin, Kuwait coast+fortified belt, tutorial river valley. Cross-scenario identical objective names rejected by validator.
5. **P2 tutorial interleaving** — Closed. Blue west / red east staging, combat roster, staged practice steps in description, reachable local objectives.

## Evidence this session

- `python scripts/validate_content.py all` → CONTENT PASS
- Godot core regression → CORE PASS 56 assertions
- AI vs AI seven scenarios → AI_SUMMARY pass=7 fail=0
- Session smoke → SESSION PASS 13 assertions
- Dual-process LAN same-machine → LAN SMOKE PASS (not dual-physical-machine evidence)
- MCP bridge tests → 3/3 PASS
- UI smoke captures regenerated
- Windows export → `artifacts/win/ewargame.exe`

## Still excluded / residual

- Real local Agent full-match acceptance (user exclusion)
- Dual physical machine LAN verification
