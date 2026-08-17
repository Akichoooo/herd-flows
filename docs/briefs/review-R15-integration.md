# R15 四车道设计集成评审（审核者：Kimi）

> 评审对象：R15a（K1 核心引擎）/ R15b（K2 模块接入）/ R15c（K3 WebUI）/ R15d（K4 运维三件套）
> 结论：**有条件通过**——一个 P0 架构窟窿需按本文裁决补设，一个 P1 接口命名需对齐，其余进入 Phase B。

## 一、引用真实性抽查（通过）

| 车道 | 抽查引用 | 结果 |
|---|---|---|
| K1/K2 | `egress/gateway.py:85` complete()、`:109-115` DLP redact、`:164` content 取出 | ✅ 逐行属实 |
| K2 | `research/workflow.py:31` ResearchWorkflow、`store.py:32` ResearchStore、`registry.py:65,193` CrawlerRegistry/select_server | ✅ 属实 |
| K4 | `dragnet-settings.js:350-367` 生图 mock stub（setTimeout 复制原图，零 API 调用） | ✅ 属实，根因诊断成立 |
| K4 | `fix_webui_access.ps1:17-19` 端口修复、`docs/R14…md:19` "一期不做生成图" | ✅ 属实 |
| K2 | `deepface_client.py:30,37` DeepFaceClient 钩子 | ✅ 属实 |
| K3 | `dragnet-settings.js:38-54` api() helper、`:489-491` observer 注入点 | ✅ 属实（此前已核读） |

四车道零编造路径，证据协议执行合格。

## 二、P0：聊天链路存在穿甲窟窿（必须补设）

**事实**：`.nanobot/config.json` 中 nanobot 的 chat 模型走 `providers.custom.apiBase = https://freetokenfaucet.com/v1`（model `gpt-5.6-terra`），**完全不经过 Dragnet 的 `LlmEgressGateway`**。

**后果**：K1/K2 把 ArmorOn 挂在 egress gateway，只覆盖 Dragnet 自有工作流（Gathering/研究）的 LLM 调用；而聊天主链路里——

- K3 的浏览器穿甲只盖住**用户手输文字**；
- **MCP 工具结果（Logbook 档案明文、Compass 关系、搜索素材）进入 nanobot 上下文后，下一轮请求明文上云**，审核照样拦截；
- K3 遗留问题#5 假设"历史消息由后端 egress 网关统一重穿甲"——该路径在聊天链路中不存在，假设不成立。

**裁决（方案甲：Armor 代理端点）**：

1. Dragnet 新增 OpenAI 兼容本地代理服务（Armor Proxy，建议 `:18791/v1/chat/completions`），内部流程：收请求 → ArmorOn（全 messages，含历史与工具结果）→ 转发云端 → 流式 ArmorOff（复用 K1 `StreamingRestorer`）→ 返回。
2. `.nanobot/config.json` 的 `providers.custom.apiBase` 改指 Armor Proxy。一处配置改动覆盖整个聊天链路：用户输入、MCP 工具结果、历史消息全部自动穿甲。
3. K3 设计相应**瘦身**：capture 换值、预穿甲缓存、XHR sync 降级全部取消（代理已透明穿甲）；穿甲/卸甲按钮回归纯预览/调试定位；气泡 ArmorOff 回填不再需要（代理返回的已是明文）。
4. Gathering 等 Dragnet 自有工作流仍走 egress gateway 内挂接（K1/K2 设计不变）。两个挂接点、同一 `src/dragnet/armor/` 引擎，词表不出 Dragnet 侧。
5. Armor Proxy 需支持流式 SSE 透传 + token 边界缓冲；nanobot 的 `fallbackModels` 存在，fallback 链也必须指向代理（或全部禁用 fallback）。

## 三、P1：`/api/armor/*` 字段命名三方不一致（对齐裁决）

- K1 定稿：`on → {armored, count, hits, version}`；`off → {text, restored, unknown, version}`
- K2 冲突：`off → {restored: str}`（restored 一为计数一为文本）
- K3 草案：`armored_text / hit_count / digest` 等 + `GET /api/armor/status`（K1 未定义）

**裁决**：一律以 K1 为准；K1 增补 `GET /api/armor/status → {ok, version, digest, loaded_count}`（供 K3 降级探测）；K2 的 `restored: str` 改为 K1 的 `text`；K3 前端 adapter 层吸收命名差异（其设计本已预留）。

## 四、P2 遗留（进 Phase B 任务单，不阻塞）

- `pyahocorasick` Windows wheel 可用性验证，不可用则启用 K1 的纯 Python `_ac.py` fallback（K1-R1）。
- 词表初版真实条目需业务方提供并加密入库（K1）。
- `trawler login` 子命令存在性未验证，不存在则走 `live_browser.py` MCP 工具链（K4-1）。
- 本地 Dify 实例未部署，PoC 可降级为"本地 LLM 直接消费素材 JSON"（K4-2）。
- DDG 搜索后端全超时需单独排查（代理 7897 可达性 / 换 Tavily/Serper）（K4-5）。
- 【安全】`run_pipeline.py:225` 硬编码 SenseNova key 仍需轮换 + 移环境变量（独立事项，第三次提醒）。

## 五、Phase B 准入

四份设计文档质量达标（引用真实、决策有理由、信任边界在各自范围内正确）。P0 裁决补设 + P1 对齐后，可按车道拆 Phase B 实施提示词。建议实施顺序：

1. **B1** = K1 引擎包 + Armor Proxy（P0 裁决的新组件，与引擎同车道）
2. **B2** = K2 egress 挂接 + Gathering 工作流引擎（依赖 B1 的引擎）
3. **B3** = K3 WebUI（按裁决瘦身后的版本，依赖 B1 的 API）
4. **B4** = K4 Trawler 登录态配置 + 生图端点（相对独立，可与 B1 并行）
