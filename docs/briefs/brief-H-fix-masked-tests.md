# Brief H：修复被标记漏洞掩盖的 15 个测试失败

## 背景
`tests/conftest.py` 新增了按目录自动打标记，暴露出 15 个此前被 `-m` 过滤漏跑的失败。
三簇根因已定位，逐簇修复。**原则：契约与 P0 基线优先；生产代码确有问题才改生产代码，
否则修测试。**

## 簇 1：tests/unit/test_doc_analyze_delivery.py（4 个）
`_manifest()` 只放了 request.json 一个对象，而 ResearchMaterialPackageManifest 契约
要求 request/plan/evidence/claims + report-{v}.md + audit-{v}.json 全齐。
修 `_manifest()` 补齐全部必需对象（照抄 `tests/unit/test_doc_analyze_publisher.py`
的 `_manifest` 写法即可），让 4 个失败用例通过；不改生产适配器语义。

## 簇 2：tests/unit/test_enroll_service.py（8 个）
`AttributeError: module 'dragnet.enroll.service' has no attribute 'psycopg'` ——
测试 monkeypatch 的对象在 service.py 里不存在（导入方式不一致）。
先读 `src/dragnet/enroll/service.py` 的真实导入与依赖注入方式，把测试的
mock/patch 目标对齐真实结构；**断言强度不许降低**（去重三类判定、stage 拒绝空
artifact 等行为必须仍被验证）。

## 簇 3：tests/security/test_enroll_gate.py（3 个）
API 层 `fail(...)` 抛 DragnetError 后未被 FastAPI 捕获，变成 500。
在 `src/dragnet/enroll/api.py` 增加 DragnetError → 4xx JSON 的异常处理器
（ACTOR_MISSING/权限类→403，校验类→400，reason_code 透传），
测试断言状态码与 reason_code；自批拒绝仍为 403。

## 门禁（全过才算完成）
```
.venv\Scripts\python.exe -m ruff format src tests
.venv\Scripts\python.exe -m ruff check src tests
.venv\Scripts\python.exe -m mypy
.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract or property or security" --timeout 120
```
注意：conftest 现在自动打标记，上述命令会跑全部单测/契约/安全测试，
必须 0 failed 才算完成（之前 369 passed / 15 failed）。
完成后写 `docs/subclaw-briefs/result-H.md`（三簇各自的修法与最终计数）。
不要 git commit。不要动 tests/conftest.py。
