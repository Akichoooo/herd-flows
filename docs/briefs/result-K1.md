# result-K1 — Armor 核心引擎 + 词表设计总结

> 车道 K1 ｜ 交付：`docs/rounds/R15a-armor-core-design.md` ｜ 阶段 Phase A（只设计，未改业务代码）

## 设计要点

1. **信任边界落位精确到行**：ArmorOn 落在 `egress/gateway.py:85 complete()` 出口（`:109-115` DLP 之后、`sent_bytes` 之前），ArmorOff 落在入口（`:164` content 取出后）。本地 DB/Trawler/磁盘永远明文区。
2. **新建 `src/dragnet/armor/` 包**：engine/wordlist/normalize/contract/audit/hooks 六文件 + 可选 `_ac.py`。类签名写到可直接照写：`Armor.on()->ArmorResult`、`Armor.off()->ArmorOffResult`、`StreamingRestorer.feed()/flush()`。
3. **词表 = YAML 明文源 + Fernet 加密落盘**：schema 含 token/category/primary/variants/enabled/note；变体覆盖简/繁/拼音/谐音/英文；密钥走 `DRAGNET_ARMOR_WORDLIST_KEY` 环境变量（沿用 `config.py` fail-closed）；gitignore；版本化 + 热更新（copy-on-write 整体替换）+ 回滚。
4. **ArmorOn 用 Aho-Corasick 多模式最长优先**：替代 `run_pipeline.py` 的正则交替（词表上千条时正则回溯失控）。需新增 `pyahocorasick` 依赖，纯 Python fallback 备选。
5. **不做上下文感知/模糊匹配**：边界编解码器要 100% 可逆，模糊匹配引入不可逆风险；语义锚定交给 token 契约段（组3 模式，`contract.py` 自动同步）。
6. **ArmorOff 100% 可逆设计**：词表双向映射 + 容错修复（大小写/全角括号/多余空格，`normalize_token_form`）+ 未知 token 原样保留+告警+计数（不静默丢弃）。
7. **流式卸甲 StreamingRestorer**：只看 `[`/`]` 边界缓冲，闭合后统一容错归一化，解耦缓冲与容错；解决 nanobot 聊天 chunk 切断 token 问题。
8. **多轮重穿甲**：历史消息一律存明文，每轮请求前在 `complete()` 内对全部 messages（含历史 assistant）统一 ArmorOn；system 每轮带契约段。
9. **审计复用 `contracts.audit.AuditEvent` + `TraceContext`**，与 egress 同 trace；日志只记 token/命中数/版本，不记主词条明文（ARCHITECTURE.md:561）。
10. **测试计划**：property 可逆性（`tests/property/test_armor_property.py`，hypothesis，语义级断言）+ 4 组过审对照复测（沿用 `cipher_test`）+ 单元/契约测试。

## 关键决策及理由

- **AC 而非正则**：`run_pipeline.py:42` 正则交替 + `sorted(-len)` 在 ~20 条尚可，但规格书明示上千条后行为不可控；AC 是 O(n) 且天然最长优先。
- **不做模糊匹配**：100% 可逆是硬约束，模糊匹配的判据不确定性会破坏可逆性；变体枚举已覆盖实际歧义。
- **Fernet 加密**：`cryptography` 已在依赖，认证加密防篡改、fail-closed，小文件无需手管 nonce；不选 AES-GCM 因静态小文件无收益且易错。
- **DLP 在前 ArmorOn 在后**：DLP 命中物（凭证）不应再被 Armor 扫描，Armor token 不触发 DLP 模式，职责互补不冲突。
- **不复用 `prompt_sanitizer.restore`**：其用自然语言别名（"某前总理"）还原，不可逆，与 Armor 目标冲突；当前无任何代码调用它（grep 验证），仅迁移其 `SENSITIVE_PAIRS` 明文条目为 Armor 词表 seed。
- **100% 可逆 vs ARCHITECTURE:106"不声称绝对100%"**：设计目标 100%（语义级断言），未知 token 是可观测降级而非丢失，调和二者。

## 遗留问题

- **R1**：`pyahocorasick` Windows wheel 可用性待 Phase B 验证；不可用则 fallback 纯 Python `_ac.py`。
- **R2**：模型把 token 拆词/改类别（如 `[PERS K1]`、`[PERSONS_K1]`）超出容错范围，进未知 token 路径；需靠契约段强制 + 上线后统计真实发生率。
- **流式落位**：K1 只给 `StreamingRestorer` 能力与签名，实际接入 `voice/gateway.py` 由 K3 完成。
- **MCP server 注册 / HTTP 路由**：K1 只定签名，落地在 K2（server.py）/K3（WebUI 后端）。
- **词表初版内容**：设计给 schema 与示例条目，真实词表条目（政治人物/事件全集）需业务方在 Phase B 前提供并加密入库。
