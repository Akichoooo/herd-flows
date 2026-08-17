# Brief C：爬虫注册表与付费源配置（crawler-registry）

## 背景
Dragnet 的搜索编排要支持多爬虫 MCP + 付费信息源，配置驱动、AI 按能力标签编排。
设计依据：`docs/R16-爬虫编排层与知识闭环整合方案.md` §2（先读）。
本任务只落配置层与加载器，不改 MCP server、不改 workflow。

## 任务
### 1. 配置文件（放 `.nanobot/workspace/`，供 nanobot 工作区使用）
`crawler-registry.yaml`：
```yaml
servers:
  trawler:
    role: primary            # primary|secondary|paid|private
    capabilities: [search.web, fetch.web, fetch.pdf, archive.raw]
    cost_class: free
    priority: 100
    enabled: true
  gptr:
    role: secondary
    capabilities: [search.web, research.deep]
    cost_class: token_cost
    priority: 60
    enabled: true
  dragnet-local:
    role: private
    capabilities: [search.private, analyze.entity]
    cost_class: free
    priority: 90
    enabled: true
  tavily:
    role: paid
    capabilities: [search.web, search.news]
    cost_class: paid
    priority: 40
    enabled: false
```
`crawler-sources.yaml`：
```yaml
paid_sources:
  - id: tavily
    enabled: false
    pricing: {unit: per_call, cny: 0.03}
    monthly_budget_cny: 200
    use_for: [deep, strong]     # 允许动用的研究档位
  - id: searxng-local
    enabled: false
    pricing: {unit: free, cny: 0}
    monthly_budget_cny: 0
    use_for: [quick, broad, deep, strong]
```
### 2. 加载器 `src/dragnet/research/registry.py`
- Pydantic v2 frozen 模型：CrawlerServerEntry、PaidSourceEntry、Pricing；
- `load_registry(path) -> CrawlerRegistry`、`load_paid_sources(path) -> tuple[PaidSourceEntry,...]`（pyyaml 已在依赖）；
- 校验规则：role 枚举；priority 0-100；capabilities 非空且形如 `域.能力`；
  paid_sources 的 id 必须能在 registry 找到同 id 服务器（找不到 → 抛错）；
- `BudgetGate.can_use(source_id, mode, spent_cny) -> tuple[bool, str]`：
  未启用拒、档位不准拒、超月预算拒，返回 (可否, 中文原因)；
- `select_server(registry, capability, mode, gate, spent)`：
  返回按 priority 降序的第一个 enabled 且通过预算闸的 server，找不到返回 None。
### 3. 测试 `tests/unit/test_crawler_registry.py`
覆盖：YAML 解析、非法 role/capability 拒绝、paid id 孤儿拒绝、
BudgetGate 三种拒绝、select_server 优先级与预算联动。
用 tmp_path 写临时 YAML，不依赖工作区文件。
### 4. 文档联动
更新 `.nanobot/workspace/AGENTS.md` 的"新增爬虫/搜索 MCP 工具的约定"一节，
补两句：新爬虫先登记 crawler-registry.yaml；付费源先登记 crawler-sources.yaml。
（该文件其他内容不许动。）

## 范围外
MCP 健康检查、WebUI、真实调用计费落库。

## 门禁（全过才算完成）
```
.venv\Scripts\python.exe -m ruff format src tests
.venv\Scripts\python.exe -m ruff check src tests
.venv\Scripts\python.exe -m mypy
.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract" --timeout 120
```
完成后写 `docs/subclaw-briefs/result-C.md`。不要 git commit。
**不要碰** src/dragnet/mcp/server.py 与 tests/unit/test_mcp_server.py（另一个 worker 在改）。
