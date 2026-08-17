# Brief B5a：Armor Proxy 卸甲盲区修复（tool_calls / 流式）

你是 GLM worker，在 Dragnet 仓库根目录一次性执行。本次是 bug 修复任务。禁止 git 任何操作。

## 背景（已确诊的 bug）

`src/dragnet/armor/proxy.py`（290 行）是穿甲代理：请求侧对全 messages ArmorOn（`_build_armored_messages` :140），响应侧卸甲。**缺陷：响应里的 `tool_calls` 从不卸甲**——

- 非流式路径（`:181-186`）只处理 `message.content`，`message.tool_calls[*].function.arguments` 原样透传；
- 流式路径（`:190-224`）只处理 `delta.content`，`delta.tool_calls` 的参数分片原样透传。

后果：模型按契约段保留 token，把 `[PERS_K1]` 写进搜索工具查询参数 → nanobot 拿 token 去搜互联网 → 召回为零（用户实测：敏感人物 X/Twitter 搜索全 0）。这破坏了"搜索永远在明文区"的信任边界设计（见 `docs/subclaw-briefs/review-R15-integration.md` §二）。

## 先读

- `src/dragnet/armor/proxy.py` 全文、`src/dragnet/armor/engine.py`（`Armor.off` / `StreamingRestorer` 的签名与行为）
- `tests/unit/` 现有 armor 测试的写法约定

## 修复内容

1. **非流式**：`chat_completions` 响应处理中，对 `choices[*].message.tool_calls[*].function.arguments`（JSON 字符串）整体做 `armor.off()` 后再放行；`content` 现有逻辑不变。
2. **流式**：`_stream_upstream` 中 `delta.tool_calls` 的参数分片不能逐片直接 ArmorOff（token 可能被 chunk 切断）——为每个 tool_call 各维护一个 `StreamingRestorer`（按 index 分桶累积 arguments 字符串），`finish_reason`/`[DONE]` 时 flush。**注意**：arguments 分片是增量 JSON，卸甲后的增量必须仍能拼成合法 JSON——由于 token 不含 JSON 结构字符，直接对流卸甲是安全的，但要用测试证明。
3. **回归防护**：确认请求侧 `tools`/`tool_choice`/`response_format` 等字段继续原样透传（`{**req}` 已保证，加测试锁定）。
4. **测试**（`tests/unit/test_armor_proxy.py` 或并入既有文件）：
   - 非流式：上游返回 `tool_calls`（arguments 含 `[PERS_K1]`）→ 客户端收到明文"朱镕基"
   - 流式：arguments 分片（token 被人为切成两片）→ 拼接后为明文合法 JSON
   - 无 tool_calls 的普通响应行为不变；未知 token 原样保留+告警
   - mock 上游用 respx（`pyproject.toml` dev 依赖已有）

## 门禁

```
.venv\Scripts\python.exe -m ruff format src tests
.venv\Scripts\python.exe -m ruff check src tests
.venv\Scripts\python.exe -m mypy
.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract or property or security" --timeout 120
```

## 收尾

写 `docs/subclaw-briefs/result-B5a.md`：修法、测试证据、遗留问题。最后输出 `[WORKER_DONE] status: OK|PARTIAL|FAIL`。
