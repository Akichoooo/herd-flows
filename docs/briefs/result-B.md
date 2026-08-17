# R14 WP1-WP3 人脸录入模块实施结果

## 改动文件清单

### 新增（未跟踪）
| 文件 | 说明 |
|------|------|
| `database/migrations/0015_face_enroll.sql` | 注册 `manual-enroll` 来源记录（幂等） |
| `database/migrations/0016_face_enroll_grants.sql` | 权限确认注释（已有权限，无需新增 GRANT） |
| `src/dragnet/enroll/__init__.py` | 模块入口 docstring |
| `src/dragnet/enroll/service.py` | EnrollService 核心：check_image / score_quality / dedup_and_diversity / stage_enroll / supplement_from_web + 工具函数 |
| `src/dragnet/enroll/api.py` | FastAPI 录入页：8 个端点 + 审批 maker-checker |
| `src/dragnet/enroll/static/index.html` | 单页前端（原生 HTML+JS）：搜索/创建人物、上传预览、提交、批次查询、审批 |
| `tests/unit/test_enroll_service.py` | 单元测试：check_image 各分支、质量分单调性、dedup 三类判定、stage_enroll、custom person_id 注入 |
| `tests/security/test_enroll_gate.py` | 安全测试：自批被拒、超大文件、非法 MIME、SQL 元字符/路径穿越注入 |

### 修改（已跟踪）
| 文件 | 变更 |
|------|------|
| `pyproject.toml` | 新增 `numpy>=1.26` 依赖；新增 `api.py` 的 B008 豁免；新增 `research/store.py` 的 S608 豁免 |

## 门禁输出尾部摘要

```
.venv\Scripts\python.exe -m ruff format src tests --check
106 files already formatted

.venv\Scripts\python.exe -m ruff check src tests
All checks passed!

.venv\Scripts\python.exe -m mypy
Success: no issues found in 73 source files

.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract or security" --timeout 120
132 passed, 230 deselected in 2.69s
```

## 实现要点

### WP1 — Schema 与身份命名空间
- `0015_face_enroll.sql`：`source_provenance` 中 upsert `manual-enroll` 来源（ON CONFLICT DO NOTHING 幂等）
- `0016_face_enroll_grants.sql`：确认 `dragnet_ingest` 已有 `source_provenance` 写权限（0002_grants.sql 已授），仅注释
- 库外人物 `person_id='custom:<slug>'`，`validate_custom_person_id()` 防注入：slug 白名单 `[A-Za-z0-9_中文.-]`，拦截 SQL 元字符与路径穿越

### WP2 — EnrollService
- **check_image**：MIME 魔数侦测、≤10MB、PIL 解码、EXIF 剥离、≥224px 最小边
- **score_quality**：Laplacian 方差（清晰度）+ 亮度 + 人脸占比 + 分辨率，加权 0.35/0.25/0.25/0.15，<0.4 拒收
- **dedup_and_diversity**：photo_hash → 跳过；跨人距离 <0.5 → 告警；本人距离 <0.15 → 重复视角拒收
- **stage_enroll**：IngestGateway create_batch(kind=FACE_SAMPLES, source="manual-enroll")，payload 与 register_faces.py 一致，preprocess_version="pp-2"
- **supplement_from_web**：经 `safe_fetch` SSRF 门禁，复用 quality/dedup 链路

### WP3 — FastAPI 录入页
- 独立进程端口 `ENROLL_PORT`（缺省 8901）
- 端点：`GET /`、`POST /api/persons/search`、`POST /api/persons`、`POST /api/enroll/{person_id}`（multipart ≤12 张）、`POST /api/enroll/{person_id}/submit`、`POST /api/batches/{id}/approve`、`GET /api/batches/{id}`
- maker-checker：`actor_id == 提交者 → 403` 拒绝
- 单页前端：侧栏导航（录入/批次）、搜索人物、创建 custom 人物、上传预览（crop + 质量分 badge）、提交、审批

## 遗留问题
1. 无真实 DeepFace 容器时预览阶段 embedding 为空（`[]`），提交后 face_samples 行仅含元数据，Spotter 检索不可用。需 WP4 接入真实容器或 mock 注入。
2. supplement_from_web 当前仅处理显式 URL 列表，自动搜索补采（auto 模式）未实现。
3. 无 eval 回归集（WP5 范围外）。
4. 无对话侧入口（MCP 工具，WP6 可选）。