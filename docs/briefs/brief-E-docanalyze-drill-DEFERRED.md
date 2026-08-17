# Brief E：docAnalyze 实联调（暂缓，留档待派）

> 状态：**暂缓**。用户决定暂不执行；需要时把本 brief 交给实施 agent（dsv4f 或 claw-pool）。
> 前置条件：docAnalyzeSystem-u3.0 Java 服务可启动（MySQL 就绪）。

## 背景
Dragnet 侧投递适配器（`src/dragnet/research/adapters/doc_analyze.py`）与 docAnalyze
接收端（`ResearchPackageController`，5 端点）的协议字段已逐项核对一致（见
`docs/R15-研究型Agent接管盘点与路线图.md` §2），单测覆盖了幂等恢复/超时恢复/冲突拒绝。
本任务做真实 HTTP 联调。

## 任务
1. 启动 docAnalyzeSystem-u3.0（`D:\devloop\workSpace\app_ZCode\docAnalyzeSystem-u3.0`，
   确认端口与鉴权方式：controller 用 `@RequestAttribute("username")`，查清网关怎么注入）；
2. 配置 Dragnet 侧：环境变量 `DOCANALYZE_BASE_URL` / `DOCANALYZE_TOKEN`（写进
   `.env.example` 说明）；
3. 联调脚本 `scripts/drill_docanalyze_delivery.py`：
   capabilities 探测 → 用真实研究包（可先 build_research_package 产出）stage →
   查状态 → publish → 确认 `knowledge_library/<工作区>/02-分析笔记/` 出现报告文件；
4. 幂等演练：同一幂等键重复 stage 不产生第二份；stage 后人工 kill 网络重试恢复；
5. 失败路径：错误 token、超大包、非法 targetCategory 各验一次；
6. 结果写 `evidence/integration/docanalyze-delivery-drill.md`（含请求/响应摘录）。

## 门禁
联调脚本可重复执行（幂等）；演练记录含时间戳与两侧日志摘录；不改两侧生产代码，
若发现协议不一致，记录差异并提修复建议，不擅自改。

## 参考
- `docs/R15-研究型Agent接管盘点与路线图.md` §4 WP-D
- `outputs/Dragnet强搜索与报告知识闭环总体方案.md` §11
- `tests/unit/test_doc_analyze_delivery.py`（协议预期）
