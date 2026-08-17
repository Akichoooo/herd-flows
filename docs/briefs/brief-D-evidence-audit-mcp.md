# Brief D：证据链与引用审计接入 MCP（WP-B 核心）

## 背景
研究运行时已有契约（EvidenceSpan/EvidenceClaim/CitationAuditResult）、
CitationAuditor、ResearchWorkflow 的 AUDITING/REPAIRING 分支，但 Agent 无法把
"主张-证据"写入研究任务、也无法触发审计。本任务补齐这条链路，让报告质量
由确定性门禁把关（这是"AI 自我校正"的受控实现）。
必读：
1. `outputs/Dragnet研究型Agent-P0工程实施基线.md` §5.3（Citation Auditor）
2. `src/dragnet/contracts/research.py`（EvidenceSpan/EvidenceClaim/CitationAuditResult/ArtifactKind）
3. `src/dragnet/research/store.py`（append_artifact）、`auditor.py`、`workflow.py`（complete_audit/begin_repair）
4. `src/dragnet/mcp/server.py`（现有 13 个工具的注册与分发方式，含 4 个研究工具）

## 任务：在 mcp/server.py 新增 3 个工具
1. `add_research_evidence(research_id, evidence: [{source_id, quote, locator, source_content_hash?, screenshot_ref?}])`
   → 逐条构造 EvidenceSpan（evidence_id 自动生成 `E-<seq>`），
   以 ArtifactKind.EVIDENCE 存入 research_artifact（metadata 放完整 span JSON，
   content_hash = sha256(canonical_json(span))）；返回 evidence_id 列表。
2. `add_research_claims(research_id, claims: [{text, claim_type, importance, evidence_ids, support_status, confidence, conflicts?}])`
   → 构造 EvidenceClaim（claim_id 自动 `C-<seq>`），ArtifactKind.CLAIM 存储；
   契约校验失败时返回该条的 pydantic 错误信息（不整批失败）。
3. `audit_research_report(research_id, report_version)`
   → 从 research_artifact 读回全部 ACTIVE 的 EVIDENCE/CLAIM（按 created_at 序），
   调 CitationAuditor.audit，审计结果以 ArtifactKind.AUDIT 存储；
   审计通过 → 经 workflow 推进 FINALIZED；不通过 → 推进 REPAIRING，
   返回 audit 明细 + 缺口清单（哪些 claim 缺证据/冲突未披露）供 Agent 定向修复。
   状态推进一律走 ResearchWorkflow，遵循现有状态机（先确保 run 处于 DRAFTING/AUDITING 等合法前置态，非法前置态返回错误说明而不是抛栈）。

## 约束
- ActorContext 复用 McpServer 已注入的 research actor（同 start_research）。
- 工具只接受业务参数；evidence/claim 的 JSON schema 写进 inputSchema。
- `test_mcp_server.py` 的 tools/list 断言同步更新（13 → 16）；FakeMcpServer 补分支。
- 新增 `tests/unit/test_research_evidence_tools.py`：fake store 覆盖
  add evidence → add claims → audit 通过/不通过两条路径、非法状态拒绝、
  坏 claim 单条报错不毁批。

## 范围外
LLM 自动抽取主张（由 nanobot Agent 侧负责）、报告正文存储、REST API、git commit。

## 门禁（全过才算完成）
```
.venv\Scripts\python.exe -m ruff format src tests
.venv\Scripts\python.exe -m ruff check src tests
.venv\Scripts\python.exe -m mypy
.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract" --timeout 120
```
完成后写 `docs/subclaw-briefs/result-D.md`。
**不要碰** src/dragnet/research/registry.py、.nanobot/workspace/*.yaml、
crawler 相关配置（另一个 worker 在改）。
