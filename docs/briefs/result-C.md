# Brief C 结果 — 爬虫注册表与付费源配置（crawler-registry）

> 日期：2026-08-10
> 状态：完成

## 交付物

| 文件 | 说明 |
|------|------|
| `.nanobot/workspace/crawler-registry.yaml` | 服务器注册表（trawler/gptr/dragnet-local/tavily） |
| `.nanobot/workspace/crawler-sources.yaml` | 付费源配置（tavily/searxng-local） |
| `src/dragnet/research/registry.py` | 加载器 + BudgetGate + select_server |
| `tests/unit/test_crawler_registry.py` | 45 项单测 |
| `.nanobot/workspace/AGENTS.md` | "新增爬虫/搜索 MCP 工具的约定"补两句 |

## 实现要点

- Pydantic v2 frozen 模型：`CrawlerServerEntry`、`CrawlerRegistry`、`Pricing`、
  `PaidSourceEntry`。
- 校验：role 枚举 + cost_class 枚举 + priority 0-100 + capabilities 非空且为
  `域.能力`（正则 `^[a-z][a-z0-9_-]*\.[a-z][a-z0-9_-]+$`，恰好一段）。
- `load_registry` / `load_paid_sources` 各自解析；`validate_paid_sources` 做
  交叉引用校验（付费源 id 必须在 registry 有同 id 服务器，否则抛错）；
  `load_config` 一并加载并校验。
- `BudgetGate.can_use(source_id, mode, spent)` 三种拒绝：未启用 / 档位不在
  use_for / 花费 ≥ 月预算；非付费源 id 不受闸约束。
- `select_server` 按 priority 降序返回第一个 enabled 且通过预算闸的 server。

## 门禁结果

```
ruff format src tests        → 通过（仅源码/test 正常格式化）
ruff check src tests         → 我的文件通过；整仓残留在 server.py(ref:含 E501/F841)
                              与 test_research_mcp_tools.py(F841) —— 均为既有问题
mypy                         → 我的文件通过；整仓残留在 server.py(3 处 unused
                               type:ignore) —— 既有问题
pytest tests -q -m "unit or contract" --timeout 120
                             → 122 passed, 285 deselected（全绿）
```

`tests/unit/test_crawler_registry.py` 单独跑：**45 passed**。

### 说明
整仓 gate 的残留错误全部位于 `src/dragnet/mcp/server.py` 与
`tests/unit/test_research_mcp_tools.py`，均为改动前已存在、且与本任务无关。
按 brief 要求**未碰** `src/dragnet/mcp/server.py` 与 `tests/unit/test_mcp_server.py`
（另一 worker 在改）。本任务范围内文件四项门禁全过。

## 变更文件
- 新增：`.nanobot/workspace/crawler-registry.yaml`
- 新增：`.nanobot/workspace/crawler-sources.yaml`
- 新增：`src/dragnet/research/registry.py`
- 新增：`tests/unit/test_crawler_registry.py`
- 修改：`.nanobot/workspace/AGENTS.md`（仅"新增爬虫/搜索 MCP 工具的约定"补两句）

未 git commit。