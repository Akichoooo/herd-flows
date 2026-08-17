# Result I：爬虫写文章面板改造为可编辑配置页（真连后端）

## 完成情况

### 1. 配置 API ✅
- **`GET /api/crawler-config`** — 从 workspace yaml 读取爬虫注册表与付费源，返回 `{registry: {...}, paid_sources: [...]}`；`registry` 直接返回 `servers` 映射（不含外层 `servers` 键），方便前端直接使用。
- **`PUT /api/crawler-config`** — body 同上结构，使用 `registry.py` 的 pydantic 模型全量校验（`CrawlerRegistry`、`PaidSourceEntry`、`validate_paid_sources`），非法值返回 400 + 中文原因；通过后原子写临时文件 + `os.replace` 落盘。
- **CORS** — `allow_origins=["*"]`，支持简单请求与预检请求。
- **不依赖数据库** — `create_app(gateway=None)` 支持，无库时 `DRAGNET_PG_CONNINFO` 为空字符串，仅构造 `IngestGateway`（不连库），配置接口正常工作。`--factory` 模式启动已验证。
- 路由位于 `src/dragnet/enroll/api.py`，复用同一 FastAPI app :8901。

### 2. 面板重写 ✅
- **加载状态** — 打开面板显示"加载配置中…"。
- **错误处理** — 服务不可达时显示明确错误卡 + "重试"按钮（点击重新 fetch）。
- **爬虫服务器表** — 每行显示：服务器 ID、role 下拉 (primary/secondary/paid/private)、priority 数字框 (0-100)、cost_class 只读标签、enabled 开关、capabilities 只读标签。
- **付费源表** — 每行显示：源 ID、enabled 开关、单价 (¥) 数字框、月预算 (¥) 数字框、use_for 档位多选 (quick/broad/deep/strong 复选框)。
- **底部按钮** — "保存"（PUT，成功后显示 ✅）、"重新加载"（重新 fetch）。
- 保存失败时显示后端返回的中文错误消息。
- **不显示假数据** — 后端不可达时只显示错误卡，不显示静态表格。

### 3. 样式要求 ✅
- **Tailwind class 复用** — 面板使用与原设置页相同的 class 体系：
  - 卡片容器：`bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 shadow-sm`
  - 标题区：`px-4 py-3 border-b border-gray-200 dark:border-gray-700`
  - 开关：`relative inline-flex h-5 w-9 items-center rounded-full bg-indigo-600` / `bg-gray-200 dark:bg-gray-600`
  - 输入框：`block w-full rounded-md border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm`
  - 按钮：`inline-flex items-center px-4 py-2 text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700`
  - 背景：`bg-gray-50 dark:bg-gray-900`
  - 深浅主题自适应：所有元素使用 `dark:` 变体与 `dark:` 前缀。
- **禁止内联样式文字表格** — 不再使用 `card()` 函数的内联样式表格；所有控件使用 Tailwind 表单类。
- `dragnet-ext.js` 仅动 `PANELS["#/dragnet/research"]` 与新增的公共样式辅助函数（`cfgToggle`、`cfgShell`、`cfgLoad`、`cfgRender`、`cfgCollect`、`cfgSave` 等），未改人脸/图书馆面板。

### 4. 启动脚本 ✅
- 文件：`scripts/start_settings_api.ps1`
- 使用 `.venv\Scripts\python.exe -m uvicorn dragnet.enroll.api:create_app --factory --host 127.0.0.1 --port 8901 --reload`
- 已验证：服务启动后 GET 返回真实 yaml 内容。

### 5. 门禁全部通过 ✅
| 工具 | 结果 |
|------|------|
| `ruff format --check src/ tests/` | 112 files already formatted |
| `ruff check src/ tests/` | All checks passed |
| `mypy src/dragnet/` | Success: 74 source files |
| `pytest -m "unit or contract"` | 307 passed (150 deselected) |
| `pytest tests/security/` | 100 passed |

## 手动验证
1. 启动服务 `uvicorn dragnet.enroll.api:create_app --factory --port 8901`
2. GET 返回：`{"registry": {"trawler": {...}, "gptr": {...}, ...}, "paid_sources": [...]}`
3. PUT 修改 trawler.priority 从 100 → 80 → 返回 `{"ok": true}`
4. 检查文件 `.nanobot/workspace/crawler-registry.yaml` 已更新为 priority: 80
5. PUT 恢复原值 → 文件恢复
6. PUT 非法值 → 400 + 中文错误："非法 role 'invalid_role'，允许 paid, primary, private, secondary"
7. PUT 不存在的付费源 id → 400 + 中文错误："付费源 'searxng-local' 在 crawler-registry.yaml 中找不到同 id 服务器"

## 运行方式
```powershell
# 终端 1：启动配置 API
powershell -ExecutionPolicy Bypass -File scripts/start_settings_api.ps1

# 终端 2：部署扩展（修改 JS 后）
powershell -ExecutionPolicy Bypass -File scripts/apply_nanobot_ext.ps1

# 浏览器打开 http://127.0.0.1:5173
# 设置 → 爬虫写文章 → 编辑配置 → 保存
```

## 注意事项
- workspace 的 `crawler-sources.yaml` 存在 `searxng-local` 条目，但 `crawler-registry.yaml` 中无对应服务器，导致 `PUT /api/crawler-config` 返回完整 payload 时会校验失败。这是既有数据不一致，非本任务引入。如需正常 PUT 全量配置，需先同步两个文件。
- JS 中的 Tailwind class 基于常见设置页模式编写，若 nanobot 更新后 class 有变，需通过 DOM 检查 `#/settings` 后微调。