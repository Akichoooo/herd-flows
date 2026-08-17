# Brief A：研究运行时 MCP 接线（WP-A）

## 背景
Dragnet 研究型 Agent 的 P0 内核已完成（契约/状态机/Store/审计/制包/gptr 适配器/投递适配器），
但未暴露给 nanobot Agent 使用。你的任务：把研究运行时接进 Dragnet MCP stdio server。
必读文档（按序）：
1. `docs/R15-研究型Agent接管盘点与路线图.md` §2、§4 WP-A
2. `outputs/Dragnet研究型Agent-P0工程实施基线.md` §5、§6（模块接口与 MCP 工具定义）
3. `src/dragnet/mcp/server.py`（现有 9 个工具的注册与分发方式）

## 任务（决策已定，照做即可）
1. 在 `src/dragnet/mcp/server.py` 新增 4 个工具（保持现有硬编码注册风格）：
   - `start_research(query, mode, skill_id?, focus?)` → 创建 ResearchRun（经 ResearchStore.create_run，
     幂等键 = sha256(query|mode|skill_id) 前 24 位），返回 research_id、state、预算摘要；
   - `get_research_status(research_id)` → 返回 state、report_versions、checkpoint 摘要；
   - `build_research_package(research_id, report_version)` → 调 ResearchPackageBuilder，
     包落盘到 `research/{research_id}/package/`（相对工作区），返回 manifest_digest 与路径；
   - `stage_research_package(research_id, report_version, target_workspace, target_category)` →
     P0 只做本地 staging 记录（写 checkpoint + 返回 STAGED），**不调真实 docAnalyze HTTP**。
2. ActorContext 注入：不接受工具参数里的用户身份。McpServer 初始化时从环境变量
   `DRAGNET_RESEARCH_ACTOR` 读 actor_id（缺省 "research-workflow"），构造
   ActorContext(actor_type=ActorType.SYSTEM, roles={"OPERATOR"})，参考
   `scripts/register_faces_subset.py` 的用法。
3. 同步桥接：MCP server 是同步 stdio 循环；gptr 适配器是 async。
   在工具实现里用 `asyncio.run(...)` 驱动即可；gptr 子进程命令从环境变量
   `GPTR_COMMAND`（缺省不启用）读取，未配置时 start_research 仍成功（DISCOVERING 留给上层）。
4. 发现-抓取最小闭环：start_research 后若 gptr 可用，执行 discover → 把来源写入 checkpoint
   （`sources` 列表：source_id/canonical_url/source_tier/fetch_status）；
   对前 3 个来源用 `dragnet.web_intelligence.provider.safe_fetch` 抓正文，
   更新 content_hash 与 fetch_status="ok"（失败记 "failed"，不中断）。
5. 状态推进必须走 `research/workflow.py` 的 ResearchWorkflow 方法与
   `assert_research_transition`；禁止直接改 state 字段。

## 必须同步修改的测试
- `tests/unit/test_mcp_server.py`：FakeMcpServer 补 4 个工具分支；tools/list 断言补 4 个工具名。
- `tests/integration/test_mcp_stdio.py`：三处 `len(tools) == 9` 改为 `== 13`。
- 新增 `tests/unit/test_research_mcp_tools.py`：用 fake store/workflow 覆盖
  start→status→package 的往返与非法状态拒绝（不依赖数据库）。

## 范围外（不要做）
REST API、Playwright 截图、真实 docAnalyze 联调、skill 改写、git commit。

## 验收门禁（全部通过才算完成）
```
.venv\Scripts\python.exe -m ruff format src tests
.venv\Scripts\python.exe -m ruff check src tests
.venv\Scripts\python.exe -m mypy
.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract" --timeout 120
```
环境：Windows PowerShell，项目根 `D:\devloop\workSpace\app_ZCode\Dragnet`，
虚拟环境 `.venv`。完成后在 `docs/subclaw-briefs/result-A.md` 写：改动文件清单、
门禁输出尾部摘要、遗留问题。不要 git commit。
