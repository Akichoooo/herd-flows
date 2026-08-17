# result-B4 — 生图端点 + Trawler 登录态 + Dify PoC — 实施

> 车道 B4 ｜ 依据：`docs/rounds/R15d-armor-ops-design.md` + `brief-B4-ops-impl.md`
> 文件所有权遵守：仅动 enroll/api.py、enroll/service.py、dragnet-settings.js、新测试/脚本、.env.example。未碰 mcp/server.py、egress/**、research/**、armor/**、run_pipeline.py。

## 交付清单

| # | 交付物 | 文件:行 | 说明 |
|---|---|---|---|
| 1 | ImageGenService（配置/生成/价格测试） | `src/dragnet/enroll/service.py:494` `ImageGenService`；`:511` `load_config`；`:527` `save_config`；`:545` `masked_config`；`:577` `test_price` | env(`DRAGNET_IMAGE_GEN_*`)+workspace yaml 覆盖；key 永不回显明文 |
| 2 | 真实 httpx 传输 + Protocol | `service.py:432` `ImageGenTransport`；`:452` `HttpxImageGenTransport` | OpenAI 兼容 /images/generations；transport 可注入（单测 mock） |
| 3 | 4 个生图端点（挂进 enroll FastAPI app） | `src/dragnet/enroll/api.py:306` GET /api/face/config；`:311` POST /api/face/config；`:328` POST /api/face/gen-augment；`:368` POST /api/face/gen-test | 扩展现有 app，不改既有路由语义；`image_gen` 注入点 `:84,102` |
| 4 | 前端 mock 替换为真实 API | `scripts/nanobot-ext/dragnet-settings.js:379` `__dragnetGenAugmentations`（原 `:350-367` setTimeout 复制原图 stub 已删） | 改为 `api("POST","/api/face/gen-augment")` 真实调用 |
| 5 | 前端生图配置面板（修"配置不生效"） | `dragnet-settings.js:344` 生图引擎配置卡；`:349` provider/model/endpoint/key 输入；`:358` 保存按钮；`:359` 价格测试按钮 | 接 `/api/face/config`，修复端点缺失导致的静默 fallback 硬编码默认值 |
| 6 | 前端配置加载修复 | `dragnet-settings.js:initFacePanel` | 读 `provider/model/endpoint/api_key_set`（原读 `cloud_api_key/cloud_endpoint` 端点不存在→`{_error:true}`→静默 fallback） |
| 7 | 前端价格测试 + 保存函数 | `dragnet-settings.js:410` `__dragnetSaveGenConfig`；`:430` `__dragnetTestImageGen` | 调 POST /api/face/gen-test 回显 `{success,latency_ms,cost_estimate,error}` |
| 8 | 单元测试（mock provider） | `tests/unit/test_enroll_gen.py`（15 用例） | 覆盖配置掩码/env 回退/yaml 覆盖/生成/价格测试/4 端点 |
| 9 | .env.example 配置项 | `.env.example` 追加 `DRAGNET_IMAGE_GEN_*` + `TRAWLER_VAULT_KEY` | env→配置模式，禁止硬编码 |
| 10 | Trawler vault 脚本 | `scripts/setup_trawler_vault.ps1` | Fernet key 生成 + 设置 + 透传确认 + 登录流程文档 |
| 11 | Dify PoC 脚本 | `scripts/dify_handoff_poc.py` | 读 raw_search_*.json → 调本地 LLM(Ollama) 合成；降级处理 |

## 根因修复确认

`[CLAIM]` "4 角度生图不可用"根因 = 前端 `__dragnetGenAugmentations` 是 mock stub（setTimeout 后把原图 URL 复制到 4 个 candidate，零 API 调用），后端 `/api/face/config` 端点从未实现。已修复：后端补齐 4 端点 + 前端改为真实 `api("POST","/api/face/gen-augment")` 调用。 | evidence: `dragnet-settings.js:379`（替换后）、R15d §4.1.2 原 `:350-367` mock | confidence: high

`[CLAIM]` "配置不生效"根因 = 前端经 `GET /api/face/config` 读 `cloud_api_key/cloud_endpoint`，但该后端端点不存在 → `api()` helper 返回 `{_error:true}` → 前端静默忽略后用硬编码默认值（`FSTATE.model="dall-e-3"`）。已修复：实现 GET/POST /api/face/config，前端读 `provider/model/endpoint/api_key_set`。 | evidence: `dragnet-settings.js:initFacePanel`、`api.py:306-326` | confidence: high

`[CLAIM]` Trawler vault key 透传链路 = `run_pipeline.py:114` `env = os.environ.copy()` 已自动透传全部环境变量（含 `TRAWLER_VAULT_KEY`），无需改 run_pipeline.py。设置 vault key 后 Trawler `account_vault.is_vault_enabled()`（`trawler/account_vault.py:91`）返回 True，走账号态爬取。 | evidence: `run_pipeline.py:114`、`trawler/account_vault.py:91` | confidence: high

`[CLAIM]` `trawler login` CLI 子命令【不存在】——`uv run trawler --help` 仅暴露 `search`。按 R15d §2.5.2 [RISK] 处置：预登录走 `trawler/live_browser.py` 工具链（`open_browser_session`→人工登录→`extract_browser_session`→`save_storage_state`），已写入 `setup_trawler_vault.ps1`。 | evidence: `uv run trawler --help` 输出、`scripts/setup_trawler_vault.ps1` | confidence: high

## 门禁结果（全绿）

```
ruff format src tests   → 125 files left unchanged
ruff check src tests    → All checks passed!
mypy                    → Success: no issues found in 84 source files
pytest -m "unit or contract or property or security" → 424 passed, 73 deselected
```
本车道新增 15 个单测全部通过（`tests/unit/test_enroll_gen.py`，自动 `unit` 标记）。

## 冒烟结果

- **生图端点**：无真实 provider key，按 brief 用 mock 验证。`ImageGenTransport` Protocol 注入 fake，15 用例覆盖：配置掩码（key 永不回显明文）、env 回退、yaml 覆盖、生成返回 PNG（魔数校验）、无 key 报错、价格测试成功/失败、4 端点 TestClient 联调。真实生图未冒烟（环境无 key，brief 允许 mock）。
- **Dify PoC**：`python scripts/dify_handoff_poc.py` 实测——成功定位 `reports/raw_search_20260813_163406.json` 并解析素材（4 查询），调本地 Ollama 返回 HTTP 404（本地未运行 Ollama）→ 按设计降级，打印明确降级信息。素材解析与 LLM 调用路径已验证，仅 LLM 端点不可用（环境限制）。

## 遗留问题

1. **无真实生图 provider key**：端到端真实图像生成未冒烟（mock 验证通过）。配置 key 后可直接走真实 `/images/generations`。
2. **本地 Ollama 未运行**：Dify PoC 端到端合成未完成（素材解析+调用路径已验证，LLM 端点 404）。`ollama serve` + `ollama pull qwen2.5:7b` 后即可完成。
3. **gen-augment 用 text-to-image + 角度 prompt**：非真实 img2img variations（DALL·E 3 无标准 `/images/variations`）。provider 无关的务实选择；真 img2img 需 provider 专属 variations 端点（二期）。
4. **`trawler login` CLI 缺失**：live_browser.py 工具链路径已文档化但未端到端执行（需 GUI + 目标站点）。
5. **R15d 纠错已落实**：R15d 称 `enroll/api.py`"尚未创建"——错误，已按 brief 先通读既有 app 后扩展（非新建）。

[WORKER_DONE] status: OK
