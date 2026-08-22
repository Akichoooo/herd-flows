# ADR-001: herd-flows 架构决策

日期: 2026-08-17  
状态: accepted (v2 模块化整合)

## 背景

旧版 subclaw 用 `run-claw-pool.sh` spawn `claude -p` 子进程经 claw-proxy（:4748）调模型。痛点：
1. claw-proxy 是自写 Python proxy，配置链断了全白费（auth 失败、无图形界面）
2. 子进程跑完即死，无状态感知（worker 卡住编排者不知道）
3. 磁盘回显（写 .claw.md 再读），不实时
4. KimiCode 无 CLI，不能当 worker spawn
5. 主编排者每次 worker 失败都要读完整报告重派，烧贵 token

## 核心架构决策

### 1. 独创“牧人 - 羊群 - 牧羊犬”三级分工模型
- **牧人（Orchestrator）**：任意主模型 CLI（Claude Code / Kimi Code），只派发高层 Brief，不看脏活过程。
- **羊群（Workers）**：运行于 `flash` / `glm` 廉价模型，在独立 Pane 中快速干活。
- **牧羊犬（Verifier）**：运行于 `deepseek` 严谨模型，在独立 Pane 中自动质检，发现缺陷生成 `redo` 指令底层重做，**不消耗主模型 Token**。

### 2. 双 UI 架构与职责边界
- **执行看板（Herdr TUI）**：基于 Rust 原生终端多路复用器，展示 Pane 分屏、工作区与 Agent 语义状态（`idle`/`working`/`blocked`），断线不丢状态。
- **配置看板（Cockpit Tools 反代）**：双模支持（Windows 桌面端 GUI / Docker 容器化网关池），提供多厂商 Key、端口映射、429 容错与协议转发。

### 3. 四层清晰解耦与上游无损升级
- `orchestrator/`：专属业务调度、Verifier 验收循环、动态环境注入。
- `orchestrator/adapters/`：Herdr 与 Gateway 适配器，隔离底层 CLI/API 变动。
- `proxy/`：自包含 Cockpit Cliproxy Go 源码，支持一键独立构建与上游同步（`update-cockpit.ps1`）。
- `vendor/herdr/`：Herdr 外部运行时管理与一键升级（`update-herdr.ps1`）。

## 关键技术决策

1. **worker settings 按 dispatch 时实际 port 动态写**——预固定 profile.port 会导致 -Port 覆盖不透传到 claude 加载的 settings.json
2. **PowerShell `--` 用变量 `$DD` 传递**——PS 5.1 splatting/函数调用吞裸 `--`，agent start 透传 agent 参数必需
3. **split 默认 down**——连续 right split 切成 1 列窄条，claude 竖排渲染状态检测废掉
4. **文件 UTF-8 BOM**——PS 5.1 按 ANSI 读无 BOM 中文破坏 JSON
5. **验证者独立 worker 不是编排者自判**——省编排者 token 是核心目标
6. **herdr 命令经 `cmd /c` 拼接**——绕开 PS splatting 吞 `--`
7. **支持 `-Async` 异步非阻塞派发**——解耦派发与回显等待，支持多 Worker 并发推进

## 后果

- **正面**：引擎中立、厂商中立、FAIL 循环底层自消化、上游依赖可一键无损升级、双模配置灵活。
- **依赖**：Herdr（Windows beta / Linux / macOS）+ Docker + Claude CLI。
