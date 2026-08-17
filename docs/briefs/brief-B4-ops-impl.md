# Brief B4：生图端点 + Trawler 登录态 + Dify PoC — 实施

你是 GLM worker，在 Dragnet 仓库根目录一次性执行。本次是**实施**任务，可以写代码。禁止 git 任何操作。

## 先读

1. `docs/rounds/R15d-armor-ops-design.md` — 你的设计文档，按它实施
2. `docs/subclaw-briefs/review-R15-integration.md` §四（遗留项处置）
3. **纠错**：R15d 称 `src/dragnet/enroll/api.py`"尚未创建"——**错误**，该文件存在（FastAPI 应用，R14 WP3 路由已有一批）。你的任务是**扩展现有 app**，先通读 `src/dragnet/enroll/api.py` 与 `src/dragnet/enroll/service.py` 再动手。
4. `scripts/nanobot-ext/dragnet-settings.js` 的生图相关段（`:271,284-291,350-367`）
5. `src/dragnet/config.py`

## 文件所有权（只许动这些，越界即失败）

- `src/dragnet/enroll/api.py`、`src/dragnet/enroll/service.py`（扩展，不改既有路由语义）
- `scripts/nanobot-ext/dragnet-settings.js` —— **Wave 1 期间你独占此文件**（B3 在 Wave 2 才碰它），只动 settings 页生图区，别碰其他模块代码
- 新建 `tests/unit/test_enroll_gen*.py`、`scripts/` 下新脚本
- `.env.example`（追加生图配置项）

**禁止碰**：`mcp/server.py`、`egress/**`、`research/**`、`src/dragnet/armor/**`、`run_pipeline.py`。

## 交付内容

1. **生图后端三端点**（挂进 enroll/api.py 现有 FastAPI app）：
   - `GET/POST /api/face/config` — 读/写生图配置（provider/model/endpoint；key 只写不回显明文）
   - `POST /api/face/gen-augment` — 输入基准图，生成 4 角度候选图，返回真实生成结果
   - `POST /api/face/gen-test` — 最小请求（256×256）价格测试，回显 `{success, latency_ms, cost_estimate, error}`
   - 配置走 `config.py` env→RuntimeConfig 模式：`DRAGNET_IMAGE_GEN_PROVIDER` / `_MODEL` / `_API_KEY` / `_ENDPOINT`；生图样本入库打标 `preprocess_version='synth-1'`（R14 §3.2 约定）
2. **前端生图区修复**（dragnet-settings.js）：删除 mock `__dragnetGenAugmentations`（`:350-367` 的 setTimeout 复制原图实现），改为真实 `api("POST","/api/face/gen-augment")` 调用；配置面板接 `/api/face/config`（修掉"配置不生效"：目前端点缺失导致静默 fallback 硬编码默认值）；加**价格测试按钮**调 `/api/face/gen-test` 并回显结果。
3. **Trawler 登录态**：验证 `trawler login` 子命令是否存在（在 `D:\devloop\workSpace\app_ZCode\Trawler-mcp` 下 `uv run trawler --help`，不存在则按 R15d 走 `live_browser.py` 工具链）；落一份 `scripts/setup_trawler_vault.ps1` 或等效文档：`TRAWLER_VAULT_KEY` 配置 + 预登录操作流程；确认调用链透传该环境变量。
4. **Dify PoC（最小验证）**：脚本或文档步骤证明"本地 LLM 消费 `reports/raw_search_*.json` 素材合成报告"可行；本地 Dify 实例不可用则降级为直接调本地 LLM（Ollama），如实记录。
5. **测试**：新端点的单元测试（mock provider）。

## 门禁（全绿才算完成）

```
.venv\Scripts\python.exe -m ruff format src tests
.venv\Scripts\python.exe -m ruff check src tests
.venv\Scripts\python.exe -m mypy
.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract or property or security" --timeout 120
```

生图端点若无真实 provider key 可冒烟，用 mock 验证并在 result 里说明。

## 收尾

写 `docs/subclaw-briefs/result-B4.md`：交付清单、根因修复确认、冒烟结果、遗留问题。
最后输出 `[WORKER_DONE] status: OK|PARTIAL|FAIL`，关键结论带 `[CLAIM] ... | evidence: 文件:行 | confidence: ...`。
