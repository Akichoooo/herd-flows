# ADR-001: herd-flows 架构决策

日期: 2026-08-17
状态: accepted

## 背景

旧版 subclaw 用 `run-claw-pool.sh` spawn `claude -p` 子进程经 claw-proxy（:4748）调模型。痛点：
1. claw-proxy 是自写 Python proxy，配置链断了全白费（auth 失败、无图形界面）
2. 子进程跑完即死，无状态感知（worker 卡住编排者不知道）
3. 磁盘回显（写 .claw.md 再读），不实时
4. KimiCode 无 CLI，不能当 worker spawn
5. 主编排者每次 worker 失败都要读完整报告重派，烧贵 token

## 决策

三层分离架构：
- 编排层：任意 CLI agent（claude/kimi），只换技能 SKILL.md
- 编排引擎：herdr（终端牧场，状态检测 idle/working/blocked，断线不死）
- 网关层：cockpit-cliproxy 池（Docker 常驻，双协议，图形化卡片配置）

验证者层：deepseek 档 worker 判定 worker 产出，FAIL→redo 循环不消耗编排者 token。

## 关键技术决策

1. **worker settings 按 dispatch 时实际 port 动态写**——预固定 profile.port 会导致 -Port 覆盖不透传到 claude 加载的 settings.json
2. **PowerShell `--` 用变量 `$DD` 传递**——PS 5.1 splatting/函数调用吞裸 `--`，agent start 透传 agent 参数必需
3. **split 默认 down**——连续 right split 切成 1 列窄条，claude 竖排渲染状态检测废掉
4. **文件 UTF-8 BOM**——PS 5.1 按 ANSI 读无 BOM 中文破坏 JSON
5. **验证者独立 worker 不是编排者自判**——省编排者 token 是核心目标
6. **herdr 命令经 `cmd /c` 拼接**——绕开 PS splatting 吞 `--`（$DD 变量也行，双保险）

## 后果

正面：引擎中立（换编排者只换 SKILL）、供应商中立（换上游只改 compose env）、FAIL 循环不烧主编排 token
负面：依赖 herdr（Windows beta）+ Docker + claude CLI 三个外部组件；opencode CLI 路由未实现（留接口注释）

## 替代方案（被否决）

- new-api（太重，AGPL v3 传染性）
- 自己写 mini gateway（维护成本，不如用成熟 cliproxy）
- 纯 API 调用无 agent（裸模型没工具，干不了活）
- KimiCode 当 worker spawn（无 CLI，不可能）
