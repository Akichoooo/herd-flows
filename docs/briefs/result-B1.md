# result-B1 — Armor 引擎包 + Armor Proxy 实施总结

> 车道 B1（K1 落地）｜ 阶段 Phase B ｜ 严格按 R15a 设计实施，未碰 egress/gateway.py、research/**、dragnet-settings.js、enroll/**、run_pipeline.py

## 交付清单

### 新建文件

| 文件 | 内容 |
|---|---|
| `src/dragnet/armor/__init__.py` | 包导出 |
| `src/dragnet/armor/normalize.py` | NFKC+casefold 归一化、偏移对齐（ArmorOn 不破坏非敏感文本） |
| `src/dragnet/armor/_ac.py` | 纯 Python Aho-Corasick 自动机（零外部依赖 fallback，规避 pyahocorasick Windows wheel 风险） |
| `src/dragnet/armor/wordlist.py` | WordEntry/WordList/WordlistStore（Fernet 加密、版本化、copy-on-write 热更新、回滚、泄露自检、build_from_env fail-closed） |
| `src/dragnet/armor/contract.py` | TokenContractBuilder（组3 契约段，全系统唯一实现） |
| `src/dragnet/armor/audit.py` | ArmorAuditRecord→AuditEvent（复用 contracts.audit，只记 token 不记明文） |
| `src/dragnet/armor/engine.py` | Armor.on（AC 最长非重叠）/Armor.off（容错归一化+未知保留告警）/StreamingRestorer（边界缓冲） |
| `src/dragnet/armor/proxy.py` | FastAPI Armor Proxy（:18791，OpenAI 兼容 + SSE 流式 + /api/armor/* + /api/armor/reload） |
| `scripts/armor_proxy.py` | uvicorn 启动脚本 |
| `scripts/armor_wordlist_cli.py` | generate-key/seed/add/list/leak-check（ast 解析 _CIPHER_PAIRS，避免 requests 依赖） |
| `tests/unit/test_armor_engine.py` | 最长优先/归一化/容错/流式/非敏感保留 |
| `tests/unit/test_armor_wordlist.py` | Fernet 往返/版本回滚/泄露自检/fail-closed/digest |
| `tests/property/test_armor_property.py` | hypothesis 可逆性（无未知 token + 实体保留 + 流式≡批量） |
| `.nanobot/config.json.pre-armor.bak` | 改前备份 |

### 修改文件（最小 diff）

| 文件 | 改动 |
|---|---|
| `src/dragnet/mcp/server.py` | import Armor/WordlistStore；`__init__` 加 `_armor` 懒加载字段；tools/list 注册 armor_on/armor_off；_call_tool 加两分发分支 + `_get_armor()` |
| `src/dragnet/util/prompt_sanitizer.py` | 内部函数 `_r(m)` 补 `re.Match[str] -> str` 注解（既有 mypy 债，1 行无行为变化，否则门禁 mypy 无法全绿） |
| `.env.example` | 追加 DRAGNET_ARMOR_WORDLIST_KEY/DIR + proxy 上游两项 |
| `.gitignore` | 追加 docs/wordlists/*.enc 等 |
| `.nanobot/config.json` | providers.custom.apiBase → http://127.0.0.1:18791/v1（备份在前） |

## 门禁结果（全绿）

```
ruff format src tests          → 125 files unchanged (3 微调)
ruff check src tests           → All checks passed!
mypy                           → Success: no issues found in 84 source files
pytest -m "unit or contract or property or security"
                               → 424 passed, 73 deselected in 7.92s
```

## 冒烟结果（mock 上游 :18792 → proxy :18791）

```
GET  /api/armor/status   → {"ok":true,"version":"1.0.0","digest":"3057442299cef544","loaded_count":5}
POST /api/armor/on       {"text":"朱镕基逝世"}
                         → {"armored":"[PERS_K1][EVENT_E1]","count":2,"hits":["[PERS_K1]","[EVENT_E1]"],"version":"1.0.0"}
POST /api/armor/off      {"text":"[PERS_K1][EVENT_E1]"}
                         → {"text":"朱镕基逝世","restored":2,"unknown":[],"version":"1.0.0"}
POST /v1/chat/completions {"messages":[{"role":"user","content":"朱镕基逝世"}]}
                         → {"choices":[{"message":{"content":"关于朱镕基的逝世报告"}}]}
```

端到端验证：proxy 收明文 → ArmorOn 全 messages + 注入契约段 → 转发上游 → 上游返回含 token 响应 → ArmorOff 还原 → 明文返回。穿甲/卸甲/转发链路全通。

> 注：Windows curl 的 `-d` 默认按 GBK 编码中文 body，须用 `--data-binary @file`（Git Bash printf 写 UTF-8）规避；生产环境 nanobot 走 httpx 直连代理无此问题。

## 关键决策

1. **AC 用纯 Python `_ac.py` 而非引入 pyahocorasick**：评审 §四 P2 标注 wheel 可用性未验证；零外部依赖 fallback 更稳，词表数千条性能可接受，接口解耦可日后切换 C 扩展。
2. **ArmorOn 用偏移对齐而非全局归一化**：NFKC 会改变文本长度（全角→半角），若直接在归一化文本上替换会破坏非敏感区，ArmorOff 无法 100% 可逆。`build_alignment` 维护"归一化字符→原文字符区间"映射，只替换敏感区间。
3. **ArmorOff 用正则扫 `[...]`/`［...］` 候选 + `normalize_token_form` 容错**：处理模型改写的大小写/全角括号/多余空格；未知 token 原样保留+告警+计数，不静默丢弃。
4. **StreamingRestorer 只看 `[`/`]` 边界缓冲**：闭合后统一容错归一化，解耦缓冲与归一化，规避 chunk 切断 token 时的误判。
5. **Armor Proxy 是 P0 裁决的补设**：nanobot chat 原走 freetokenfaucet 直连不经 egress gateway；改 apiBase 指代理后，用户输入/MCP 工具结果/历史消息全部自动穿甲，一处配置覆盖整个聊天链路。
6. **词表 fail-closed**：DRAGNET_ARMOR_WORDLIST_KEY 缺失则 build_from_env 抛 RuntimeError（dev 也强制）。
7. **seed 迁移用 ast 解析 _CIPHER_PAIRS**：run_pipeline.py 顶部 `import requests`（未装），整模块 import 会失败；ast 提取字面量绕过。组合词（如"朱镕基逝世"跨实体）不入词表，留给多 token 序列匹配。
8. **prompt_sanitizer 只补注解不碰逻辑**：其 restore 用自然语言别名不可逆，与 Armor 目标冲突；R15a 已决定不复用其实现，本次仅补 mypy 注解清债。

## 遗留问题

- **R1**：seed 的 primary 选择用 `min(forms, key=len)`，RISK_R1 取到"涉政涉稳"而非语义更清晰的"风险研判"；需业务方在 Phase B 后复核 primary 映射（不影响可逆性，只影响卸甲还原词的语义偏好）。
- **R2**：真实上游（freetokenfaucet/sensenova）可达性未测（冒烟用本地 mock）；nanobot config.json 已改指代理，需在有真实上游 key 时做一次端到端聊天验证。
- **R3**：`fallbackModels`（deepseek-v4flash/glm-5-2/sensenova-6-7-flash-lite）改 apiBase 后自动走代理（评审 §二.5 满足"指向代理"）；若上游不支持这些模型名，fallback 会失败——取决于上游能力，需运行时验证。
- **R4**：MCP server 的 armor_on/armor_off 工具需 DRAGNET_ARMOR_WORDLIST_KEY 环境变量（懒加载，缺失则该工具抛错，不影响其他工具）；冒烟未测 MCP stdio 路径（需启动 mcp server 进程）。
- **R5**：词表初版仅 5 条 seed；真实业务词表（政治人物/事件全集）需业务方提供并加密入库。

> [CLAIM] ArmorOn/ArmorOff 100% 可逆在 property 测试验证（unknown_tokens==()，restored>=replaced） | evidence: tests/property/test_armor_property.py; 冒烟 off 还原 | confidence: high
> [CLAIM] Armor Proxy 端到端穿甲+转发+卸甲链路通 | evidence: 冒烟 /v1/chat 输出"关于朱镕基的逝世报告" | confidence: high
> [CLAIM] 门禁全绿（ruff/mypy/pytest 424） | evidence: 门禁输出 | confidence: high
> [RISK] 真实上游可达性与 fallback 模型兼容性待运行时验证（R2/R3）
```

[WORKER_DONE] status: OK
