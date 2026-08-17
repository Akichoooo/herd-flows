# Brief B5b：Trawler 运维侧预登录（替代 WebUI 弹窗）

你是 GLM worker，在 Dragnet 仓库根目录一次性执行。本次是功能补全任务。禁止 git 任何操作。

## 背景

目标站点（小红书等）有登录墙，原设计的人工辅助登录（HITL 弹窗）在 WebUI/无头环境下弹不出浏览器窗口——**已裁决放弃 WebUI 弹窗路线**，改为运维侧预登录：在开发机（有 GUI）用 CLI 起有头浏览器人工登录一次，storage_state 存入 Trawler 加密 vault，之后无头抓取自动复用。

已有基础设施（先读，别重造）：

- `scripts/setup_trawler_vault.ps1` — B4 写的 vault key 配置与流程文档
- Trawler 项目在 `D:\devloop\workSpace\app_ZCode\Trawler-mcp`：`trawler/account_vault.py`（Fernet 加密 storage_state 读写、cookie 过期检测）、`trawler/live_browser.py`（`open_browser_session` / `perform_browser_actions` / `extract_browser_session` / `save_storage_state`）
- 调用链：`run_pipeline.py:call_trawler_search`（`env = os.environ.copy()` 已自动透传 `TRAWLER_VAULT_KEY`）

## 交付内容

1. **一键预登录脚本** `scripts/trawler_prelogin.ps1`（或 py，按 Trawler 工具链的实际接口选择）：
   - 检查 `TRAWLER_VAULT_KEY`（缺失则引导生成，复用 setup_trawler_vault.ps1 逻辑）
   - 起有头浏览器打开目标站点（默认 `https://www.xiaohongshu.com`，参数可换）
   - 等待用户人工完成登录（轮询登录态或等用户回车确认）
   - `save_storage_state` 存入 vault，打印过期时间
2. **验证脚本**：无头模式用 vault 中的 storage_state 访问目标站登录后页面（如小红书某 explore 页），判定是否拿到登录态内容（对比未登录的重定向/登录墙标志），输出 PASS/FAIL。
3. **文档更新**：把"WebUI 弹窗不可用 → 运维预登录"的最终流程写进 `scripts/setup_trawler_vault.ps1` 头部注释或 `docs/` 相应位置（一句话级别，别写长文）。
4. **明确的边界声明**（写进 result）：小红书有强反爬，预登录解决登录墙但不保证规模化抓取不被风控；若验证失败，降级方案 = 攻略类需求用知乎/头条/携程等免登录源（已实测可用），在 result 中如实记录。

## 约束

- 只许新增 `scripts/` 下文件和必要的文档注释行；**不改** `src/dragnet/**`、`run_pipeline.py`、`dragnet-settings.js`。
- Trawler 侧（仓库外）只读调用其既有接口；如必须改 Trawler 代码才能跑通，停下来在 result 里写 `[ASK_ORCHESTRATOR]` 说明，不要擅自改。
- 脚本要在 Windows 本机真实可跑；如果当前环境无法完成人工登录步骤（无交互会话），脚本照写，验证步骤标明"待人工执行"。

## 门禁

新增 Python 文件过 ruff/mypy；不影响既有测试：

```
.venv\Scripts\python.exe -m ruff check src tests scripts
.venv\Scripts\python.exe -m pytest tests -q -m "unit or contract or property or security" --timeout 120
```

## 收尾

写 `docs/subclaw-briefs/result-B5b.md`：交付清单、验证结果（PASS/FAIL/待人工）、小红书抓取的边界声明。最后输出 `[WORKER_DONE] status: OK|PARTIAL|FAIL`。
