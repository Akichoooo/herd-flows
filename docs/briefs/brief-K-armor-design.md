# Brief K：Armor 穿卸甲系统 — Phase A 设计文档

你是一个 claude code worker（模型 glm-5.2），运行在 Dragnet 仓库根目录，一次性非交互执行。

## 任务

**先完整阅读 `docs/subclaw-briefs/brief-armor-system-v1.md`，它是本任务的完整规格书，逐节遵循。**
本 brief 只执行其中的 **Phase A**：产出设计文档。**禁止修改任何业务代码、测试、配置。**

## 交付物（只允许写这两个文件）

1. `docs/rounds/R15-armor-system-design.md` — 设计文档，覆盖规格书 §2–§9 全部内容：
   信任边界架构、词表数据模型与版本管理、ArmorOn/ArmorOff 引擎算法、三模块（Face/Profile/Gathering）改造点、
   WebUI 穿甲/卸甲按钮交互、Trawler 登录弹窗方案对比与推荐、Dify 回退链路接口、生图配置修复、
   完整链路时序图（mermaid）、**改造文件清单（精确到文件与函数）**、测试计划、风险清单。中文撰写。
2. `docs/subclaw-briefs/result-K.md` — 简短总结：设计要点 5-10 条、关键决策及理由、遗留问题。

## 硬性要求

- **信任边界不能画错**（规格书 §2）：Armor 只发生在云端 LLM API 出口/入口；Trawler 搜索、本地 DB 永远是明文区。
  设计文档中每一条数据流都要能指出此时处于明文区还是密文区。
- **文件清单必须真实**：清单里写的每个文件、每个函数/类名，写进文档前必须先用 Read/Grep 验证存在。
  不允许凭印象编造路径。规格书 §1 的必读文件要全部真正读完。
- 关键设计决策（如 token 格式、匹配算法、存储位置）必须在文档中给出**理由和取舍**，不许只列方案不给结论。
- 时间预算有限：若临近超时，优先保证 §2 架构、§4/§5 引擎、§6 Gathering 三节完整，
  其余可精简，并在 result-K.md 标注未完成部分。

## 证据协议（必须输出，纯文本行）

- `[PROGRESS] <当前步骤>` — 每完成一步输出一行，全程 ≤50 行
- `[EVIDENCE] <file>:<line> - <fact>` — 关键事实给出处
- `[CLAIM] <结论> | evidence: <file:line 列表> | confidence: high|medium|low`
- `[RISK] <不确定或需验证的点>`
- `[ASK_ORCHESTRATOR] <具体问题>` — 仅在真正被阻塞时
- `[WORKER_DONE] status: OK|PARTIAL|FAIL` — 最后一行

最终回复是 ≤2K token 的简明证据包，不是过程转录；设计细节写进交付文件，回复里只引用路径。
不要 git commit，不要 git 任何变更操作。
