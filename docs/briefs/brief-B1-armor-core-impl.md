# Brief B1：Armor 引擎包 + Armor Proxy 服务 — 实施

你是 GLM worker，在 Dragnet 仓库根目录一次性执行。本次是**实施**任务，可以写代码。禁止 git 任何操作。

## 先读

1. `docs/rounds/R15a-armor-core-design.md` — 你的设计文档，按它实施
2. `docs/subclaw-briefs/review-R15-integration.md` — 集成评审，§二（Armor Proxy 裁决）和§三（API 字段裁决）是本任务的强制需求
3. `run_pipeline.py`（词表 seed 来源 `_CIPHER_PAIRS`）、`src/dragnet/util/prompt_sanitizer.py`（`SENSITIVE_PAIRS` seed 来源）
4. `src/dragnet/mcp/server.py`、`src/dragnet/config.py`

## 文件所有权（只许动这些，越界即失败）

- 新建 `src/dragnet/armor/**`（全部）
- `src/dragnet/mcp/server.py` —— 只加 armor 工具注册块，不动既有工具
- 新建 `tests/unit/test_armor_*.py`、`tests/property/test_armor_property.py`
- `.env.example`、`.gitignore`（各追加若干行）
- `.nanobot/config.json` —— 改前先复制备份为 `config.json.pre-armor.bak`
- 新建 `scripts/` 下的 proxy 启动脚本（如需要）

**禁止碰**：`egress/gateway.py`、`research/**`、`dragnet-settings.js`、`enroll/**`、`run_pipeline.py`（B2/B3/B4 的地盘）。

## 交付内容

1. **`src/dragnet/armor/` 包**，按 R15a：engine（`Armor.on()->ArmorResult` / `Armor.off()->ArmorOffResult`）、wordlist（YAML 明文源 + Fernet 加密落盘、版本化、copy-on-write 热更新、回滚）、normalize、contract（token 契约段渲染器——**全系统唯一实现**，B2 的 `research/prompt_contract.py` 只 import 包装它）、audit（复用 `contracts.audit.AuditEvent`，日志不记明文主词条）、`StreamingRestorer.feed()/flush()`（`[`/`]` 边界缓冲 + 容错归一化）。AC 匹配：`pyahocorasick` 优先，Windows wheel 不可用则落纯 Python `_ac.py` fallback（R15a R1）。
2. **Armor Proxy 服务**（评审 §二裁决）：OpenAI 兼容端点 `POST /v1/chat/completions`（支持流式 SSE），监听 `:18791`。流程：收请求 → 全 messages（含历史与工具结果）ArmorOn + system 注入契约段 → 转发上游 → 流式 ArmorOff（StreamingRestorer）→ 返回。上游 base_url/key 走环境变量（`DRAGNET_ARMOR_PROXY_UPSTREAM_BASE` / `DRAGNET_ARMOR_PROXY_UPSTREAM_KEY`），禁止硬编码。
3. **HTTP API**（与 proxy 同进程托管，评审 §三裁决的**最终字段名**，B2/B3 按此对齐）：
   - `POST /api/armor/on` body `{text}` → `{armored, count, hits, version}`
   - `POST /api/armor/off` body `{text}` → `{text, restored, unknown, version}`
   - `GET /api/armor/status` → `{ok, version, digest, loaded_count}`
4. **MCP 工具** `armor_on(text)` / `armor_off(text)` 注册进 `mcp/server.py`。
5. **词表 seed 迁移工具**：把 `run_pipeline.py:_CIPHER_PAIRS` + `prompt_sanitizer.SENSITIVE_PAIRS` 迁为词表初版条目（含变体分组），CLI 支持 add/list/encrypt/leak-check。
6. **配置**：`.env.example` 追加 `DRAGNET_ARMOR_WORDLIST_KEY`、proxy 上游两项；`.gitignore` 追加词表密文/密钥文件；`.nanobot/config.json` 的 `providers.custom.apiBase` 改指 `http://127.0.0.1:18791/v1`（先备份；`fallbackModels` 若指向直连上游则一并改指代理或禁用，评审 §二.5）。
7. **测试**：单元（引擎/词表/容错修复/流式缓冲）+ property（`ArmorOff∘ArmorOn` 语义级可逆，hypothesis）。

## 门禁（全绿才算完成）

```
.venv\Scripts\python.exe -m ruff format src tests
.venv\Scripts\python.exe -m ruff check src tests
.venv\Scripts\python.exe -m mypy
.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract or property or security" --timeout 120
```

proxy 与 /api/armor/* 做一次手动冒烟（curl 三个端点 + 一次 /v1/chat/completions 转发），结果记入 result。

## 收尾

写 `docs/subclaw-briefs/result-B1.md`：交付清单、冒烟结果、遗留问题。
最后输出 `[WORKER_DONE] status: OK|PARTIAL|FAIL`，关键结论带 `[CLAIM] ... | evidence: 文件:行 | confidence: ...`。
