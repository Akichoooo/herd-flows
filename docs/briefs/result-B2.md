# result-B2 — egress 挂接 + Gathering 工作流引擎 实施总结

> 车道 B2（K2 落地）｜ 阶段 Phase B ｜ 严格按 R15b 设计实施
> 禁止碰 armor/**、dragnet-settings.js、enroll/**、run_pipeline.py（均未触碰）

## 交付清单

### 修改文件

| 文件 | 改动 | 挂接点最终行号 |
|---|---|---|
| `src/dragnet/egress/gateway.py` | import Armor/TokenContractBuilder；`FallbackRouter` 类；`__init__` 加 armor/armor_enabled/fallback 参数；出口 ArmorOn（DLP redact 后、sent_bytes 前）；入口 ArmorOff（content 取出后）；4xx 回退 FallbackRouter.handoff；`_armor_egress` 方法（全 messages ArmorOn + system 前置契约段） | FallbackRouter:74,handoff:84；__init__:100-115；出口:149-150；4xx 回退:188-200；入口:213-214；_armor_egress:251-269 |
| `src/dragnet/mcp/server.py` | tools/list 注册 gather_handoff（:596）；_call_tool 加 gather_handoff 分发（:740，调 FallbackRouter.handoff 落盘返回路径）。B1 的 armor 块未动 | gather_handoff:596,740 |

### 新建文件

| 文件 | 职责 |
|---|---|
| `src/dragnet/research/prompt_contract.py` | `render_token_contract(wordlist)` 薄包装 `dragnet.armor.contract.TokenContractBuilder`（全系统唯一实现，不另起） |
| `src/dragnet/research/engine.py` | `GatheringEngine` 按 YAML schema 执行四阶段；`WorkflowStep`/`WorkflowDef`/`load_workflow`/`GatheringResult`；`LlmCaller` protocol + `SearchFn` 类型；LLM 走注入 gateway（R15b-R2 不直连） |
| `src/dragnet/research/workflow_defs/incident-research.yaml` | 等价 run_pipeline 四阶段的默认 YAML（search→armor_on→llm_generate→persist，每步 armored 标注信任区） |
| `tests/unit/test_egress_armor.py` | 挂接开关开/关两态、契约段注入（无system/有system）、4xx 回退触发/无fallback报错 |
| `tests/unit/test_research_engine.py` | YAML 引擎端到端（mock gateway/爬虫）、armor_on 穿甲素材验证、未知 step kind 报错 |

## 挂接点设计要点

1. **信任边界**（规格书 §2）：ArmorOn 落 `complete()` 出口 DLP redact 之后（:149-150），密文区从 sent_bytes 起；ArmorOff 落入口 content 取出后（:213-214），密文区结束。搜索/本地 DB 永远明文，不穿甲。
2. **多轮重穿甲**（规格书 §2 推论1）：`_armor_egress`（:251）对全 messages（含历史 assistant）逐条 ArmorOn；无 system 时注入契约段，有 system 时前置到头部（:259-265）。词表热更新后下次请求即用新契约段。
3. **关闭态零差异**：`armor_enabled=False`（默认）时 `_armor_egress` 不执行、入口 `if self._armor is not None` 不触发，行为与现状完全一致（测试 `TestArmorDisabled` 验证 payload 含明文、不穿甲）。
4. **4xx 回退**（规格书 §8）：`400 <= status < 500` 且 armor_enabled 且 fallback 注入 → `FallbackRouter.handoff`（:188-200）落盘穿甲素材返回路径，不抛 NotImplementedError；无 fallback 时沿用原 fail（测试覆盖两态）。
5. **契约段唯一实现**：`prompt_contract.render_token_contract` 只包装 `TokenContractBuilder`；gateway `_armor_egress` 也直接调 `TokenContractBuilder`，无重复渲染逻辑，随词表版本自动同步。
6. **Gathering 引擎**：engine 不重复穿甲逻辑——`armor_on` step（Phase2）穿甲素材为 armored_context；`llm_generate` step 把 armored_context 作 user message 传 gateway，gateway 内部 ArmorOn（幂等，token 不动）+ 注入契约段 + ArmorOff。密文过渡态仅引擎 ctx 内部，最终明文落盘 `reports/`。
7. **采集结果明文落盘**（§6.5）：`_persist` 写 `reports/<name>_<ts>.md`（明文），档案模块可读；`report_path` 单独返回，`final_report` 为内容。

## 门禁结果（全绿）

```
ruff format src tests          → 126 files unchanged (3 微调)
ruff check src tests           → All checks passed!
mypy                           → Success: no issues found in 87 source files
pytest -m "unit or contract or property or security"
                               → 434 passed, 73 deselected in 6.82s
```

## 测试覆盖

- `TestArmorDisabled`：关闭态 payload 明文不穿甲（零差异回归）。
- `TestArmorEnabled`：出口穿甲 + 入口卸甲；无 system 注入契约段；有 system 前置契约段。
- `TestFallback`：4xx 触发 handoff 返回落盘路径；无 fallback 时抛 DragnetError（沿用既有 fail）。
- `TestGatheringEngine`：四阶段 steps_run 顺序；armor_on 穿甲素材传入 gateway（含 token、不含明文关键词）；落盘文件内容=final_report；未知 step kind 报错。

## 遗留问题

- **R1**：`DRAGNET_ARMOR_ENABLED` 开关目前通过 `__init__(armor_enabled=...)` 注入；上层（MCP server/proxy 启动）需读环境变量并传入，B2 只在 gateway 层暴露开关，未改 server/proxy 启动逻辑（B3/B4 接入运行时配置）。
- **R2**：Gathering 引擎的 search step 用注入的 `search_fn`（mock），真实搜索需接 `CrawlerRegistry.select_server` + gptr/trawler 适配——engine 已留 `capability` 字段对齐，真实接入属后续（B4 爬虫编排）。
- **R3**：`gather_handoff` 工具当前用 `topic` 作 armored_context 占位落盘；真实素材应从 ResearchStore 取当前 run 素材——需 B4 衔接 run 上下文。
- **R4**：`_start_research()`（server.py:706）未接入 GatheringEngine（R15b §8.2 建议）；B2 只建引擎与默认 YAML，接入 _start_research 的编排需与既有状态机协调（避免与 ResearchWorkflow 重复），留后续。
- **R5**：流式 ArmorOff 落点——gateway.complete 是非流式整包；流式聊天走 B1 的 Armor Proxy（StreamingRestorer），本车道 gateway 入口卸甲覆盖非流式路径，流式由 proxy 承担。

> [CLAIM] ArmorOn/Off 唯一落点为 LlmEgressGateway.complete() 出口(:149)/入口(:213)，关闭态零差异 | evidence: src/dragnet/egress/gateway.py:149,213,251; tests/unit/test_egress_armor.py | confidence: high
> [CLAIM] Gathering YAML 引擎四阶段端到端跑通（mock LLM/爬虫），穿甲素材经 gateway 不直连 | evidence: tests/unit/test_research_engine.py; src/dragnet/research/engine.py:118 | confidence: high
> [CLAIM] 4xx 内容拦截转 FallbackRouter 落盘返回路径，不抛 NotImplementedError | evidence: gateway.py:188-200,84; tests/unit/test_egress_armor.py TestFallback | confidence: high
> [RISK] DRAGNET_ARMOR_ENABLED 运行时接入与 _start_research 编排待 B3/B4（R1/R4）

[WORKER_DONE] status: OK
