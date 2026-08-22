# vendor/herdr

Herdr 外部运行时管理模块。

## 作用
- Herdr（https://herdr.dev）是专为 AI Coding Agent 设计的终端多路复用与运行时（Terminal Multiplexer + Runtime）。
- 本项目通过 `orchestrator/adapters/herdr-adapter.ps1` 适配层与 Herdr 通信，实现终端 Pane 几何切分、Agent 语义生命周期检测（`working`/`blocked`/`idle`）与指令交互。

## 维护脚本
- `install-herdr.ps1`: 安装与自检 Herdr 运行时
- `update-herdr.ps1`: 升级 Herdr 至官方最新版本
