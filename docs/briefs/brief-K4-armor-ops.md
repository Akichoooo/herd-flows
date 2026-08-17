# Brief K4：Trawler 登录弹窗 + Dify 回退链路 + 生图配置 — 设计

你是 GLM worker，在 Dragnet 仓库根目录一次性执行。只出设计，禁止改业务代码/测试/配置，禁止 git 操作。

## 先读（全部真正读完再动笔）

1. `docs/subclaw-briefs/brief-armor-system-v1.md` — 总规格书（§8 §9 是你的范围）
2. `run_pipeline.py` 中 `call_trawler_search()` — Trawler 的现有调用方式（uv subprocess CLI）
3. `scripts/` 目录（deploy/preflight/fix_webui_access 等 ps1）— 现有部署与访问修复手段
4. 生图相关代码：用 Grep 在 `src/`、`scripts/`、`docs/` 搜 生图/多视角/扩增/image/角度 等关键词自行定位（已知线索：`scripts/nanobot-ext/dragnet-settings.js` 提到"AI多视角扩增"，`src/dragnet/enroll/` 是人脸录入模块，`docs/R14-人脸录入模块实施方案.md` 可能有设计）
5. `reports/` 下近期的 diagnostic 文件（diagnostic_20260813_*.json/md）——可能含生图/配置故障线索

## 共同架构契约（必须遵守）

- Trawler-mcp、Dify、本地 DB 都是明文区；只有云端 LLM API 是密文区。
- Dify 回退链路的交接素材一律明文。
- 配置/密钥走 `src/dragnet/config.py` 的既有模式或环境变量，禁止硬编码。

## 你的设计范围

1. **Trawler 无头登录弹窗**：
   - 至少三个方案的对比表：Playwright `storage_state` 预登录注入（headed 人工登录一次 → 保存 → headless 复用）、按站点 cookie 保险库（加密存放/过期检测/刷新）、手动接管模式（检测到登录墙时暂停并通知用户）；可加代理/UA 策略维度。
   - 给出**明确推荐**与取舍理由；推荐方案细化到文件落位与操作流程。
   - 列出"目前 WebUI 不可用"的排查清单（从 scripts/ 里的既有修复脚本反推可能原因）。
2. **Dify 回退链路**（规格书 §8）：Dragnet → 本地 Dify agent 的素材交接设计：MCP 工具形式（如 `gather_handoff(topic) → artifact_path`）、素材 JSON 结构（沿用 reports/raw_search_*.json 的现有格式）、Dify 侧消费方式（MCP 工具挂载/知识库导入）、本地 LLM 合成的衔接。本阶段只出接口设计与 PoC 验证步骤，不全量实施。
3. **生图模块修复 + 配置界面**：
   - 先诊断：通过第 4、5 项阅读定位"4 角度生图不可用/配置不生效"的最可能根因（配置加载路径、provider 接口、流程断裂），把根因分析写进文档，证据不足的标 `[RISK]`。
   - 配置面板设计：复用 dragnet-settings.js 注入模式新增"生图"设置区——provider/模型/key/参数 + **价格测试按钮**（发最小请求，回显成功/耗时/费用估算）。

## 交付物（只许写这两个文件）

1. `docs/rounds/R15d-armor-ops-design.md` — 上述全部内容，中文。
2. `docs/subclaw-briefs/result-K4.md` — 5-10 条设计要点 + 根因诊断结论 + 遗留问题。

## 硬性要求

- 引用的每个已有文件/函数必须先用 Read/Grep 验证存在，禁止编造路径。
- Trawler-mcp 项目在本仓库外的 `D:\devloop\workSpace\app_ZCode\Trawler-mcp`，能读则读，读不到就基于 run_pipeline.py 的调用方式设计并标注假设。
- 末尾输出：`[WORKER_DONE] status: OK|PARTIAL|FAIL`；关键结论用 `[CLAIM] 结论 | evidence: 文件:行 | confidence: high|medium|low` 标注。
