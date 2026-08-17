# Brief A 结果 — 研究运行时 MCP 接线（WP-A）

> 日期：2026-08-09
> 对应任务：`docs/subclaw-briefs/brief-A-research-mcp-wiring.md`
> 结论：**验收门禁全部通过**；WP-A 内核已在工作区就绪（说明：其中大部分接线逻辑在本次接管前的 R13 工作区变更中已在 `mcp/server.py` 落地，本次补齐 mypy 修复并新增 `test_research_mcp_tools.py` 切片测试，随后全量跑通门禁）。

---

## 1. 改动文件清单

| 文件 | 改动 | 状态 |
|------|------|------|
| `src/dragnet/mcp/server.py` | 新增 4 个研究工具注册（`start_research` / `get_research_status` / `build_research_package` / `stage_research_package`）+ `_call_tool` 分发 + 工具实现方法；ActorContext 从 `DRAGNET_RESEARCH_ACTOR` 注入；`GPTR_COMMAND` 缺省不启用；`asyncio.run` 驱动 async gptr 适配器；discover→fetch 最小闭环；移除被 `trawler.py` 取代的 `research_person` | 工作区（未提交） |
| `src/dragnet/mcp/trawler.py` | 删除（被 `mcp_gptr_*` 与研究工具取代） | 已删除 |
| `src/dragnet/research/adapters/gptr.py` | gptr 上游适配器（Transport 抽象 + stdio 子进程；URL 归一化/去重/分层） | 未跟踪（R13） |
| `src/dragnet/research/store.py` | ResearchStore（幂等 + CAS + 租约） | 未跟踪（R13） |
| `src/dragnet/research/workflow.py` | ResearchWorkflow 有界状态推进（状态推进唯一入口） | 未跟踪（R13） |
| `src/dragnet/research/package.py` | ResearchPackageBuilder（清单 + 落盘 + 路径穿越防护） | 未跟踪（R13） |
| `tests/unit/test_mcp_server.py` | FakeMcpServer 补 4 个研究工具分支；tools/list 断言补 4 个工具名；移除 `research_person` | 工作区（未提交） |
| `tests/integration/test_mcp_stdio.py` | 4 处 `len(tools)` 断言 `10 → 13` | 工作区（未提交） |
| `tests/unit/test_research_mcp_tools.py` | **新增** FakeResearchStore / FakeResearchMcpServer，覆盖 start→status→package 往返与非法状态拒绝 | 新增 |

> 注：`research/` 域与契约 `contracts/research.py` 属于 R13 未跟踪工作，非本次 WP-A 新增；本次 WP-A 的独立增量是 MCP 接线（server.py）、测试切片（test_research_mcp_tools.py）与一处 mypy 收窄。

---

## 2. 门禁输出尾部摘要

```
$ .venv/Scripts/python.exe -m ruff format src tests
106 files left unchanged

$ .venv/Scripts/python.exe -m ruff check src tests
All checks passed!

$ .venv/Scripts/python.exe -m mypy
Success: no issues found in 73 source files

$ .venv/Scripts/python.exe -m pytest tests -q -m "unit or contract" --timeout 120
105 passed, 257 deselected in 2.12s
```

**WP-A 相关单测**（`test_mcp_server.py` + `test_research_mcp_tools.py`）单独跑：`17 passed`。

---

## 3. 接线要点（对照 Brief A 任务清单）

1. **4 工具注册**：见 `server.py` `tools/list` 与 `_call_tool()`，保持既有硬编码注册风格。
2. **ActorContext 注入**：`McpServer.__init__` 读 `DRAGNET_RESEARCH_ACTOR`（缺省 `research-workflow`），构造 `ActorContext(actor_type=ActorType.SYSTEM, roles={"OPERATOR"}, auth_method="internal")`；工具不接受参数里的用户身份。
3. **同步桥接**：工具实现内用 `asyncio.run(self._gptr_adapter.discover(...))` 驱动 async 适配器；`GPTR_COMMAND` 缺省不启用，未配置时 `start_research` 仍成功（推进到 `EVIDENCE_BUILDING`，来源空）。
4. **discover→fetch 最小闭环**：gptr 可用时执行 discover，来源写入 checkpoint（`sources`：source_id/canonical_url/source_tier/fetch_status）；前 3 个来源用 `web_intelligence.provider.safe_fetch` 抓正文，更新 `content_hash` 与 `fetch_status="ok"`（失败记 `"failed"`，不中断）。
5. **状态推进**：全部经 `research/workflow.py` 的 `ResearchWorkflow` 方法 + `assert_research_transition`，未直接改 state 字段。

---

## 4. 遗留问题 / 注意点

- **`start_research` 的 fetch 是同步阻塞**：`safe_fetch` 是同步 HTTP，前 3 个来源在 `asyncio.run` 之外逐条抓取；来源多或网络慢时 MCP 调用耗时会加长。P1 可改异步轮询（`get_research_status`）。
- **`test_manifest_cannot_be_embedded`（contract 未打标记）**：`tests/contract/test_research_contracts.py` 中该用例未加 `contract` 标记，且当前失败（期望 `ValidationError` 未抛出）。不在 `-m "unit or contract"` 门禁内，属 R13 遗留，未纳入本次 WP-A 修复范围。
- **`test_glued_frames`（integration）**：`tests/integration/test_mcp_stdio.py` 全量跑时存在已知超时（`_read_frame` 阻塞，非 WP-A 引入），门禁按 `-m "unit or contract"` 规避。
- **gptr 进程内状态**：stdio 子进程重启即丢上游 `research_id`，P0 竖切可接受（Dragnet 侧 `research_run` 已持久化）；`deep_research` 实测 2-5 分钟，MCP `toolTimeout` 需按档位放宽或改轮询。
- **未提交**：按 Brief A 范围不加 git commit；research 域整体仍为未跟踪工作区文件，建议按 P0 基线 §9 顺序分批提交。
- **包内正文**：`build_research_package` 目前以 checkpoint 来源元数据指纹重建 `SourceRecord`（`_sources_from_checkpoint`），不含抓取正文；正文固化（sources/*/content.md）留待 WP-C。