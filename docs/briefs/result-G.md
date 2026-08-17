# Brief G 结果 — 技能与路由切换到研究运行时（WP-E 第一步）

> 日期：2026-08-10
> 状态：完成
> 范围：仅 8 个 markdown 文件，未触碰任何代码/测试/配置。

## 背景核对的工具名（来自 `src/dragnet/mcp/server.py` tools/list）

| MCP 工具名（nanobot 前缀 mcp_dragnet_） | 用途 | 关键参数 |
|------|------|----------|
| `mcp_dragnet_start_research` | 建研究任务，返回 research_id | query(必填), mode: quick/broad/deep/strong, skill_id, focus |
| `mcp_dragnet_get_research_status` | 取研究状态/checkpoint | research_id |
| `mcp_dragnet_add_research_evidence` | 写证据（来源+引用） | research_id, evidence[] |
| `mcp_dragnet_add_research_claims` | 写主张（事实/推断+支持状态） | research_id, claims[] |
| `mcp_dragnet_audit_research_report` | 引文审计/质量门禁，返回缺口清单 | research_id, report_version |
| `mcp_dragnet_build_research_package` | 打包素材 | research_id, report_version |
| `mcp_dragnet_stage_research_package` | 交付到目标工作区 | research_id, report_version, target_workspace, target_category |

## 改动清单

| 文件 | 改动 |
|------|------|
| `.nanobot/workspace/AGENTS.md` | 工具清单新增"研究运行时 — dragnet MCP"小节（7 工具）；路由规则第 3 条改为先 start_research（调查/尽调→strong，写文章→deep），素材采集优先走任务内工具，gptr_deep_research 降为采集手段之一；成文硬规则补第 8 条质量门禁（deep/strong 档落盘前必须过 audit_research_report，不过按缺口清单修复后重审）。其余内容未动。 |
| `skills/incident-research/SKILL.md` | 删除"目标态"注记；第 2 步改为 start_research 建任务（按意图选 strong/deep），素材走 add_research_evidence；第 4 步改为 add_research_claims + audit 后落盘；保留反证与冲突并列规则。 |
| `skills/person-research/SKILL.md` | 第 1 步后插入"建研究任务"（start_research）；素材采集改走任务内证据工具；落盘前加 audit；长任务步号同步为 4-6。 |
| `skills/public-opinion/SKILL.md` | 第 1 步后插入"建研究任务"；素材采集改走任务内证据工具；落盘前加 audit。其余维度/结构不变。 |
| `skills/donor-dig/SKILL.md` | 同上：插入建任务、素材走证据工具、落盘前 audit。 |
| `skills/news-scan/SKILL.md` | 同上：插入建任务、素材走证据工具、落盘前 audit。 |
| `skills/daily-digest/SKILL.md` | 定时触发节补充：每次运行先调 get_research_status 查上次研究 checkpoint，无新增材料输出"无重大变化"，不重复成文。 |
| `docs/Dragnet使用手册.md` | "技能一览"表后新增小节"3.1 研究任务与质量门禁"：说明 start_research/audit 作用、报告质量卡（来源数/引用覆盖率/未决事项）随摘要返回。 |

## 每个技能的新流程（3 行摘要）

- **incident-research**：定边界 → start_research(strong/deep) 建任务 → 素材采集走任务内来源与证据工具（含反证检索，冲突并列）→ 关联人物补本地档案 → add_research_claims + audit 通过后落盘。
- **person-research**：定身份（照片/名字）→ start_research 建任务 → 本地档案 + 任务内素材采集（gptr 作采集手段）→ 交叉验证 → add_research_claims + audit 通过后成文落盘。
- **public-opinion**：定目标与窗口 → start_research 建任务 → 素材采集走任务内证据工具 → 区分事实与观点 → add_research_claims + audit 通过后成文落盘。
- **donor-dig**：定身份 → start_research 建任务 → 素材采集走任务内证据工具 → add_research_claims + audit 通过后成文落盘（金额必须带来源）。
- **news-scan**：定身份 → start_research 建任务 → 素材采集走任务内证据工具 → add_research_claims + audit 通过后成文落盘（每条新闻带日期来源）。
- **daily-digest**：先试跑确认格式 → 建 cron 任务 → 每次运行先 get_research_status 查上次 checkpoint，无新增材料输出"无重大变化"不重复成文；有新增才按模板成文落盘。

## 自检结果

- `grep -r "mcp_dragnet_start_research" .nanobot/workspace` → 命中 6 个文件
  （5 个调用 start_research 的技能 + AGENTS.md；daily-digest 按 brief 用 get_research_status 复用上次研究，不新建任务）。
- 6 个技能路由命中核对：AGENTS.md 第 3 条技能路由（person-research / donor-dig / news-scan /
  incident-research / public-opinion / daily-digest）与各技能 frontmatter `description` 触发词一致，未改动，命中不受影响。
- 技能内引用的工具名逐个与 server.py tools/list 核对，均以 `mcp_dragnet_` 前缀精确匹配。

## 门禁

不涉及代码门禁（纯 markdown 变更）。未 git commit。未触碰 src/、tests/、pyproject.toml、crawler-*.yaml。