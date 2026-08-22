# herd-flows

> **基于 Herdr 终端牧场 + Cockpit 反代网关的轻量高效 Agent 编排流水线**  
> 独创 **“牧人（编排者）- 羊群（Worker）- 牧羊犬（Verifier）”** 三级分工架构与底层自闭环质检，极大节省主模型 Token。

---

## 🌟 核心理念：牧人、羊群与牧羊犬

在传统的 Agent 派发中，子模型报错或写出低质代码时，主模型需要耗费大量昂贵的上下文去阅读、分析并重新指派，不仅速度慢，而且成本极高。

`herd-flows` 引入了 **三级经济学分工模型**：

```
┌────────────────────────────────────────────────────────┐
│             1. 牧人 (Orchestrator - 昂贵高智商)          │
│   - Claude Code / Kimi Code 等主编排 Agent             │
│   - 核心原则: "只动脑派活，绝不看脏活过程，绝不烧贵 Token"   │
└───────────────────────────┬────────────────────────────┘
                            │ 派发结构化任务契约 (Brief)
                            ▼
┌────────────────────────────────────────────────────────┐
│        2. 核心编排调度引擎 (orchestrator/ 专属业务模块)  │
│   - 档位路由 (flash / deepseek / glm)                  │
│   - 动态环境隔离 (settings.json 毫秒级生成)              │
│   - 状态感知驱动 (借助 Herdr 检测 idle/working/blocked) │
└──────────────┬──────────────────────────▲──────────────┘
               │                          │
               ▼                          │ 自动循环质检 (不惊动主模型)
┌──────────────────────────────┐  ┌───────┴──────────────────────┐
│  3. 羊群 (Worker 廉价干活)   │  │  4. 牧羊犬 (Verifier 独立质检)│
│  - 运行 6.8-flash-lite/glm   │  │  - 运行 DeepSeek 档位        │
│  - 在独立 Pane 中扫码/写代码 │  │  - 严格审核交付物是否实质完整│
│  - 产出初步半成品            │─►│  - PASS: 放行交付主模型      │
│                              │  │  - FAIL: 生成 redo 指令打回  │
└──────────────┬───────────────┘  └──────────────────────────────┘
               │
               ▼
┌────────────────────────────────────────────────────────┐
│  5. 出海反代网关 (proxy/ 模块 - 基于 Cockpit Tools)     │
│  - Docker 4 实例网关池 (:1456 ~ :1459) 或 Win 本地客户端│
│  - 自动协议转换 (Claude ◄► OpenAI/SenseNova) / 429 容错│
└────────────────────────────────────────────────────────┘
```

1. **牧人（Orchestrator）**：Claude Code 或 Kimi Code，只负责理解用户意图与验收最终成品。
2. **羊群（Workers）**：运行在廉价高吞吐模型（`sensenova-6.8-flash-lite`、`glm-5.2`），在后台 Pane 中大量读写代码、运行命令。
3. **牧羊犬（Verifier）**：运行在严谨推理模型（`deepseek-v4-flash`），在独立 Pane 中自动质检验收。若发现敷衍或缺陷，直接生成 `redo` 指令打回 Worker 重做（最多 2 轮），**所有失败与重试在底层全部消化，主模型始终只看合格品**。

---

## 🖥️ 双 UI 协同架构

系统采用清晰的“前线干活 + 后勤配置”双 UI 模式：

- **UI ①：Herdr 终端执行牧场（TUI / 前线）**
  - 基于 Rust 开发的原生终端多路复用界面；
  - 实时展示所有 Pane 分屏、工作区拓扑、Agent 语义状态（🟢 `working` / 🟡 `blocked` / ⚪ `idle`）；
  - 支持 `Ctrl+B` 快捷键与鼠标点击/拖拽分屏。
- **UI ②：Cockpit Tools 反代配置（后勤）**
  - **Windows 桌面模式**：直接使用 Cockpit Tools 桌面端图形化界面管理厂商 Key、本地代理端口与模型映射；
  - **Docker 模式**：通过 `proxy/compose.subclaw-pool.yml` 启动 4 端口网关池，浏览器与容器化一键管理。

---

## 📁 模块化目录结构

项目各模块高度解耦，**业务编排逻辑独立沉淀，上游组件（Herdr / Cockpit Tools）支持无损一键更新**：

```
herd-flows/
├── orchestrator/                    # ⭐️【核心业务模块：编排与沟通优化引擎】
│   ├── engine.ps1                   # 调度总引擎 (Ensure / Dispatch / Verify 闭环 / Clean)
│   ├── verifier.ps1                 # 牧羊犬质检评估器 (独立 Pane 质检、提取 redo)
│   ├── profile-manager.ps1          # Worker 档位管理与 settings.json 动态注入
│   ├── adapters/
│   │   ├── herdr-adapter.ps1        # Herdr 终端牧场适配层 (隔离 Herdr CLI 变动)
│   │   └── gateway-adapter.ps1      # Cockpit 反代网关适配层 (端口探测、429 容错)
│   └── templates/
│       └── verifier-default.txt     # 质检员默认 Prompt 验收模板
│
├── proxy/                           # ⭐️【Cockpit Tools 反代与配置模块 (支持上游更新)】
│   ├── sidecars/cockpit-cliproxy/   # 完整的 Go 源码 (自包含，支持离线/独立构建)
│   ├── Dockerfile.cockpit-cliproxy  # 独立构建 Docker 镜像
│   ├── compose.subclaw-pool.yml     # 4 端口网关 Docker 编排 (:1456 ~ :1459)
│   ├── .env.example                 # 多 Key 环境变量模板
│   └── update-cockpit.ps1           # 上游 Cockpit Tools 源码同步更新脚本
│
├── vendor/
│   └── herdr/                       # ⭐️【Herdr 运行时管理 (支持上游更新)】
│       ├── install-herdr.ps1        # Herdr 运行时安装与自检
│       ├── update-herdr.ps1         # Herdr 官方版本升级脚本
│       └── README.md
│
├── runner/                          # 【用户与 CLI 交互入口】
│   ├── herdr-pool.ps1               # 统一对外 CLI（透传调用 orchestrator）
│   └── config.json                  # 统一 Profiles 与端口映射配置
│
├── skills/                          # 【Agent 入口技能】
│   ├── subclaw.claude.md            # Claude Code 入口技能 (/subclaw)
│   └── subclaw.kimi.md              # Kimi Code 入口技能 (/subclaw)
│
├── scripts/                         # 【全套运维与一键脚本】
│   ├── install-deps.ps1             # 依赖一键安装与自检
│   ├── start-proxy.ps1              # 启动网关池 (Docker 或本地模式)
│   ├── start-herdr.ps1              # 启动/进入 Herdr 终端牧场 (TUI)
│   ├── start-all.ps1                # 一键拉起全套生态
│   └── update-all-upstreams.ps1     # ⭐️ 一键检查并更新 Herdr 与 Cockpit Tools 上游
│
├── docs/                            # 架构决策记录与历史 Task Brief 归档
└── README.md                        # 本手册
```

---

## 🚀 快速开始

### 1. 依赖自检与初始化
```powershell
powershell scripts\install-deps.ps1
```
脚本会自动检查/安装 Herdr 运行时、Docker 环境、独立编译 `cockpit-cliproxy` 本地镜像并检测 Claude CLI。

### 2. 配置厂商 API Key
复制 `proxy/.env.example` 为 `proxy/.env` 并填入 Key：
```bash
cp proxy/.env.example proxy/.env
```

### 3. 一键启动全套生态
```powershell
powershell scripts\start-all.ps1
```
会自动拉起网关池、激活 Herdr 后台会话并完成自检。

### 4. 安装 Agent 技能
- **Claude Code**:
  ```powershell
  Copy-Item skills/subclaw.claude.md ~/.claude/commands/subclaw.md
  ```
- **Kimi Code**:
  ```powershell
  Copy-Item skills/subclaw.kimi.md ~/.kimi-code/skills/subclaw/SKILL.md
  ```

---

## 🛠️ 使用指令

```powershell
# 1. 派发任务 (默认开启 DeepSeek 牧羊犬质检闭环)
powershell runner\herdr-pool.ps1 -Dispatch "扫描项目中的 TypeScript 类型隐患并修复" -Profile flash -Name w1

# 2. 异步非阻塞派发 (立即返回，后台运行)
powershell runner\herdr-pool.ps1 -Dispatch "重构认证模块" -Profile deepseek -Async -Name w2

# 3. 读取 Worker 产出与日志
powershell runner\herdr-pool.ps1 -Read w1

# 4. 查看当前所有 Worker 状态
powershell runner\herdr-pool.ps1 -Status

# 5. 手动运行质检
powershell runner\herdr-pool.ps1 -Verify w1 -Task "任务描述"

# 6. 回收清理 Worker Pane
powershell runner\herdr-pool.ps1 -Clean w1

# 7. 进入 Herdr 全屏终端看板
powershell scripts\start-herdr.ps1
```

---

## ⚙️ 模型档位矩阵 (Profiles)

| 档位 Profile | 默认模型 | 默认端口 | 角色与典型应用场景 |
|---|---|---|---|
| `flash` | `sensenova-6.8-flash-lite` | `:1458` | 羊群（Worker）：初筛扫描、批量初稿、文件分类、轻量修改 |
| `deepseek` | `deepseek-v4-flash` | `:1457` | 牧羊犬（Verifier）：深度逻辑推理、架构审查、跨文件重构、产物质检 |
| `glm` | `glm-5.2` | `:1456` | 羊群（Worker）：超长上下文阅读、复杂业务代码编写 |

---

## 🔄 上游组件无损升级

当 Herdr 或 Cockpit Tools 官方发布新版本时，无需担心代码污染，运行一键更新：
```powershell
powershell scripts\update-all-upstreams.ps1
```
- `vendor/herdr` 自动同步最新 release 二进制；
- `proxy/sidecars/cockpit-cliproxy` 自动从上游同步源码；
- `orchestrator/` 业务逻辑与适配层保持完好。
