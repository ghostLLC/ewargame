# 战线 · 战役指挥（EWarGame）

Windows 中文 2D 六角格作战级兵棋。WEGO 秘密同时下令，确定性裁决；人机 / 热座 / 局域网 / 观察模式；本地 MCP 桥可供 Agent 代打一方（本版不要求真实 Agent 整局验收）。

## 需要

- Godot **4.7.2**（仓库 `tools/godot/` 已有官方 Windows 构建时可直接用）
- 可选：Node.js 20+（MCP 桥 `bridge/server.mjs`）
- 可选：Python 3.10+（仅剧本生成与校验，标准库）

## 目录

| 路径 | 职责 |
|---|---|
| `game/` | Godot 工程：core 裁决、session 权威、ui、剧本 JSON、美术 |
| `game/core/engine.gd` | `WarEngine` 纯规则（UI 不得直读完整 state） |
| `game/data/scenarios/` | 七个剧本（教学 + 六历史关） |
| `tests/core_test.gd` | 核心回归 |
| `bridge/` | Node stdio MCP 适配器与 Skill 说明 |
| `scripts/validate_content.py` | 剧本生成与静态校验 |
| `docs/` | 规格、计划、史料边界、内容审查与进度 |

## 打开工程

用 Godot 4.7.2 打开 `game/project.godot`，主场景 `main.tscn`。

命令行烟测（需本机 Godot 可执行文件）：

```powershell
# 菜单截图
& .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path game -- --ui-menu-smoke --capture=user://ui-menu-smoke.png

# 对局地图截图
& .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path game -- --ui-smoke --scenario=tutorial --capture=user://ui-smoke.png

# 核心回归（脚本在仓库 tests/，需绝对或相对工程可解析路径）
& .\tools\godot\Godot_v4.7.2-stable_win64_console.exe --path game --headless -s (Resolve-Path tests\core_test.gd)
```

## 剧本内容

```powershell
python scripts\validate_content.py all
```

应输出 `CONTENT PASS`。生成器会重写 `game/data/scenarios/*.json`：显式兵种类型、分场景编制与地图、禁止不可通行水域部署。

## 对局模式

- **人机**：与离线 AI 对战  
- **热座**：同机双人，回合交接  
- **局域网**：主机权威 + UDP 房间发现  
- **观察**：双方 AI 自动推进  
- **本地 Agent**：游戏内写 `agent-connection.json`，MCP 经回环口令调用 `game_observe` / `game_orders` / `game_commit` 等  

MCP 接入见 `bridge/SKILL.md`。命令示例：`node` + 绝对路径 `bridge/server.mjs`，环境变量 `EWARGAME_CONNECTION` 可指向连接配置。

## 打包

```powershell
powershell -File scripts\package.ps1
```

需要已配置 Godot 4.7.2 导出模板（本机已装到 `%APPDATA%\Godot\export_templates\4.7.2.stable\`）。导出 Windows 桌面构建到 `artifacts/win/ewargame.exe`。

## 集成烟测

```powershell
powershell -File scripts\integration_smoke.ps1   # 会话层：下令/结算/存读档/观察暂停/lan 模式
powershell -File scripts\lan_smoke.ps1           # 同机双进程 LAN（不等于双物理机证据）
```

## 边界与诚实声明

- 历史场景是玩法抽象，不是精确复原；详见 `docs/history.md`。  
- 双物理机 LAN 未验证前，不得用同机双进程结果冒充。  
- 本版不做真实 Agent 整局验收；MCP 协议与鉴权测试仍需要。  
