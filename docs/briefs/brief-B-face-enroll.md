# Brief B：人脸录入模块 R14 WP1-WP3

## 背景
Dragnet 已有人脸识别（face_samples/pgvector HNSW/ArcFace-2026 512 维/DeepFace 容器），
缺"人工录入"写入链路。写入必须走 IngestGateway maker-checker（提交者≠审批者）。
必读文档：
1. `docs/R14-人脸录入模块实施方案.md`（完整设计，WP 分解在 §2）
2. `src/dragnet/pipelines/register_faces.py`（artifact payload 字段基准）
3. `src/dragnet/ingest/gateway.py`（create_batch/add_artifact/validate 接口）
4. `src/dragnet/mcp/deepface_client.py`（检测+提特征客户端）

## 任务
### WP1 迁移（注意编号！）
0013/0014 已被研究运行时占用。新建：
- `database/migrations/0015_face_enroll.sql`：在 source_provenance upsert 一条
  `source_id='manual-enroll'` 的种子语句（幂等，ON CONFLICT DO NOTHING）；
  face_samples 不加列。
- `database/migrations/0016_face_enroll_grants.sql`：dragnet_ingest 对
  source_provenance 已有写权限则只写注释说明；否则补 GRANT。
人物身份约定：库外人物 person_id='custom:<slug>'，同时向 politicians 写最小行
（参照 0001_init.sql 的列；release_id 用 active_release 当前 DATA release）。

### WP2 EnrollService（src/dragnet/enroll/service.py）
按 R14 §2 WP2 的签名实现：check_image / score_quality / dedup_and_diversity /
stage_enroll / supplement_from_web。要点：
- MIME 白名单 jpeg/png/webp，≤10MB，PIL 可解码，剥 EXIF（pillow 已在依赖）；
- 质量分用 PIL+numpy（新增 numpy 依赖：改 pyproject.toml dependencies，
  然后 `uv sync` 或 `.venv\Scripts\python.exe -m pip install numpy`）：
  清晰度（灰度 Laplacian 方差）+亮度+人脸占比+分辨率，<0.4 拒收并给中文原因；
- 多人脸（>1）拒收；
- dedup：photo_hash 去重；跨人最小距离 < threshold_set.high 告警；
  本人样本距离 <0.15 判重复视角拒收；
- stage_enroll 走 IngestGateway：kind=BatchKind.FACE_SAMPLES，
  payload 字段与 register_faces.py 完全一致（preprocess_version 用 "pp-2"）；
- supplement_from_web 用 web_intelligence.provider.safe_fetch。

### WP3 FastAPI 录入页（src/dragnet/enroll/api.py + static/index.html）
- 端口 env ENROLL_PORT 缺省 8901；
- 端点：GET /（单页，原生 HTML+JS 无构建）；POST /api/persons/search；
  POST /api/persons；POST /api/enroll/{person_id}（multipart ≤12 张，返回预览：
  每脸 crop base64 + 质量分 + 通过/拒收原因）；POST /api/enroll/{person_id}/submit；
  POST /api/batches/{id}/approve（审批者 actor 参数）；GET /api/batches/{id}；
- maker-checker：approve 的 actor_id == 提交者 actor_id 时必须拒绝；
- 页面风格朴素即可（参考 docs/prototypes/ 里的配色变量）。

## 测试（新增）
- `tests/unit/test_enroll_service.py`：check_image 各拒绝分支、质量分单调性、
  dedup 三类判定（hash/跨人/重复视角）；
- `tests/security/test_enroll_gate.py`：自批被拒、超大文件拒收、非法 MIME 拒收、
  custom person_id 注入防护（含 ../ 与 SQL 元字符）。
集成/数据库路径用 fake gateway 或 mock，不依赖 docker。

## 范围外
DeepFace 容器真实调用（mock DeepFaceClient）、对话侧 MCP 工具（WP6）、合成增强。

## 验收门禁（全部通过才算完成）
```
.venv\Scripts\python.exe -m ruff format src tests
.venv\Scripts\python.exe -m ruff check src tests
.venv\Scripts\python.exe -m mypy
.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract or security" --timeout 120
```
环境：Windows PowerShell，项目根 `D:\devloop\workSpace\app_ZCode\Dragnet`。
完成后在 `docs/subclaw-briefs/result-B.md` 写：改动文件清单、门禁输出尾部摘要、
遗留问题。不要 git commit。注意：另一个 worker 正在同仓库改
src/dragnet/mcp/server.py 与相关测试，**不要碰**这些文件，避免冲突。
