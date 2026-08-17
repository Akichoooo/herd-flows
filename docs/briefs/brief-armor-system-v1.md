# Brief: Dragnet Armor 穿卸甲系统 — 设计与实施

> 执行者：GLM5.2 ｜ 审核者：Kimi（对照代码库评审每一轮产出）
> 仓库：D:/devloop/workSpace/app_ZCode/Dragnet

## 0. 执行模式（两阶段，禁止跳步）

- **Phase A — 只产出设计文档**，写入 `docs/rounds/R15-armor-system-design.md`。
  包含：架构图、信任边界定义、数据模型、接口签名、改造文件清单、测试计划、风险清单。
  **Phase A 禁止修改任何业务代码。**
- **Phase B — 按批准后的设计实施**，小批量提交，每批附带可通过的 pytest。
  未收到 Phase A 评审通过结论前不得开始。

## 1. 必读文件（设计前必须全部读完并引用）

| 文件 | 读它的目的 |
|---|---|
| `run_pipeline.py` | 现有 cipher 全链路参考实现（搜索明文→加密素材→云端生成→解密） |
| `run_qa.py` | cipher 的 QA 验证方式 |
| `reports/cipher_test_20260813_160604.json` | 4 组对照实验数据：明文被 HTTP 400 拦截；编码+强制 token 契约（组3模式）可通过审核 |
| `scripts/nanobot-ext/dragnet-settings.js` | WebUI 注入扩展的既有模式（穿甲/卸甲按钮要复用此机制） |
| `src/dragnet/mcp/server.py` | MCP 工具注册方式（spotter/logbook/compass） |
| `src/dragnet/util/prompt_sanitizer.py` | 已有的 prompt 清洗逻辑，Armor 须与其整合而非另起炉灶 |
| `src/dragnet/egress/dlp.py` + `src/dragnet/egress/gateway.py` | 出站管控层，ArmorOn 应落位在这里 |
| `src/dragnet/config.py` | 配置管理模式 |
| `tests/` 目录结构 | 测试约定（unit / contract / property / integration） |

## 2. 核心架构原则：信任边界（最高优先级，理解错了全盘皆错）

Armor 是**边界编解码器**，不是流水线的一个阶段。

- **明文区（可信）**：本地一切组件 —— Trawler-mcp、gptr-mcp、本地 DB、本地 Dify、MCP Server、磁盘存储。
- **密文区（不可信）**：云端 LLM API（sensenova 等）的请求与响应。
- **ArmorOn 只发生在"即将发往云端 LLM"的出口；ArmorOff 只发生在"云端响应刚回来"的入口。**
- ❌ 错误：用户输入 → ArmorOn → Trawler 搜索。用 `[PERS_K1]` 搜互联网召回为零。
- ✅ 正确（`run_pipeline.py` 已验证）：明文搜索 → 素材 ArmorOn → 云端生成 → ArmorOff → 明文呈现。
- **本地数据库永远存明文。** 存密文会破坏全文检索、排序、关系图谱。"怕库文件被拷走"是磁盘加密/访问控制问题，不由 Armor 解决。原需求中"敏感文本字段穿甲后存入"一条作废，按此更正执行。

推论出的设计要求：

1. **多轮对话**：历史消息中的明文必须在每次请求前重新 ArmorOn。
2. **流式输出**：nanobot 聊天是流式的，ArmorOff 必须能处理 token 被 chunk 切断的情况（缓冲到 token 边界再放行）。
3. **回退路由**：ArmorOn 后仍被云端拦截时，策略路由到本地模型/Dify 链路（见 §8），不得直接报错终止。

## 3. 词表管理

- 存储：独立词表文件（JSON/YAML），**加密存放、加入 .gitignore、禁止入库、禁止日志输出明文映射**。词表是本系统最敏感的资产。
- 结构：`{ token, category, 主词条, 变体列表, 启用状态, 版本, 备注 }`。
  变体必须覆盖：简体/繁体/拼音/常见谐音/英文名（如 朱镕基 → 朱鎔基 / zhu rongji / Zhu Rongji），同组变体映射到同一 token。
- 版本管理：词表带 version 号，审计日志记录每次穿甲/卸甲使用的版本；支持热更新与回滚。
- 管理接口：MCP 工具或 CLI 提供增删查、泄露自检（对样本密文扫描残留明文）。

## 4. 穿甲引擎 ArmorOn

- 算法：多模式串最长优先匹配（Aho-Corasick，词表上千条后正则交替会慢且行为不可控）。
- 匹配选项：大小写、全半角归一；是否需要"上下文感知/模糊匹配"由你在设计中论证——**给结论和理由，不要两个都做**。
- 输出附带：替换计数、命中词条 ID 列表（供审计与卸甲校验）。

## 5. 卸甲引擎 ArmorOff

- 100% 可逆是硬指标：对任意文本 `ArmorOff(ArmorOn(x))` 中敏感信息零丢失（允许标点/空白差异，用语义级断言）。
- 必须处理：模型输出中 token 被轻微改写（大小写、全角括号、多余空格）→ 容错匹配 + 修复；修复行为记入审计。
- 未知/残留 token 策略：原样保留 + 告警 + 计数上报，禁止静默丢弃。
- 用 property-based 测试（仓库已有 `tests/property/` 与 hypothesis）覆盖可逆性。

## 6. 三模块改造

- **Face**：本地识别不穿甲。仅在"外部识图 API 接入层"预留 armor 出入站钩子（接口 + 默认直通实现）。改造量保持小。
- **Profile**：库存明文（见 §2）。改造点只有一处：档案内容被送入云端 LLM 的链路出口统一走 ArmorOn。展示层不需要卸甲按钮逻辑（本来就是明文）。
- **Gathering（核心）**：把 `run_pipeline.py` 的四阶段（搜索→加密→生成→解密）产品化为 `src/dragnet/research/` 下的正式工作流：
  - 系统 prompt 的 token 契约（组3模式：定义 token 含义 + 强制原样保留）做成可配置模板，词表变更时自动同步契约段。
  - 技能/流程/模板的可编排化：给出 YAML 工作流定义 schema（步骤、数据源、模板、是否穿甲），引擎按 schema 执行。
  - 采集结果明文落盘（沿用 `reports/` 或归档目录），档案模块可读。

## 7. UI（nanobot WebUI :5173）

- 复用 `scripts/nanobot-ext/dragnet-settings.js` 的 DOM 注入模式，在聊天输入框发送键旁注入两个按钮：**穿甲**（hover: 穿甲 ArmorOn）、**卸甲**（hover: 卸甲 ArmorOff）。
- 交互定稿（解决原需求的自相矛盾——"用户可见替换结果"与"用户始终看到真实内容"冲突）：
  - 默认**自动穿甲**：发送时透明 ArmorOn，聊天界面永远显示明文；
  - 按钮为**手动预览/调试**：点穿甲在输入框预览替换结果（可一键还原），点卸甲对选中/最新一条回复手动触发还原；
  - 状态指示：当前消息是否已穿甲（图标/颜色），穿甲命中词条数 toast。
- 后端通过本地 API（复用 `api()` helper 的 fetch 模式）调用 MCP 侧 armor 接口，词表不出后端。

## 8. Trawler-mcp 登录弹窗 + Dify 回退链路

- 设计多方案并推荐其一，至少覆盖：Playwright `storage_state` 预登录注入（headed 人工登录一次 → 保存状态 → headless 复用）、按站点的 cookie 保险库（加密存放、过期检测）、代理/UA 策略、手动接管模式。给出推荐与取舍理由。
- 明确"目前 WebUI 不可用"的具体所指并在设计中列出排查项。
- **Dify 回退链路**：设计 Dragnet → 本地 Dify agent 的素材交接（明文素材 JSON → Dify 工具/知识库），Dify 侧用 Trawler-MCP 搜索 + 本地 LLM 合成。以 MCP 工具形式暴露（如 `gather_handoff(topic) → artifact_path`）。本阶段只出接口设计与 PoC 验证，不全量实施。

## 9. 生图模块

- 先诊断后设计：定位"4 角度生图不可用"的根因（配置不生效/模型接口/流程断裂），把根因写进设计文档。
- 配置界面：复用 settings 注入模式新增"生图"面板：provider/模型/key/参数，**价格测试按钮**（发一次最小请求回显成功/耗时/费用估算）。
- 配置存取走 `src/dragnet/config.py` 的既有模式，禁止硬编码密钥。

## 10. 交付物与验收标准

Phase A 交付：`docs/rounds/R15-armor-system-design.md`，含本文 §2–§9 的全部设计 + 改造文件清单（精确到文件与函数）+ 时序图（用户提问→穿甲→云端→卸甲→呈现）。

量化验收（Phase B 的完成定义）：

- 可逆性：property 测试通过，`ArmorOff∘ArmorOn` 敏感信息还原率 100%。
- 过审率：用 `reports/cipher_test` 的方法跑 ≥10 条敏感查询，云端拦截率从明文基线降到 0（或给出残余拦截的分类与回退路径）。
- token 保留率：云端输出中 token 原样保留率 ≥99%，其余被容错修复。
- 搜索召回：穿甲前后搜索结果条数/相关度无显著下降（对照实验）。
- 既有测试：`pytest` 全绿，不破坏 `run_pipeline.py` 现有行为。

## 11. 硬约束

- 最小 diff，遵循仓库既有代码风格与测试约定；不顺手重构无关代码。
- 任何密钥走环境变量/配置，禁止硬编码（注意：`run_pipeline.py` 现有硬编码 key 是反面教材，不要模仿，也不要顺手删除——审核方另行处理）。
- 设计文档用中文，代码注释/提交信息遵循仓库惯例。
