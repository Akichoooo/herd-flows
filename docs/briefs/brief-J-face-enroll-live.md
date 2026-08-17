# Brief J：人脸录入链路真实落地（后端启动 + 面板接真 API + 端到端验证）

## 背景
R14 人脸录入后端代码已完成（Brief B：`src/dragnet/enroll/service.py` +
`api.py` + `static/index.html`，maker-checker/质量分/去重/DragnetError→4xx 都齐，
单测全绿），但**从未真正跑起来**；nanobot WebUI 的"人脸录入"面板
（`scripts/nanobot-ext/dragnet-ext.js` 的 PANELS["#/dragnet/face"]）目前只是文字说明。
用户要求：链路真实可用，不要只有文字。
环境现成：dragnet-pg（PostgreSQL :54333，库 dragnet，conninfo 见
`.nanobot/config.json` 的 DRAGNET_PG_CONNINFO）与 dragnet-deepface
（:5051，/represent 接口）容器均在运行。

## 任务
### 1. 数据库就绪
- 用 `src/dragnet/storage/migrate.py`（或 docker exec dragnet-pg psql）应用迁移
  至最新（含 0015_face_enroll.sql / 0016_face_enroll_grants.sql）；
- 验证 source_provenance 存在 manual-enroll 记录（没有则按 0015 补）。
### 2. 启动服务
- `scripts/start_enroll.ps1`：uvicorn 起 dragnet.enroll.api app 于 :8901，
  注入 DRAGNET_PG_CONNINFO 与 DEEPFACE_URL=http://localhost:5051；
- 确认 app 开启 CORS（与 Brief I 同一 app，若其已加则复用）；
- 冒烟：GET /api/persons/search?q= 返回 200 JSON。
### 3. 面板接真 API（dragnet-ext.js 的 PANELS["#/dragnet/face"]）
功能流（fetch http://127.0.0.1:8901）：
1. 搜人物（输入姓名 → 列表）+ 创建 custom 人物（姓名 → custom:slug）；
2. 选定人物后上传多图（input multiple，≤12 张）→ 调
   POST /api/enroll/{person_id} → 渲染预览卡：人脸 crop（后端返回 base64）+
   质量分 + 通过/拒收原因；
3. 提交（POST submit）→ 显示 batch_id 与状态；
4. 审批区：输入审批者 actor_id（≠提交者）调 POST approve → 显示结果；
   自批被拒要能展示 403 的中文原因；
5. 批次状态查询（GET /api/batches/{id}）。
样式与 Brief I 同一要求：复用 nanobot 设置页原生 Tailwind class，
禁止纯文字列表；深/浅主题正常；服务不可达显示错误卡 + 重试。
### 4. 端到端验证（必须真跑，不许只写"应该可以"）
- 找一张真实人脸照片（`.nanobot/media/websocket/` 下有现成 jpg）；
- 创建 custom 测试人物 → 上传该照片 → 预览出现质量分 → 提交 →
  用另一 actor 审批 → psql 查 face_samples 新增行（person_id/photo_hash/embedding 非空）；
- 用 MCP Spotter 验证可检索：`.venv\Scripts\python.exe` 直接调
  Spotter.recognize_face_image(该照片) 返回该 custom 人物；
- 再传一张同人照片验证去重/重复视角行为符合预期；
- 验证完清理测试数据（face_samples 与 custom 人物行删除），在 result 里记录过程。
### 5. 部署扩展
改完 dragnet-ext.js 后执行
`powershell -ExecutionPolicy Bypass -File scripts/apply_nanobot_ext.ps1`。

## 门禁
- ruff/mypy/pytest 现有全绿不回退；
- 第 4 节端到端全部实测通过并在 result-J.md 贴关键输出（psql 行数、Spotter 返回）；
- 结果写 `docs/subclaw-briefs/result-J.md`。不要 git commit。
**不要动** PANELS["#/dragnet/research"] 与配置 API（另一个任务负责）；
若与其并行执行（编排上为串行），以其交卷版本为 dragnet-ext.js 基线继续改。
