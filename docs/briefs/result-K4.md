# Result K4 — Trawler 登录弹窗 + Dify 回退链路 + 生图配置

> 车道：K4 ｜ 交付物：`docs/rounds/R15d-armor-ops-design.md` + 本文件
> 状态：OK（全部范围已覆盖，根因已定位，遗留问题已标注）

---

## 设计要点

1. **Trawler-mcp 已有完整登录态基础设施，无需在 Dragnet 侧重复实现。** Trawler-mcp 的 `trawler/account_vault.py` 已实现加密 storage_state 读写（Fernet + `TRAWLER_VAULT_KEY`）、cookie 保险库（`_is_cookie_fresh()` 过期检测）、`save_auto_cookies()`/`get_auto_cookies()` 回流；`trawler/fetcher/hitl_rung.py` 已实现 HITL 人工过码（`has_display()` 检测 GUI → `launch_persistent_context(headless=False)` → 轮询 `is_challenge_page()`）；`trawler/live_browser.py` 已实现可见浏览器会话（`open_browser_session` / `connect_browser_session` / `perform_browser_actions`）。Dragnet 侧只需配置 `TRAWLER_VAULT_KEY` 环境变量并在 `call_trawler_search()` 中透传。

2. **推荐 A+B 组合、C 兜底的登录方案。** 方案 A（storage_state 预登录注入）为主、方案 B（cookie 保险库过期检测+刷新）为辅、方案 C（HITL 手动接管）为兜底。无 GUI 的 headless server 上 C 不可用（`hitl_rung.has_display()` 返回 False），但开发机/运维终端上 C 是最后手段。代理/UA 策略（方案 D）是正交维度，应叠加使用。详细对比表见 R15d §2.3。

3. **WebUI 不可用的根因已定位为搜索后端超时，非端口冲突。** `fix_webui_access.ps1` 已修复 websocket host（→0.0.0.0:5173）和 gateway 端口冲突（→0.0.0.0:18790）。当前"不可用"更可能是 DDG 搜索后端全部 timeout（`reports/raw_search_20260813_163406.json` 四组查询全部 `"Connection timed out after 15008ms"`）或 Trawler 无账号态被反爬拦截（当前 `call_trawler_search` 不传 `TRAWLER_VAULT_KEY`）。

4. **Dify 回退链路设计为 MCP 工具 `gather_handoff(topic) → artifact_path`。** 触发条件：ArmorOn 穿甲后云端 LLM 仍返回拦截/空响应/安全拒绝。素材 JSON 沿用 `reports/raw_search_*.json` 现有格式（明文），在 `server.py` 的 `_call_tool()` 分发中新增。Dify 侧消费方式：MCP 工具挂载（动态按主题获取）或知识库导入（批量预导入），由本地 LLM（Ollama Qwen/GLM）合成，绕过云端内容安全策略。

5. **Dify 回退的核心价值是素材已在本地明文落盘。** 诊断报告（`diagnostic_final_20260813_1510.md`）证实 deepseek-v4-flash 对"朱镕基总理"+"逝世"+"风险研判"组合触发安全策略，但搜索阶段素材已获取。回退链路复用这些素材，由本地 LLM 在无云端审查环境下完成合成。

6. **生图"4 角度不可用"的根因是前端 mock stub + 后端端点缺失。** `dragnet-settings.js:350-367` 的 `__dragnetGenAugmentations` 函数仅用 `setTimeout(1200ms)` 延时后复制原图 URL 到 4 个 candidate，无任何 API 调用。`FSTATE.model = "dall-e-3"`（line 271）被设置但从未使用。后端 `/api/face/config` 端点在 `src/dragnet/` 中不存在（Grep 确认无此路由），前端 `api()` fetch 静默失败后用硬编码默认值。

7. **R14 设计文档明确"一期不做生成图"是 mock 存在的原因。** `docs/R14-人脸录入模块实施方案.md:19` 记载"一期不做生成图，首选补真实照片，生成图作为二期可选增强"。当前 mock 为占位实现，本设计为二期实施提供方案。

8. **生图修复需同步实施前端+后端+配置三层。** 前端替换 `__dragnetGenAugmentations` 为真实 `api("POST", "/api/face/gen-augment")` 调用；后端在 `src/dragnet/enroll/api.py`（R14 WP3 已规划但未创建）新增 `/api/face/config`、`/api/face/gen-augment`、`/api/face/gen-test` 端点；配置走 `src/dragnet/config.py` 的 env→RuntimeConfig 模式（`DRAGNET_IMAGE_GEN_PROVIDER`/`_MODEL`/`_API_KEY`/`_ENDPOINT`），禁止硬编码 key。

9. **价格测试按钮复用 `api()` helper fetch 模式。** 设计为：前端调用 `api("POST", "/api/face/gen-test", {provider, model})`，后端发最小生图请求（256×256），回显 `{success, latency_ms, cost_estimate, error}`。与现有 `api("GET", "/api/face/config")` 调用方式一致，无需引入新通信机制。

10. **生图样本须与真实样本隔离。** 沿用 R14 §3.2 约定：生图入库时 `preprocess_version='synth-1'`，与真实照片 `pp-2` 区分；独立 threshold_set 标定，不混入真实样本阈值集，防生成伪影推高误识。

---

## 根因诊断结论

### 生图模块根因

`[CLAIM]` "4 角度生图不可用"的根因是前端 `__dragnetGenAugmentations`（`scripts/nanobot-ext/dragnet-settings.js:350-367`）是 mock stub，仅用 `setTimeout` 延时后复制原图 URL 到 4 个 candidate，未调用任何生图 API；后端 `/api/face/config` 端点亦不存在（Grep `src/dragnet/` 无此路由）。R14 设计文档（`docs/R14-人脸录入模块实施方案.md:19`）明确"一期不做生成图"，此 mock 为占位实现。 | evidence: `scripts/nanobot-ext/dragnet-settings.js:350-367,271,284`, Grep `src/dragnet/` 无 `face/config` 路由, `docs/R14-人脸录入模块实施方案.md:19` | confidence: high

`[CLAIM]` 配置不生效的根因是：前端通过 `GET /api/face/config` 期望获取云端识图/生图配置，但该后端端点从未实现（Grep `src/dragnet/` 无匹配），`api()` helper（`dragnet-settings.js:38-54`）的 fetch 返回 `{_error: true}`，前端静默忽略错误后使用硬编码默认值。 | evidence: `scripts/nanobot-ext/dragnet-settings.js:284-291,38-54`, Grep `src/dragnet/` 无 `face/config` | confidence: high

### WebUI 不可用根因

`[CLAIM]` WebUI 端口冲突和 host 绑定问题已由 `fix_webui_access.ps1` 修复（websocket→0.0.0.0:5173, gateway→0.0.0.0:18790）；当前"不可用"更可能是搜索后端超时（DDG 代理不通，`raw_search_*.json` 全部 timeout）或 Trawler 无账号态被反爬拦截。 | evidence: `scripts/fix_webui_access.ps1:14,17-19`, `reports/raw_search_20260813_163406.json:11` | confidence: medium

### Dify 回退触发条件

`[CLAIM]` 云端拦截的触发条件 = "真实敏感新闻报道" + "涉政涉稳风险研判"组合（单独一个因素不触发），穿甲后仍可能被云端内容安全策略拦截，需 Dify+本地 LLM 回退。 | evidence: `reports/diagnostic_final_20260813_1510.md:50-56`, `reports/diagnostic_final_20260813_1445.md:44-52` | confidence: high

---

## 遗留问题

1. **Trawler CLI `login` 子命令验证**：Dragnet 侧仅验证 `trawler search`（`run_pipeline.py:124`），`trawler login <url>` 子命令未验证。若不存在，需通过 MCP 工具链 `open_browser_session` → `perform_browser_actions` → `close_browser_session`（`live_browser.py:169-277,1052-1090,1756-1779`）替代。标注为 `[RISK]`。

2. **Dify 部署状态**：PoC 步骤 3 依赖本地 Dify 实例可用性，当前未在仓库中验证。若未部署，PoC 可降级为"本地 LLM 直接消费素材 JSON"最小验证。标注为 `[RISK]`。

3. **`src/dragnet/enroll/api.py` 实施时机**：生图端点依赖 R14 WP3 的 API 层创建（`docs/R14-人脸录入模块实施方案.md:81-99`），Grep 确认 `src/dragnet/enroll/` 下仅有 `service.py`，`api.py` 尚未创建。需协调实施顺序。

4. **生图 provider 选择**：DALL-E 3 vs Flux 1.1 Pro 的面部结构保真度对比未测试，需在价格测试按钮实施后实测。

5. **搜索后端超时**：`raw_search_*.json` 全部 timeout，DDG 代理不通问题需单独排查（代理 `http://127.0.0.1:7897` 可达性、DDG 后端可用性），或配置 Tavily/Serper 等搜索 API key。

---

`[WORKER_DONE] status: OK`
