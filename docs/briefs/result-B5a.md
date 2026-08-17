# result-B5a — Armor Proxy 卸甲盲区修复（tool_calls / 流式）实施总结

> 车道 B5a ｜ 依据：`docs/subclaw-briefs/brief-B5a-proxy-toolcalls-fix.md`
> 本次为 bug 修复任务，禁止 git 操作。

## 缺陷与根本原因

- **缺陷表现**：上游模型按 token 契约段保留 `[PERS_K1]` 等 token 写进搜索等工具参数（`tool_calls[*].function.arguments`），下游工具（如 nanobot / MCP 搜索工具）携带 token 直接去明文区搜索导致召回为零（敏感人物 X/Twitter 搜索全 0），破坏"搜索永远在明文区"的信任边界设计。
- **根因分析**：
  1. 非流式响应处理原先仅对 `choices[0].message.content` 执行 `armor.off()`，忽略了 `message.tool_calls`；
  2. 流式响应处理原先仅对 `delta.content` 经 `StreamingRestorer` 卸甲，`delta.tool_calls` 分片原样透传且未处理跨 chunk 切断的 token。

## 修复内容

### 1. 代码修改

| 文件 | 位置 | 修法说明 |
|---|---|---|
| `src/dragnet/armor/proxy.py` | `chat_completions:187-193`, `_dearmor_tool_call_args:196-214` | **非流式**：遍历 `choices[*].message.tool_calls`，对 `function.arguments`（JSON 字符串）做 `armor.off()` 还原明文（结构字符不受影响，仍为合法 JSON）。 |
| `src/dragnet/armor/proxy.py` | `_stream_upstream:216-274`, `_feed_tool_call_args:275-295`, `_flush_tool_restorers:297-313` | **流式**：维护 `tool_restorers: dict[int, StreamingRestorer]`（按 `tool_call.index` 分桶），增量 feed arguments 分片；在 `finish_reason` 与 `[DONE]` 时 flush 残留缓冲，确保跨 chunk 被切断的 token（如 `[PER` + `S_K1]`）无缝还原且拼成合法 JSON。 |
| `src/dragnet/armor/proxy.py` | `:315-379` | 清理浏览器测试页 `_TEST_HTML` 换行超长行，删除重复 import，补齐 `HTMLResponse` 返回值类型注解。 |
| `src/dragnet/armor/wordlist.py` | `build_from_env:120-126` | 恢复 `DRAGNET_ARMOR_WORDLIST_KEY` 缺失时的 fail-closed 抛错机制（修复此前残留的 `DEFAULT_KEY` 未定义及 fail-closed 破坏）。 |
| `tests/security/test_ssrf_guard.py` | `test_nonexistent_host_fails:236-242` | mock `socket.getaddrinfo` 抛 `socket.gaierror`，规避本地代理/DNS 劫持环境下 fake-IP 导致的单测环境污染。 |

### 2. 测试覆盖（`tests/unit/test_armor_proxy.py`）

| 测试类 | 用例名 | 覆盖场景 |
|---|---|---|
| `TestNonStreamToolCalls` | `test_tool_calls_dearmored` | 非流式：上游 arguments 含 `[PERS_K1]` / `[EVENT_E1]` → 卸甲为明文"朱镕基 逝世"，解析为合法 JSON |
| `TestNonStreamToolCalls` | `test_unknown_token_preserved` | 非流式：未知 token（`[ORG_X99]`）原样保留，已知 token 正常还原 |
| `TestNonStreamToolCalls` | `test_multiple_tool_calls_each_dearmored` | 非流式：多个 tool_calls 均被正确卸甲 |
| `TestNonStreamToolCalls` | `test_no_tool_calls_content_behavior_unchanged` | 回归：普通 content 响应行为不变，不产生多余字段 |
| `TestStreamToolCalls` | `test_token_split_across_chunks` | 流式：token 被 chunk 人为切片（`{"query":"[PER` + `S_K1]"}`）→ 跨片缓冲还原为合法明文 JSON |
| `TestStreamToolCalls` | `test_complete_token_in_single_chunk` | 流式：单 chunk 完整 token 正确卸甲 |
| `TestStreamToolCalls` | `test_two_tool_calls_split_independently` | 流式：多个 tool_calls（index 0 / 1）独立分桶缓冲与还原 |
| `TestStreamToolCalls` | `test_content_dearmored_no_tool_calls` | 回归：普通流式 content（跨片 token）还原行为保持正确 |
| `TestRequestPassthrough` | `test_tools_tool_choice_response_format_pass_through` | 回归防护：请求侧 `tools` / `tool_choice` / `response_format` / `temperature` 原样透传，`messages` 穿甲 |

## 门禁结果（全绿）

```powershell
.venv\Scripts\python.exe -m ruff format src tests
# 130 files left unchanged

.venv\Scripts\python.exe -m ruff check src tests
# All checks passed!

.venv\Scripts\python.exe -m mypy
# Success: no issues found in 87 source files

.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract or property or security" --timeout 120
# 450 passed, 73 deselected in 9.11s
```

## 遗留问题与说明

1. **Token 结构安全**：Token 命名均使用半角/全角括号加字母数字下划线（如 `[PERS_K1]`），不包含 JSON 结构字符（如 `"`, `:`, `{`, `}`, `,`），因此在 arguments 流中直接按括号边界卸甲是安全的，所有测试用例已验证拼接后 JSON 结构合法。
2. **多 tool_call 并发分片**：目前基于 `tool_call.index` 分桶累积 StreamingRestorer，符合 OpenAI 标准流式 tool_calls 协议。

[WORKER_DONE] status: OK
