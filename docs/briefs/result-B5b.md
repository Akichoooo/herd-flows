# Result B5b：Trawler 运维侧预登录（替代 WebUI 弹窗）

## 1. 交付清单

| 文件 | 类型 | 描述 |
|---|---|---|
| `scripts/trawler_prelogin.ps1` | PowerShell 运维入口 | 检查/生成 `TRAWLER_VAULT_KEY`，调用 Trawler 环境执行 prelogin / check / verify |
| `scripts/trawler_prelogin.py` | Python 核心逻辑 | 支持 `check`（环境与状态预检）、`prelogin`（有头人工登录与 vault 加密持久化）、`verify`（无头登录态与登录墙比对验证） |
| `scripts/setup_trawler_vault.ps1` | 运维文档/脚本 | 已更新头部注释，明确"WebUI 弹窗不可用 → 运维侧预登录"架构裁决与一键流程 |

## 2. 核心机制说明

1. **接口复用**：
   - 严格遵循只读调用 Trawler（`Trawler-mcp`）既有接口原则（`trawler.account_vault`、`trawler.live_browser`、`trawler.errors`、`trawler.fetcher`、`trawler.urlnorm`），未修改 Dragnet `src/` 或 Trawler 内部源码。
2. **透传机制**：
   - `run_pipeline.py:call_trawler_search` 通过 `os.environ.copy()` 自动透传 `TRAWLER_VAULT_KEY`，子进程自动读取加密的 `storage_state.json.enc`。
3. **预登录流程**：
   - 运维在有 GUI 桌面环境执行 `.\scripts\trawler_prelogin.ps1 -Mode prelogin`。
   - 打开有头浏览器（Patchright/Chromium）并进入小红书，运维完成扫码/短信验证。
   - 回车确认后，自动提取 `storage_state` 并通过 Fernet 密钥加密持久化至 Trawler account_vault，打印 Cookie 数量与最早过期时间。
4. **验证机制**：
   - 执行 `.\scripts\trawler_prelogin.ps1 -Mode verify`。
   - 启动无头浏览器，注入 vault 解密后的 `storage_state`，访问目标页面（如 `/explore`）并比对登录墙标识（"扫码登录"、"短信登录"、"请先登录"等）及无账号基线，输出 `PASS/FAIL`。

## 3. 验证与门禁结果

- **代码规范检查 (ruff)**：
  - 命令：`.venv\Scripts\python.exe -m ruff check scripts\trawler_prelogin.py`
  - 结果：`PASS` (0 errors)
- **类型检查 (mypy)**：
  - 命令：`.venv\Scripts\python.exe -m mypy scripts\trawler_prelogin.py`
  - 结果：`PASS` (Success: no issues found in 1 source file)
- **PowerShell 脚本预检 (check 模式)**：
  - 命令：`powershell.exe -ExecutionPolicy Bypass -File scripts\trawler_prelogin.ps1 -Mode check`
  - 结果：`PASS`（正确识别 Vault Key、Patchright 可用性、GUI 环境及目标域路径）
- **Vault 加密解密单元测试**：
  - 结果：`PASS`（验证了 `save_storage_state`、`get_storage_state`、Cookie 过期时间计算与登录墙特征检测逻辑）
- **真机预登录与站点验证**：
  - 结果：`待人工执行`（由于当前无交互式会话，无法在 CI/自动化代理中完成真机扫码/短信交互；脚本已在 Windows 环境就绪，随时供运维人员在交互终端执行）。

## 4. 边界与降级声明

1. **反爬与风控边界**：
   - 小红书具有高强度设备指纹、滑动验证码与行为风控机制。
   - 运维预登录仅解决进入站点的"登录墙"凭据问题，**不保证**高频或规模化爬取时不被风控拦截或阻断。
2. **降级方案**：
   - 若小红书 Cookie 过期、风控拦截或 verify 验证未通过，知识检索管道应自动降级至免登录源（如**知乎、今日头条、携程**等，已实测稳定可用）。

---
[WORKER_DONE] status: OK
