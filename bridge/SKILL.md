---
name: ewargame-player
description: Play an assigned side in the EWarGame operational wargame through its local MCP tools.
---

# 战役指挥 Agent

用户须先在游戏中选择「本地 Agent」模式并启动对局，接入 ewargame MCP。此 Skill 是使用说明，MCP 桥接程序提供真实操作。用户本版不要求真实 Agent 整局验收。

## 对局循环
1. 调用 `game_rules`，再调用 `game_observe`。核实阵营、当前回合、胜利目标和命令状态。
2. 只使用返回的己方状态和已知敌情，判断补给、疲劳、预备队与目标。不要读取游戏存档、源码内的初始部署或其他阵营配置来获得额外情报。
3. 使用 `game_orders` 提交己方编组命令；每批带上当前 `turn`。目标坐标为 `[q,r]`，命令可以跨回合持续执行。整个批次验证失败时不会部分生效。
4. 可用 `game_support` 分配一次回合支援。检查返回错误，修改命令；不要反复提交相同非法操作。
5. 完成计划后调用 `game_commit` 锁定本回合。该操作不能撤回。
6. 用 `game_wait_turn` 等待下一回合，单次最多 25 秒。超时属于正常等待，可再次等待；不要重复提交已锁定回合。
7. 读取新战报，持续进行，直到 `phase=finished` 或用户要求暂停。返回最终战果和简要总结。

## 中断和权限
重连后重新读取 `game_observe`，以实际 `turn` 和己方 ready 状态为准。`stale_turn` 表示需要刷新战况。只控制分配的阵营；工具不提供修改裁决、随机数和隐藏敌情的能力。用户要求停止时不继续锁定回合。连接配置含本局凭证，不输出到聊天或日志。

## 接入
MCP stdio command: `node`，args: `[绝对路径/bridge/server.mjs]`。可通过环境变量 `EWARGAME_CONNECTION` 指向游戏界面显示的连接配置文件。游戏重开后配置会更新，桥接程序每次请求重新读取。

本地接口无需付费服务；Agent 本身的模型运行条件和费用由所用客户端决定。
