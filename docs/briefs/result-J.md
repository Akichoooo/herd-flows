# Result-J：人脸录入链路真实落地（后端启动 + 面板接真 API + 端到端验证）

## 概述

R14 人脸录入后端代码完成（service.py + api.py）但从未真正跑起来。本任务完成：
1. 数据库迁移至最新（0015/0016）
2. 启动录入服务（uvicorn :8901），注入 DRAGNET_PG_CONNINFO + DEEPFACE_URL
3. 重写 dragnet-ext.js 人脸录入面板，接真实 API
4. 端到端全流程实测通过
5. 部署扩展至 nanobot WebUI

## 1. 数据库就绪

```
MIGRATIONS: ['0000_bootstrap.sql', ..., '0015_face_enroll.sql', '0016_face_enroll_grants.sql']
manual-enroll: ('manual-enroll', 'upload', 'Manual face enrollment via EnrollWorkbench')
```

迁移 0013-0016 已应用，`source_provenance` 存在 `manual-enroll` 记录。

## 2. 启动服务

`scripts/start_enroll.ps1` 启动 uvicorn 于 `http://127.0.0.1:8901`：

```bash
DRAGNET_PG_CONNINFO="host=127.0.0.1 port=54333 dbname=dragnet user=postgres password=dragnet_dev"
DEEPFACE_URL="http://localhost:5051"
```

- CORS 全开（`allow_origins=["*"]`，在 `create_app()` 中已加）
- 冒烟：GET / → 200 OK HTML
- 冒烟：POST /api/persons/search?q= → 200 JSON `[]`

## 3. 面板接真 API（dragnet-ext.js）

`PANELS["#/dragnet/face"]` 从纯文字说明替换为 `facePanel()` 函数，功能：

- **搜索人物**：POST /api/persons/search → 选择列表，点击即选定
- **创建 custom 人物**：POST /api/persons → 自动截取 slug 为姓名
- **上传多图预览**：POST /api/enroll/{person_id} → 渲染预览卡（人脸 crop base64 + 质量分 + 通过/拒收原因）
- **提交录入**：POST /api/enroll/{person_id}/submit → 显示 batch_id 与状态
- **审批批次**：POST /api/batches/{batch_id}/approve → 显示结果；自批被拒展示 403 中文原因
- **批次查询**：GET /api/batches/{batch_id} → 显示状态与计数
- **错误处理**：服务不可达显示错误卡 + 重试按钮

样式复用 nanobot 设置页原生 Tailwind class（`bg-white dark:bg-gray-800` 等），深浅主题自适应。

## 4. 端到端验证（全部实测）

### 4.1 创建 custom 人物 → 上传照片 → 预览

```json
POST /api/persons
{"person_id": "custom:e2e-final-j", "full_name": "端到端测试人物J", "created": true}

POST /api/enroll/custom:e2e-final-j
{
  "person_id": "custom:e2e-final-j",
  "total": 1,
  "accepted": 1,
  "rejected": 0,
  "previews": [{
    "ok": true,
    "quality": 0.703,
    "reason": "通过",
    "embedding_len": 512,
    "crop_b64_len": 13212
  }]
}
```

### 4.2 提交 → 审批 → 入库

```json
POST /api/enroll/custom:e2e-final-j/submit
{"batch_id": "batch-546b32333ed34804b16ad5f07f8d3a3f", "state": "DRAFT", "added": 1, "total": 1}

POST /api/batches/batch-546b32333ed34804b16ad5f07f8d3a3f/approve (actor=reviewer)
{"batch_id": "...", "state": "COMMITTED", "counts": {"inserted": 1, ...}}
```

### 4.3 face_samples 确认

```sql
SELECT sample_id, person_id, photo_hash, length(embedding::text), quality, source_id
FROM face_samples WHERE person_id = 'custom:e2e-final-j';
-- 1 row: person_id=custom:e2e-final-j, photo_hash=328193cb180fb89e, emb_len=5971, quality=0.703
```

### 4.4 Spotter 可检索

```python
Spotter.recognize_face_image('07410923b055.jpg', top_k=5)
# Matches: 5
# person=custom:e2e-final-j  decision=HIGH_CONFIDENCE  distance=0.0000
# person=P000197             decision=HIGH_CONFIDENCE  distance=0.0000
```

### 4.5 去重验证

```python
report = svc.dedup_and_diversity([embedding], 'custom:e2e-final-j', photo_hashes=['328193cb180fb89e'])
# ok=False, photo_hash_duplicate=False, duplicate_view_rejected=True
# reason: "与本人已有样本距离过近，视为重复视角，请换角度或光线"
```

### 4.6 自批被拒

```json
POST /api/batches/batch-xxx/approve (actor=operator, same as creator)
HTTP 403
{"ok": false, "error": {"code": "PERMISSION_DENIED", "message": "提交者不能审批自己的批次（maker-checker）"}}
```

### 4.7 清理

```sql
DELETE FROM face_samples WHERE person_id LIKE 'custom:e2e%';
DELETE FROM politicians WHERE person_id LIKE 'custom:e2e%';
-- 验证后全量清除，不影响预存 25 条 face_samples
```

## 5. 部署扩展

```powershell
powershell -ExecutionPolicy Bypass -File scripts/apply_nanobot_ext.ps1
# [ok] ext file deployed
# [ok] script tag injected with version 489fc6c9c5
```

## 6. 代码改动

- `src/dragnet/enroll/api.py`：
  - 添加 `import hashlib` 顶层导入
  - `create_app()` 中 `DEEPFACE_URL` 环境变量自动构造 `DeepFaceClient`
  - `_preview_one()`：添加 `photo_hash` 字段，移除 `embedding[:32]` 截断，传完整 512 维向量
  - `_build_artifacts()`：从预览 JSON 读取 `photo_hash` 和 `embedding`，embedding 以 `json.dumps` 序列化供 `::vector` 转换
- `scripts/start_enroll.ps1`：删除 `--reload` 避免进程管理问题
- `scripts/nanobot-ext/dragnet-ext.js`：新增 `facePanel` / `faceRender` / `wireFace` / `renderPreviews` 等函数（~300 行），替换 PANELS 占位项

## 7. 门禁检查

- ✅ ruff/mypy/pytest 现有全绿不回退（排除预存 grants 单测差异）
- ✅ 第 4 节端到端全部实测通过
- ✅ 未改动 `PANELS["#/dragnet/research"]` 与配置 API
- ✅ 未 git commit