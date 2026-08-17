# Brief I：爬虫写文章面板改造为可编辑配置页（真连后端）

## 背景
nanobot WebUI 的 Dragnet 注入扩展（`scripts/nanobot-ext/dragnet-ext.js`，
注入机制见 `scripts/apply_nanobot_ext.ps1`）里"爬虫写文章"面板目前是静态文字列表。
用户要求：① 做成**可编辑的配置页**（数据真实读写 workspace 的 crawler 配置文件）；
② 视觉样式必须与 nanobot 设置页原生模块一致，不能只列文字。
配置数据源已就绪：`.nanobot/workspace/crawler-registry.yaml` 与
`crawler-sources.yaml`，加载/校验逻辑在 `src/dragnet/research/registry.py`
（load_registry / load_paid_sources / BudgetGate，45 项单测）。

## 任务
### 1. 配置 API（src/dragnet/enroll/api.py 内新增路由，复用同一 FastAPI app :8901）
- `GET /api/crawler-config` → 返回 {registry: ..., paid_sources: ...}（yaml 原文解析为 JSON）；
- `PUT /api/crawler-config` → body 同上结构；先用 registry.py 的校验函数全量校验
  （非法值返回 400 + 中文原因，不落盘），通过后原子写回两个 yaml 文件
  （写临时文件 + os.replace）；
- app 必须开 CORS：allow_origins=["*"]（本机内网工具）；
- 配置接口**不依赖数据库**：app 启动时 IngestGateway 用 lazy 初始化
  （现状若是启动即连库，改成首次用到才建），保证无库也能提供配置服务。
### 2. 面板重写（dragnet-ext.js 的 PANELS["#/dragnet/research"]）
- 打开面板时 fetch `http://127.0.0.1:8901/api/crawler-config`；服务不可达时
  显示明确错误卡与重试按钮，不显示假数据；
- 渲染为可编辑表单：
  - 爬虫服务器表：每行 role 下拉(primary/secondary/paid/private)、priority 数字框、
    enabled 开关、capabilities 只读标签；
  - 付费源表：每行 enabled 开关、单价数字框、月预算数字框、use_for 档位多选；
  - 底部"保存"与"重新加载"按钮；保存走 PUT，失败显示后端返回的中文错误。
### 3. 样式要求（关键，勿略过）
**禁止**继续用内联样式的文字表格。实现方式：打开 #/settings 用 DOM 检查原生
设置页的卡片/分组/输入控件 class（如 content 区容器、h2、分隔线、开关样式），
在面板里**复用同一批 Tailwind class**（bundle 里已存在这些样式）。
可先在浏览器里用 `document.querySelector('...').className` 抄出真实类名再写代码。
深浅主题都要正常（用 CSS 变量/currentColor，不写死颜色）。
### 4. 启动脚本
新增 `scripts/start_settings_api.ps1`：用 `.venv\Scripts\python.exe -m uvicorn
dragnet.enroll.api:create_app --factory --port 8901`（或现有 app 对象）启动服务。
验证服务起来后 GET 接口返回真实 yaml 内容。

## 门禁
- ruff format/check、mypy、pytest -m "unit or contract"（现有 384+ 必须保持全绿）；
- 手工验证：起服务 → 浏览器开面板 → 改一个 priority → 保存 → 检查
  crawler-registry.yaml 已更新 → 改回。
- 完成后部署扩展：`powershell -ExecutionPolicy Bypass -File scripts/apply_nanobot_ext.ps1`。
- 结果写 `docs/subclaw-briefs/result-I.md`。不要 git commit。
**不要改** 人脸录入面板（另一个任务负责）；dragnet-ext.js 只动
PANELS["#/dragnet/research"] 与必要的公共样式辅助函数。
