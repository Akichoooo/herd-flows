# Result-F：原文截图与快照策略（WP-C）

## 完成情况

### 1. `src/dragnet/research/snapshot.py` ✅

- **`policy_for_mode(mode) -> SnapshotPolicy`**：quick/broad→L0、deep→L1、strong→L2，映射集中一处，与 `ResearchRequest._defaults` 一致。
- **`SnapshotResult`**（frozen dataclass）：`path`、`sha256`、`captured_at`（UTC）、`truncated`。
- **`SnapshotCapture`**：
  - playwright 为**可选依赖**：顶层 `importlib.util.find_spec("playwright")` 检测，未安装时 `available()` 返回 False，`capture()` 抛中文 RuntimeError。
  - `capture(url, *, full_page=True, selector=None, dest_dir) -> SnapshotResult`：全页 webp 截图 + 可选元素裁剪（优先于 `selector` 参数）。
  - 文件名 `snapshot-<sha256(url)[:12]>.webp`。
  - 硬限制：单页渲染体积 ≤ 20MB（超标则降级可视区域）、HTTP 超时 30s、仅 http/https（复用 `web_intelligence.provider._validate_url` 的 SSRF 门禁）。
  - 可注入 `driver_factory` seam（测试用 fake driver）。
- **SSRF 门禁**：捕获 `SSRFError` 和 `ValueError` 并翻译为中文说明。

### 2. pyproject 依赖 ✅

- `pyproject.toml` `[dependency-groups]` 新增 `snapshots = ["playwright>=1.40"]`，不进主依赖。

### 3. 测试 `tests/unit/test_snapshot.py` ✅（35 项）

| 测试组 | 项数 | 覆盖点 |
|--------|------|--------|
| TestPolicyForMode | 4 | 四个档位映射 |
| TestValidateUrl | 7 | 合法 http/https、非法 scheme、user-info 拒绝 |
| TestSnapshotFilename | 3 | 格式稳定、确定性强、不同 URL 不同 |
| TestResolveDestDir | 4 | 创建目录、路径穿越拒绝、嵌套穿越、绝对路径 |
| TestPlaywrightUnavailable | 2 | `available()=False`、`capture()` 抛 RuntimeError |
| TestCaptureWithFakeDriver | 5 | 落盘+哈希、URL/timeout 传递、full_page 默认、无截断、确定性哈希 |
| TestCaptureWithSelector | 2 | 元素截图、选择器不匹配降级 |
| TestEdgeCases | 4 | 非 http 拒绝、空 URL、路径穿越 |
| TestSnapshotResult | 2 | frozen 不可变、repr 包含字段 |

### 4. MCP 接线（最小） ✅

`mcp/server.py` 的 `_start_research` checkpoint 写入 `snapshot_policy` 字段，值来自 `policy_for_mode(mode)`（WP-C）。未加新 MCP 工具。

## 门禁结果

```
ruff format   → 111 files left unchanged
ruff check    → All checks passed!
mypy          → Success: no issues found in 75 source files
pytest (unit/contract) → 137 passed, 320 deselected in 2.27s
```

## 范围外（未做）

- 真实浏览器下载集成
- artifact 入库联动
- REST 接口