# Brief G：技能与路由切换到研究运行时（WP-E 第一步）

## 背景
研究运行时 MCP 工具已就绪（dragnet MCP 现有 16 个工具，含：
start_research / get_research_status / add_research_evidence / add_research_claims /
audit_research_report / build_research_package / stage_research_package）。
现在把场景技能与全局路由切到"研究运行时优先、gptr/内置兜底"。
先读 `src/dragnet/mcp/server.py` 的 tools/list 拿到准确工具名与参数。

## 任务
### 1. `.nanobot/workspace/AGENTS.md`
- 工具清单新增"研究运行时 — dragnet MCP"小节，列出上述 7 个研究工具（一句话用途）；
- 路由规则第 3 条（深度调研）改为：先 `mcp_dragnet_start_research` 建研究任务
  （mode 按意图：调查/尽调→strong，写文章→deep），素材采集优先走研究任务内的
  来源与证据工具；`mcp_gptr_deep_research` 降为研究任务内的采集手段之一；
- 成文硬规则补一条：deep/strong 档报告落盘前必须经过
  `mcp_dragnet_audit_research_report`，审计不过按缺口清单定向修复后重审；
- 其余内容不动。
### 2. 技能更新（保持各技能 SOP 骨架，只换工具路径）
- `skills/incident-research/SKILL.md`：删除"目标态"注记，把第 2、4 步改为
  start_research(strong/deep) → 证据/主张写入 → audit → 落盘；保留反证与冲突并列规则；
- `skills/person-research/SKILL.md`、`skills/public-opinion/SKILL.md`、
  `skills/donor-dig/SKILL.md`、`skills/news-scan/SKILL.md`：同样在第 1 步后插入
  "start_research 建任务、落盘前过 audit"，其余维度与结构不变；
- `skills/daily-digest/SKILL.md`：定时触发一节补充——每次运行先查上一次研究的
  checkpoint（get_research_status），无新增材料时输出"无重大变化"，不重复成文。
### 3. `docs/Dragnet使用手册.md`
- "技能一览"表后加一小节"研究任务与质量门禁"：说明 start_research/audit 的作用、
  报告质量卡（来源数/引用覆盖率/未决事项）会随摘要返回；
- 其余不动。

## 约束
- 只改上述 8 个 markdown 文件，不碰任何代码与测试；
- 技能里引用的工具名必须与 server.py tools/list 完全一致（逐个核对）；
- 改完自检：每个技能仍能被 AGENTS.md 的技能路由命中（触发词不变）。

## 门禁
不涉及代码门禁；交付前用 `grep -r "mcp_dragnet_start_research" .nanobot/workspace`
确认 6 个技能都接上。完成后写 `docs/subclaw-briefs/result-G.md`
（改动清单 + 每个技能的新流程 3 行摘要）。不要 git commit。
**不要碰** src/、tests/、pyproject.toml、crawler-*.yaml（另一个 worker 在改）。
