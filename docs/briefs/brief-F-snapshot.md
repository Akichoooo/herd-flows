# Brief F：原文截图与快照策略（WP-C）

## 背景
研究档位需要原文证据固化：快查不截图、广搜截最终引用、深研截关键论断来源、
强搜全引用留快照。依据：`docs/R16-爬虫编排层与知识闭环整合方案.md` §2.3、
`docs/R15-研究型Agent接管盘点与路线图.md` §4 WP-C。
契约里已有 `SnapshotPolicy`（L0/L1/L2）与 `EvidenceSpan.screenshot_ref`。

## 任务
### 1. `src/dragnet/research/snapshot.py`
- `policy_for_mode(mode) -> SnapshotPolicy`：quick/broad→L0、deep→L1、strong→L2
  （与契约默认一致，集中一处）；
- `class SnapshotCapture`：playwright 为**可选依赖**——模块顶层 try-import，
  未安装时 `available()` 返回 False、capture 抛带中文说明的 RuntimeError（优雅降级）；
- `capture(url, *, full_page=True, selector=None, dest_dir) -> SnapshotResult`：
  全页 webp + 可选元素裁剪；文件名 `snapshot-<sha256(url)[:12]>.webp`；
  返回 SnapshotResult(path, sha256, captured_at, truncated: bool)；
- 硬限制：单页下载 ≤ 20MB、超时 30s、仅 http/https（复用
  web_intelligence 的 SSRF 判断逻辑或重查其白名单函数）。
### 2. pyproject 依赖
playwright 放 **optional**（dependency-groups 新增 `snapshots = ["playwright>=1.40"]`），
不进主依赖；门禁环境不安装浏览器。
### 3. 测试 `tests/unit/test_snapshot.py`
- policy_for_mode 各档位映射；
- playwright 缺失时的降级报错（monkeypatch 模块标志）；
- 非 http(s) URL 拒绝、dest_dir 路径穿越拒绝；
- 用 fake driver 覆盖 capture 的落盘与 hash（不启动真实浏览器）。
### 4. 接线（最小）
`mcp/server.py` 的 start_research checkpoint 里写 `snapshot_policy` 字段（值来自
policy_for_mode）；不加新 MCP 工具（截图执行留给上层研究循环，本 brief 不展开）。

## 范围外
真实浏览器下载、artifact 入库联动、REST。

## 门禁（全过才算完成）
```
.venv\Scripts\python.exe -m ruff format src tests
.venv\Scripts\python.exe -m ruff check src tests
.venv\Scripts\python.exe -m mypy
.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract" --timeout 120
```
完成后写 `docs/subclaw-briefs/result-F.md`。不要 git commit。
**不要碰** `.nanobot/workspace/skills/`、`AGENTS.md`、`docs/Dragnet使用手册.md`
（另一个 worker 在改）。
