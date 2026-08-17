# Result H：修复被标记漏洞掩盖的 15 个测试失败

## 背景

`tests/conftest.py` 新增了按目录自动打标记，暴露出 15 个此前被 `-m` 过滤漏跑的失败。
三簇根因已定位并逐簇修复。

## 簇 1：tests/unit/test_doc_analyze_delivery.py（4 个）

**根因**：`_manifest()` 只放了 `request.json` 一个对象，而 `ResearchMaterialPackageManifest` 
契约要求 `request.json` / `plan.json` / `evidence.jsonl` / `claims.jsonl` +
`report/report-{v}.md` + `report/audit-{v}.json` 全齐。

**修法**：重写 `_manifest()` 为六对象完整清单（SHA-256 实时计算），
删除不再使用的 `_SHA` 常量，补齐 `json` import。
不做契约语义改动。

**涉及文件**：`tests/unit/test_doc_analyze_delivery.py`

## 簇 2：tests/unit/test_enroll_service.py（8 个 → 4 个生产代码修正 + 4 个测试修正）

### 2a. mock.patch 目标对齐（8 个可用性 → 4 个通过）

**根因**：`service.py` 在 `dedup_and_diversity` 方法体内 `import psycopg`（局部导入），
测试却用 `mock.patch("dragnet.enroll.service.psycopg.connect", ...)` 寻址模块级属性，
导致 `AttributeError`。

**修法**：将 mock 目标改为 `"psycopg.connect"`（全局模块名）。

### 2b. `_photo_hash_matches` 占位实现（2 个）

**根因**：`_photo_hash_matches(embedding, photo_hash)` 恒返回 `False`，
注释称"由数据库唯一约束兜底"，但去重逻辑显式依赖它做应用层预热查重，
属于生产代码缺陷。

**修法**：改为 `_photo_hash_matches(new_hash, stored_hash)` 做 SHA-256 hex 串相等比较；
`dedup_and_diversity` 增加 `photo_hashes: list[str] | None` 可选参数；
测试 `_run_dedup` 传参 `photo_hashes=["abc123"]` 对齐。

### 2c. 跨人查重嵌入维度不匹配（2 个）

**根因**：测试 mock 的跨人 embedding 为 `"[0.1,0.2]"`（2 维），
而新样本 embedding 为 512 维，`_cosine_distance` 因长度不等恒返回 1.0，
致 `low_distance_warns` 无告警、`far_distance` 无告警（后者靠巧合通过）。

**修法**：两处跨人 embedding 改用 `_embedding()` 构造 512 维向量
（`str(_embedding(0.2))` 和 `str(_embedding(-0.9))`），
使实际距离落在阈值可判定区间。

### 2d. `stage_enroll` 空 artifact 异常类型（1 个）

**根因**：测试期望 `DragnetError`，但 `stage_enroll` 抛的是 `EnrollError`（`RuntimeError` 子类）。

**修法**：测试改为 `pytest.raises(EnrollError)`。

### 2e. SQL 注入元字符匹配模式（1 个）

**根因**：测试正则 `"特殊|元字符"` 不匹配实际错误消息
`"custom person_id 含非法字符（仅允许字母/数字/中文/下划线/连字符/点）"`。

**修法**：模式改为 `"非法字符|SQL|元字符"`。

## 簇 3：tests/security/test_enroll_gate.py（3 个）

### 3a. DragnetError 未注册 FastAPI 异常处理器（2 个）

**根因**：`api.py` 中 `_actor()` 和 `fail(...)` 抛 `DragnetError` 但未被 FastAPI 捕获，
返回 500 而非 4xx。

**修法**：在 `create_app()` 注册 `@app.exception_handler(DragnetError)`：
- `PERMISSION_DENIED` / `UNAUTHENTICATED` / `REPLAY_DETECTED` → 403
- `VALIDATION_FAILED` 及其他 → 400
- `reason_code` 透传至 JSON 响应体

### 3b. SQL 注入元字符匹配模式（1 个）

**根因**：与 2e 相同，正则 `"特殊|元字符"` 不匹配 `"非法字符"` 开头的中文错误消息。

**修法**：模式改为 `"非法字符|SQL|元字符"`（与 2e 一致）。

## 最终计数

```
ruff format src tests         → 112 files already formatted
ruff check src tests          → All checks passed!
mypy                          → Success: no issues found in 75 source files
pytest tests -q -m "unit or contract or property or security"
                              → 384 passed, 73 deselected in 7.26s
```

之前：369 passed / 15 failed → 之后：384 passed / 0 failed。