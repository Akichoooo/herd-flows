# herd-flows

herdr 驱动的动态 worker 池 + 验证者循环。编排者派活 → herdr 养一群 claude worker 在 pane 里干 → 验证者监督放行/打回 → 经 cockpit-cliproxy 网关出海到 SenseNova。省主编排者 token：FAIL 循环在验证者层消化，编排者只看合格品。

## 架构

```
编排者（claude / kimi，任意 CLI agent）
  │  runner/herdr-pool.ps1 -Dispatch
  ▼
herdr session 'subclaw'（终端牧场，断线不死，状态感知 idle/working/blocked）
  ├── pane: worker (claude CLI + --settings 注入网关)
  ├── pane: worker (claude CLI)
  └── pane: verifier (claude CLI, deepseek 档)
       │  FAIL → prompt 打回 worker 重做（不打扰编排者）
       ▼
cockpit-cliproxy 网关池 :1456-1459（每端口一 SenseNova key）
  └── SenseNova 上游（glm-5.2 / deepseek-v4-flash / 6.8-flash-lite）
```

## 目录结构

| 路径 | 内容 |
|------|------|
| `runner/herdr-pool.ps1` | 引擎中立 runner（dispatch/read/status/verify/clean） |
| `runner/config.json` | 网关池端口、profiles、验证者 prompt 模板 |
| `gateway/compose.subclaw-pool.yml` | 4-key cliproxy 池（:1456-1459） |
| `gateway/.env.example` | 4-key 占位模板（真实 .env 不入库） |
| `gateway/Dockerfile.cockpit-cliproxy` | cliproxy 镜像构建（自包含，不依赖外部仓库） |
| `gateway/docker/` | cliproxy 构建辅助文件 |
| `skills/subclaw.claude.md` | Claude Code 入口技能 |
| `skills/subclaw.kimi.md` | Kimi Code 入口技能 |
| `scripts/install-deps.ps1` | 依赖安装 + 自检（herdr/docker/cliproxy image/claude CLI） |
| `docs/ADR-001-architecture.md` | 架构决策记录 |
| `docs/briefs/` | subclaw 历史设计 brief + 结果（armor/face-enroll/crawler 等） |
| `legacy/` | 旧版 claw-proxy 时代归档（run-claw-pool.sh 等，不再使用） |

## 快速开始

### 1. 安装依赖
```powershell
powershell scripts\install-deps.ps1
```
自动装 herdr（Windows beta）、验证 Docker、build cliproxy image、检查 claude CLI。

### 2. 启动网关池
```bash
cp gateway/.env.example gateway/.env    # 填 4 个 SenseNova key
docker compose -f gateway/compose.subclaw-pool.yml --env-file gateway/.env up -d
```

### 3. 安装技能入口
```powershell
# Claude Code
Copy-Item skills/subclaw.claude.md ~/.claude/commands/subclaw.md
# Kimi Code
Copy-Item skills/subclaw.kimi.md ~/.kimi-code/skills/subclaw/SKILL.md
```

### 4. 自检
```powershell
powershell runner\herdr-pool.ps1 -Ensure
# 应见: [ok] herdr session 'subclaw' 运行中 / [ok] gateway :1456-1459
```

## 用法

```powershell
# 派活（验证者默认开）
powershell runner\herdr-pool.ps1 -Dispatch "<task>" -Profile flash -Name w1
# -Profile: flash(6.8-flash-lite,:1458) | deepseek(:1457) | glm(:1456)
# -NoVerify 跳过验证者

# 读 worker 输出
powershell runner\herdr-pool.ps1 -Read w1
# 查状态
powershell runner\herdr-pool.ps1 -Status
# 清理 worker
powershell runner\herdr-pool.ps1 -Clean w1
```

## 依赖

| 组件 | 说明 | 安装 |
|------|------|------|
| herdr 0.8+ | 终端牧场，状态检测 | `irm https://herdr.dev/install.ps1 \| iex` |
| Docker | 网关池运行环境 | Docker Desktop |
| cockpit-cliproxy | 多协议 LLM 网关 | `scripts/install-deps.ps1` 自动 build |
| claude CLI | worker 执行引擎 | `npm i -g @anthropic-ai/claude-code` |
| SenseNova key | 上游模型供应商 | console.sensenova.cn → API Keys |

## 血统

延续 Dragnet（天网/拖网）+ Trawler（拖网渔船）生态。herd-flows 是"群工作流"层——herdr 本意 herd（放牧），编排者=牧人，worker=羊群，验证者=牧犬。

## 设计细节

见 `docs/ADR-001-architecture.md`（架构决策记录：为什么三层分离、踩过的坑、被否决的替代方案）。
