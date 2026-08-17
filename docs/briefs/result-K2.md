# result-K2 — 三模块接入 + 全链路数据流 设计要点

> 车道 K2 ｜ 交付：`docs/rounds/R15b-armor-modules-design.md`
> 证据协议：`[CLAIM] 结论 | evidence: 文件:行 | confidence`

## 设计要点（10 条）

1. **三模块共享一个云端出口**：Face/Profile/Gathering 的明文数据送云端时最终都汇聚到 `LlmEgressGateway.complete()`（`src/dragnet/egress/gateway.py:85`）。ArmorOn 在 `redact()` 之后（`:112-115`）、ArmorOff 在 `content=` 响应处（`:164`）。一处挂接覆盖三模块，Profile 改造成本 = 0 行业务代码。
   `[CLAIM]` egress 网关是唯一穿甲边界 | evidence: `gateway.py:85,112-115,164` | confidence: high

2. **Face 改造量最小**：本地识别（`Spotter`/pgvector）、本地录入（`EnrollService`）全部不穿甲。唯一钩子在 `DeepFaceClient`（`deepface_client.py:30,37`）——仅当 `DEEPFACE_URL` 指向云端视觉 API 时，对伴随文本元数据穿甲；图像字节流永不穿甲；默认直通，本地容器路径零影响。

3. **Profile 零业务改动**：`Logbook.get_profile()`（`logbook.py:24`）保持明文读写；穿甲不在 Profile 内，在共享出口。规格书 §2"本地库永远明文"得到遵守——"档案穿甲后入库"已被否决。

4. **Gathering 产品化目标**：把 `run_pipeline.py` 四阶段（`phase1_search`→`phase2_encrypt`→`phase3_generate`→`phase4_decrypt`，`run_pipeline.py:59,176,220,346`）映射到 `src/dragnet/research/` 已有基础设施（`ResearchWorkflow` 状态机 `workflow.py:31` + `ResearchStore` `store.py:32` + `CrawlerRegistry`/`select_server` `registry.py:65,193` + `GptrAdapter` `gptr.py:115`），而非另起炉灶。

5. **YAML 工作流 schema**：步骤带 `armored: bool` 字段标注每步信任区（`search`=明文 / `armor_on`=边界转换 / `llm_generate`=密文 / `persist`=明文落盘）。引擎按 schema 执行，替代 `run_pipeline.py` 硬编码四阶段。新增 `src/dragnet/research/engine.py` + `workflow_defs/*.yaml`。

6. **token 契约模板数据驱动**：`run_pipeline.py:246-269` 硬编码的"组3模式"system prompt（token 含义定义 + 强制原样保留）做成可配置模板 `render_token_contract(wordlist_version)`，从 Armor 词表自动渲染契约段；词表热更新后下一次研究即用新契约段。新增 `src/dragnet/research/prompt_contract.py`。

7. **采集结果明文落盘**：原始素材 `reports/raw_search_*.json` 与最终报告 `reports/final_report_*.md` 是明文区产物，档案模块可读可入档；密文过渡态 `encrypted_*.json/md` 仅 Gathering 引擎内部、不入档。报告也可经 `ResearchStore.append_artifact()`（`store.py:337`）作为 CLAIM/EVIDENCE 制品落库。

8. **回退路由接口占位**：`LlmEgressGateway.complete()` 当前 4xx 直接 `fail()`（`gateway.py:153-161`），改为内容拦截时转 `FallbackRouter.handoff(topic, armored_context)` → 本地 Dify（K4 实现），以 MCP 工具 `gather_handoff(topic)→artifact_path` 暴露（规格书 §8）。Phase B 前为 `NotImplementedError`。

9. **时序图与真实代码对齐**：两张 mermaid 图的组件名全部用真实模块名（`McpServer`/`ResearchWorkflow`/`ResearchStore`/`CrawlerRegistry`/`LlmEgressGateway`/Trawler-mcp/云端 sensenova/`reports/`），每条消息标注明文区/密文区，符合规格书 §2 信任边界。

10. **prompt_sanitizer 退役**：`src/dragnet/util/prompt_sanitizer.py` 的语义别名（"朱镕基"→"该前总理"）不可逆、不可控，是 Armor 的反面教材；Armor 用不透明 token `[PERS_K1]` 100% 可逆地取代，上线后 sanitizer 退役。

## 关键决策与理由

- **为什么穿甲落点在 egress 网关而非各模块内部**：信任边界只有一个（云端 LLM 出口/入口）。在 `LlmEgressGateway.complete()` 一处挂接，保证所有送云端路径都经过穿甲，无法绕过；若分散到三模块各自实现，必然遗漏且重复。Profile 因此零改动。
- **为什么图像字节流不穿甲**：Armor 是文本边界编解码器，对二进制图像无意义；云端视觉模型直接看原图。只有伴随文本元数据（人名/任务描述）才穿甲。
- **为什么 Gathering 复用 `research/` 已有基础设施而非改 run_pipeline.py**：规格书 §11 明确 run_pipeline.py 不删不改（其硬编码 key 是反面教材）；`research/` 已有成熟状态机/持久化/审计/爬虫编排，产品化复用它们而非重造。
- **为什么 token 契约要数据驱动渲染**：`run_pipeline.py` 硬编码契约段与词表脱节，词表增删后契约段不会同步，导致云端模型不知道新 token 含义。数据驱动渲染保证契约段随词表版本走。

## 遗留问题

- R1：`LlmEgressGateway` 当前非流式（`httpx.post` `gateway.py:132`），nanobot 聊天是流式；ArmorOff 流式 token 边界缓冲落点需 K1/K3 协同（属 K1 引擎）。
- R2：`run_pipeline.py:283` 的 `requests.post` 直连 sensenova 绕过网关，产品化引擎必须改走 `LlmEgressGateway` 否则穿甲无从挂接。
- R4：YAML 步骤与 `ResearchState` 状态转换的精确映射需 Phase B 细化。
- R5：`FallbackRouter`/`gather_handoff` 的 Dify 侧实现属 K4，本设计只占位。
- R6：契约段渲染依赖 K1 词表 `note` 字段为脱敏释义，否则契约段本身成泄露面。

[WORKER_DONE] status: OK
