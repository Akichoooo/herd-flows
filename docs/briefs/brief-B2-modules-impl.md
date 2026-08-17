# Brief B2：egress 挂接 + Gathering 工作流引擎 — 实施

**前置：B1 已完成（`src/dragnet/armor/` 可用）。** 你是 GLM worker，在 Dragnet 仓库根目录一次性执行。本次是**实施**任务。禁止 git 任何操作。

## 先读

1. `docs/rounds/R15b-armor-modules-design.md` — 你的设计文档
2. `docs/subclaw-briefs/review-R15-integration.md` §二§三（裁决）
3. `docs/subclaw-briefs/result-B1.md` — B1 的实际交付（引擎真实签名以代码为准，不以设计文档为准）
4. `src/dragnet/armor/`（B1 产物，只 import 不修改）、`src/dragnet/egress/gateway.py`、`src/dragnet/research/`（workflow.py / store.py / registry.py / adapters/gptr.py）、`src/dragnet/mcp/server.py`

## 文件所有权（只许动这些，越界即失败）

- `src/dragnet/egress/gateway.py`（ArmorOn/ArmorOff 挂接）
- 新建 `src/dragnet/research/engine.py`、`src/dragnet/research/prompt_contract.py`、`src/dragnet/research/workflow_defs/*.yaml`
- `src/dragnet/mcp/server.py` —— 只加 `gather_handoff` 工具块（B1 的 armor 块已存在，别动）
- 新建相关测试 `tests/unit/test_research_engine*.py`、`tests/unit/test_egress_armor*.py` 等

**禁止碰**：`src/dragnet/armor/**`、`dragnet-settings.js`、`enroll/**`、`run_pipeline.py`（它是反面教材参考，一行不改）。

## 交付内容

1. **egress 挂接**（R15b §设计）：`LlmEgressGateway.complete()` 中，ArmorOn 落在 DLP redact 之后（`:112-115` 循环内）、`sent_bytes` 之前；ArmorOff 落在响应 `content=` 取出处（`:164`）；审计事件与 egress 同 trace。穿甲开关走 config（`DRAGNET_ARMOR_ENABLED`），关闭时行为与现状完全一致（回归零差异）。
2. **多轮重穿甲**：对 `request.messages` 全量（含历史 assistant 消息）逐条 ArmorOn；system 消息注入 armor.contract 渲染的契约段（调 `dragnet.armor` 的渲染器，`research/prompt_contract.py` 只做薄包装）。
3. **Gathering 工作流引擎**：`research/engine.py` 按 YAML schema 执行（步骤含 `armored: bool` 信任区标注），复用 `ResearchWorkflow` 状态机 + `ResearchStore` 持久化 + `CrawlerRegistry` 选源；`workflow_defs/` 内置一个等价 run_pipeline 四阶段的默认 YAML；LLM 调用一律走 `LlmEgressGateway`（R15b-R2：禁止绕过网关直连）。
4. **回退路由**：`complete()` 收到内容拦截类 4xx 时转 `FallbackRouter.handoff(topic, armored_context)`；MCP 工具 `gather_handoff(topic) -> artifact_path` 注册进 server.py；Dify 侧未就绪则落盘素材 + 返回路径（B4 的 PoC 产物可消费），不抛 NotImplementedError 给最终调用方。
5. **采集结果明文落盘**：密文过渡态仅引擎内部；最终报告明文写 `reports/`，可经 `ResearchStore.append_artifact()` 入档。
6. **测试**：挂接开关开/关两态、契约段渲染同步词表版本、YAML 引擎端到端（mock LLM/爬虫）、回退路由触发路径。

## 门禁（全绿才算完成）

```
.venv\Scripts\python.exe -m ruff format src tests
.venv\Scripts\python.exe -m ruff check src tests
.venv\Scripts\python.exe -m mypy
.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract or property or security" --timeout 120
```

## 收尾

写 `docs/subclaw-briefs/result-B2.md`：交付清单、挂接点最终行号、测试结果、遗留问题。
最后输出 `[WORKER_DONE] status: OK|PARTIAL|FAIL`，关键结论带 `[CLAIM] ... | evidence: 文件:行 | confidence: ...`。
