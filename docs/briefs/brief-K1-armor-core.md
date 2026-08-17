# Brief K1：Armor 核心引擎 + 词表管理 — 设计

你是 GLM worker，在 Dragnet 仓库根目录一次性执行。只出设计，禁止改业务代码/测试/配置，禁止 git 操作。

## 先读（全部真正读完再动笔）

1. `docs/subclaw-briefs/brief-armor-system-v1.md` — 总规格书
2. `run_pipeline.py` — 现有 cipher 参考实现
3. `reports/cipher_test_20260813_160604.json` — 过审对照实验数据
4. `src/dragnet/util/prompt_sanitizer.py`、`src/dragnet/egress/dlp.py`、`src/dragnet/egress/gateway.py` — Armor 的落位层
5. `src/dragnet/config.py` — 配置管理模式

## 共同架构契约（必须遵守，不得另起方案）

- 信任边界：本地组件（Trawler-mcp、本地 DB、Dify、MCP Server、磁盘）= 明文区；云端 LLM API 请求/响应 = 密文区。ArmorOn 只在发往云端 LLM 的出口执行，ArmorOff 只在云端响应入口执行。搜索关键词、本地库存储永远明文。
- 命名：代码 `ArmorOn()` / `ArmorOff()`；UI 按钮 穿甲/卸甲。
- 服务接口约定（其他车道也按此引用，你不能单方面改签名，只能提修订建议）：
  - MCP 工具：`armor_on(text)` / `armor_off(text)`
  - 本地 HTTP API：`POST /api/armor/on`、`POST /api/armor/off`
- token 占位格式 `[<类别>_<编号>]`（如 `[PERS_K1]`），你负责本格式定稿。
- 词表是最高敏感资产：加密存放、gitignore、禁日志、版本化。

## 你的设计范围（规格书 §3 §4 §5 + 落位）

1. **模块结构**：`src/dragnet/armor/` 包设计（engine/wordlist/audit 等文件划分、类与函数签名、与 egress/dlp 的挂接点）。
2. **词表**：JSON/YAML schema（token、category、主词条、变体列表、启用状态、版本、备注）；变体覆盖简体/繁体/拼音/谐音/英文名；加密存储方案（给出具体算法与密钥来源）；版本管理与热更新机制；增删查与泄露自检接口。
3. **ArmorOn**：Aho-Corasick 多模式串最长优先匹配（给出选型理由，对比正则交替）；归一化规则（大小写/全半角）；是否需要上下文感知/模糊匹配——给结论和理由，不要两个都做；输出附带替换计数与命中词条 ID。
4. **ArmorOff**：100% 可逆的设计保证；模型改写 token 的容错修复（大小写/全角括号/多余空格）；流式输出的 token 边界缓冲方案；未知 token 告警策略；审计记录结构。
5. **多轮对话重穿甲**：历史消息的处理时机。
6. **测试计划**：property-based 可逆性测试（仓库有 tests/property/ + hypothesis）、过审率复测方法（沿用 cipher_test 的 4 组对照法）。

## 交付物（只许写这两个文件）

1. `docs/rounds/R15a-armor-core-design.md` — 上述全部内容，中文，关键决策给理由。
2. `docs/subclaw-briefs/result-K1.md` — 5-10 条设计要点 + 关键决策理由 + 遗留问题。

## 硬性要求

- 文档中引用的每个已有文件/函数/类名，写入前必须用 Read/Grep 验证存在，禁止编造路径。
- 接口签名写到可直接照写的程度（参数、返回类型、异常）。
- 末尾输出：`[WORKER_DONE] status: OK|PARTIAL|FAIL`；关键结论用 `[CLAIM] 结论 | evidence: 文件:行 | confidence: high|medium|low` 标注。
