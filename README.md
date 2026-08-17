# herd-flows

herdr 驱动的动态 worker 池 + 验证者循环。编排者派活 → herdr 养一群 claude worker 在 pane 里干 → 验证者监督放行/打回 → 经 cockpit-cliproxy 网关出海到 SenseNova。省主编排者 token：FAIL 循环在验证者层消化，编排者只看合格品。

## 架构

```
编排者（claude / kimi，任意 CLI agent）
  │  herdr-pool.ps1 -Dispatch
  ▼
herdr session 'subclaw'（终端牧场，断线不死）
  ├── pane: worker (claude CLI + --settings 注入网关)
  ├── pane: worker (claude CLI)
  └── pane: verifier (claude CLI, deepseek 档)
       │  FAIL → prompt 打回 worker 重做（不打扰编排者）
       ▼
cockpit-cliproxy 网关池 :1456-1459（每端口一 SenseNova key）
  └── SenseNova 上游（glm-5.2 / deepseek-v4-flash / 6.8-flash-lite）
```

## 目录

| 路径 | 内容 |
|------|------|
| `runner/herdr-pool.ps1` | 引擎中立 runner（dispatch/read/status/verify/clean） |
| `runner/config.json` | 网关池端口、profiles、验证者 prompt 模板 |
| `gateway/compose.subclaw-pool.yml` | 4-key cliproxy 池（:1456-1459） |
| `gateway/.env.example` | 4-key 占位模板（真实 .env 不入库） |
| `skills/subclaw.claude.md` | Claude Code 入口技能 |
| `skills/subclaw.kimi.md` | Kimi Code 入口技能 |

## 安装

1. 网关池（一次）：
   ```bash
   cp gateway/.env.example gateway/.env   # 填 4 个 SenseNova key
   docker compose -f gateway/compose.subclaw-pool.yml --env-file gateway/.env up -d
   ```

2. herdr（一次）：`powershell irm https://herdr.dev/install.ps1 | iex`

3. 技能入口（符号链接或复制到引擎扫描位置）：
   - claude: `skills/subclaw.claude.md` → `~/.claude/commands/subclaw.md`
   - kimi:   `skills/subclaw.kimi.md`   → `~/.kimi-code/skills/subclaw/SKILL.md`

4. 自检：`powershell runner\herdr-pool.ps1 -Ensure`（应见 `[ok] gateway :1456-1459`）

## 用法

```powershell
powershell runner\herdr-pool.ps1 -Dispatch "<task>" -Profile flash -Name w1
# -Profile: flash(6.8-flash-lite,:1458) | deepseek(:1457) | glm(:1456)
# 验证者默认开；-NoVerify 跳过
powershell runner\herdr-pool.ps1 -Read w1
powershell runner\herdr-pool.ps1 -Status
powershell runner\herdr-pool.ps1 -Clean w1
```

## 血统

延续 Dragnet（天网/拖网）+ Trawler（拖网渔船）生态。herd-flows 是"群工作流"层——herdr 本意 herd（放牧），编排者=牧人，worker=羊群，验证者=牧犬。
