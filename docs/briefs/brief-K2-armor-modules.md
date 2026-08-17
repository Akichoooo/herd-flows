# Brief K2：三模块接入 + 全链路数据流 — 设计

你是 GLM worker，在 Dragnet 仓库根目录一次性执行。只出设计，禁止改业务代码/测试/配置，禁止 git 操作。

## 先读（全部真正读完再动笔）

1. `docs/subclaw-briefs/brief-armor-system-v1.md` — 总规格书
2. `run_pipeline.py` — 现有四阶段链路（搜索→加密→生成→解密），Gathering 产品化的原型
3. `src/dragnet/mcp/server.py`、`src/dragnet/mcp/spotter.py`、`src/dragnet/mcp/logbook.py`、`src/dragnet/mcp/compass.py`
4. `src/dragnet/research/`（workflow.py、registry.py、store.py、auditor.py）— Gathering 工作流的落位处
5. `src/dragnet/enroll/service.py`、`src/dragnet/enroll/api.py` — Face 模块外部 API 接入层（预留 armor 钩子的位置）

## 共同架构契约（必须遵守，不得另起方案）

- 信任边界：本地组件（Trawler-mcp、本地 DB、Dify、MCP Server、磁盘）= 明文区；云端 LLM API 请求/响应 = 密文区。ArmorOn 只在发往云端 LLM 的出口执行，ArmorOff 只在云端响应入口执行。**搜索关键词、本地库存储永远明文**——"档案穿甲后入库"已被否决，本地库一律明文，只有出站喂云端模型才穿甲。
- 命名：代码 `ArmorOn()` / `ArmorOff()`。
- 服务接口约定（K1 车道负责实现设计，你按此引用）：
  - MCP 工具：`armor_on(text)` / `armor_off(text)`，注册进 `src/dragnet/mcp/server.py`
  - 本地 HTTP API：`POST /api/armor/on`、`POST /api/armor/off`
- token 占位格式 `[<类别>_<编号>]`（如 `[PERS_K1]`），最终格式以 K1 为准。

## 你的设计范围（规格书 §6 + §9 时序图）

1. **Face**：本地识别不穿甲；外部识图 API 接入层的 armor 出入站钩子设计（接口 + 默认直通实现），改造量保持最小。
2. **Profile**：库存明文前提下的唯一改造点——档案内容送入云端 LLM 的出口统一走 ArmorOn；指出具体挂接文件与函数。
3. **Gathering（重点）**：把 run_pipeline.py 四阶段产品化为 `src/dragnet/research/` 下的正式工作流：
   - YAML 工作流定义 schema（步骤、数据源、技能匹配、输出模板、是否穿甲），引擎按 schema 执行；
   - 系统 prompt 的 token 契约模板（cipher_test 组3模式：定义 token 含义 + 强制原样保留），词表变更时自动同步契约段；
   - 采集结果明文落盘位置与档案模块的读取关系；
   - 被云端拦截时的回退路由（转到本地/Dify 链路，接口占位即可，Dify 细节是 K4 的活）。
4. **全链路时序图**：mermaid，用户提问 → （云端出口）ArmorOn → 云端 LLM → ArmorOff → 明文呈现；以及 Gathering 完整链路（明文搜索 → 素材 ArmorOn → 云端生成 → ArmorOff → 落盘/呈现）。每条消息标注处于明文区还是密文区。
5. **改造文件清单**：精确到文件与函数，写入前必须验证真实存在。

## 交付物（只许写这两个文件）

1. `docs/rounds/R15b-armor-modules-design.md` — 上述全部内容，中文。
2. `docs/subclaw-briefs/result-K2.md` — 5-10 条设计要点 + 关键决策理由 + 遗留问题。

## 硬性要求

- 引用的每个已有文件/函数/类名必须先用 Read/Grep 验证存在，禁止编造路径。
- 时序图必须与实际代码结构对得上（组件名用真实模块名）。
- 末尾输出：`[WORKER_DONE] status: OK|PARTIAL|FAIL`；关键结论用 `[CLAIM] 结论 | evidence: 文件:行 | confidence: high|medium|low` 标注。
