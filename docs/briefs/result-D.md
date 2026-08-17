# Brief D 结果 — 证据链与引用审计接入 MCP（WP-B 核心）

> 日期：2026-08-10
> 状态：完成

## 交付物

| 文件 | 说明 |
|------|------|
| `src/dragnet/mcp/server.py` | 新增 `add_research_evidence`、`add_research_claims`、`audit_research_report` 三个工具（含 tools/list 注册、_call_tool 分发、handler 方法） |
| `src/dragnet/research/workflow.py` | 新增 `begin_audit` 方法（DRAFTING → AUDITING，不注册新版本） |
| `tests/unit/test_research_evidence_tools.py` | 新增 21 项单测：evidence/claim/audit 全路径 |
| `tests/unit/test_mcp_server.py` | FakeMcpServer 已补上三个 WP-B 分支 + tools/list 断言 15 个工具名 |
| `tests/unit/test_research_mcp_tools.py` | FakeResearchMcpServer 新增三个 WP-B 方法（含 fake store 实现） |
| `tests/unit/test_research_workflow.py` | 新增 `begin_audit` 方法测试 |

## 实现要点

### 三个 MCP 工具

1. **`add_research_evidence(research_id, evidence)`**
   - 逐条构造 `EvidenceSpan`，evidence_id 自动编号 `E-<seq>`
   - 以 `ArtifactKind.EVIDENCE` 存入 `research_artifact`，metadata 为 span 完整 JSON
   - content_hash = sha256(canonical_json(span))
   - 返回 `{research_id, evidence_ids: [str]}`

2. **`add_research_claims(research_id, claims)`**
   - 构造 `EvidenceClaim`，claim_id 自动编号 `C-<seq>`
   - 以 `ArtifactKind.CLAIM` 存储，metadata 为 claim 完整 JSON
   - 契约校验失败（如 supported 声明无 evidence）返回该条 pydantic 错误信息，不毁整批
   - 返回 `{research_id, claim_ids: [str], errors: [{claim_id, error}]}`

3. **`audit_research_report(research_id, report_version)`**
   - 状态前置检查：仅允许 DRAFTING / AUDITING / REPAIRING
   - 自动推进：REPAIRING → DRAFTING（begin_repair）→ AUDITING（begin_audit）；DRAFTING → AUDITING（begin_audit）
   - 从 `research_artifact` 读回 ACTIVE 的 EVIDENCE/CLAIM，调 `CitationAuditor.audit`
   - 审计结果以 `ArtifactKind.AUDIT` 存储
   - 审计通过 → `FINALIZED`；不通过 → `REPAIRING`，返回缺口清单

### Workflow 新增

- **`begin_audit(run)`**：DRAFTING → AUDITING 无版本注册。用于审计工具在版本已注册后仅移动状态，避免 `create_report_version` 重复注册报错。

### 修复的 Bug

- `_audit_research_report` 在 REPAIRING → DRAFTING 路径中，之前的版本已注册，调用 `create_report_version` 会报 "version already exists"。现改为 `begin_audit` 解决。

## 门禁结果

```
ruff format src tests        → 通过（109 files left unchanged）
ruff check src tests         → 全部通过（All checks passed）
mypy                         → 通过（Success: no issues found in 74 source files）
pytest tests -q -m "unit or contract" --timeout 120
                             → 137 passed, 285 deselected（全绿）
```

`tests/unit/test_research_evidence_tools.py` 单独跑：**21 passed**。

## 变更文件
- 修改：`src/dragnet/mcp/server.py`（新增三个工具 + 修复 audit 状态推进）
- 修改：`src/dragnet/research/workflow.py`（新增 `begin_audit`）
- 新增：`tests/unit/test_research_evidence_tools.py`（21 项单测）
- 修改：`tests/unit/test_mcp_server.py`（FakeMcpServer 补分支 + 断言）
- 修改：`tests/unit/test_research_mcp_tools.py`（FakeResearchMcpServer 补三个 WP-B 方法）
- 修改：`tests/unit/test_research_workflow.py`（`begin_audit` 测试）

未 git commit。