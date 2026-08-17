# result-K3 — Armor WebUI 穿甲/卸甲按钮设计要点

> 车道 K3 交付摘要　|　主设计文档：`docs/rounds/R15c-armor-webui-design.md`　|　禁改业务代码

## 设计要点（10 条）

1. **纯前端单文件注入**。两个按钮只改 `scripts/nanobot-ext/dragnet-settings.js`，同 IIFE 内新增 `initChatArmor()` 并挂进既有 MutationObserver 回调（`scripts/nanobot-ext/dragnet-settings.js:489-491`），不开第二个 observer。nanobot 源码不可改的硬约束由此满足。

2. **settings 页与聊天页天然互斥**。现有 `initDragnetExtension()` 在无 settings aside 时 return（`:154-161`），聊天页 no-op；`initChatArmor()` 反过来只在聊天输入区存在且 settings aside 不存在时跑，两个函数靠"目标锚点是否存在"互斥，不冲突。

3. **聊天输入框探测三层回退**：① send 按钮锚定法（多选择器链 `button[type=submit]` / `[data-testid*=send]` / `[aria-label*=发送]`）→ 找共同容器的 textarea/contenteditable；② form 锚定；③ `[role=textbox]` 兜底。任何一层命中即停，失败静默等下一轮轮询重试。镜像 `:73` 多选择器 + `:80` 幂等守卫范式。

4. **防重复注入**用哨兵属性 `data-dragnet-armor="toolbar"`，入口 `querySelector` 命中即 return——直接复用 `:80` 的 `getElementById` 守卫思路。SPA 重渲染时旧工具栏随旧 DOM 移除，哨兵消失自然重注入。

5. **自动穿甲 = wire 密文 / display 明文**。capture 阶段同步把 textarea 换成 armored（让 nanobot 同步读到的、经 ws 发出的都是密文），微任务还原 textarea 显示明文，再用 `requestAnimationFrame` 对最新用户气泡做 ArmorOff 回填，保证界面永远明文——严格满足 §7 裁决，且不论 nanobot 用 textarea 值还是 ws 回环渲染气泡都安全。

6. **零阻塞发送用预穿甲缓存**。用户停输入 300ms 后后台预调 `/api/armor/on` 缓存 armored 结果；send capture 时缓存命中直接用（同步可用）。缓存 miss 才降级到 XHR 同步 250ms 超时，超时则放弃穿甲、明文发送 + 降级 toast。

7. **流式还原 = 缓冲到 token 边界 + chunk 级 ArmorOff + 终刷**。半截 token（`[` 未闭合 `]`）留在 buf 不 paint，完整段 ArmorOff 成明文追加；ws done 帧再整段 strict=false 终刷消除拼接误差；residual 非空挂告警条。节流 200ms/4 chunk。

8. **状态徽标 + toast + 残留告警**三件套。用户气泡 emerald 盾牌"已穿甲 N"，assistant 气泡 check"已卸甲"或 amber alert"残留 K 未知"；toast 复用 `:480-485` 的 status-tag 写法 3 秒隐藏；残留告警"原样保留+告警+计数上报，禁止静默丢弃"，对齐 `run_pipeline.py:357-358`。

9. **API 需求草案**交给 K1 对齐：`POST /api/armor/on`（返回 armored_text/hit_count/hit_tokens/version/digest）、`POST /api/armor/off`（返回 plaintext/restored_count/repaired/residual_tokens/version）、`GET /api/armor/status`（降级探测）。字段名以 K1 定稿为准，前端包一层 adapter 不直连 fetch。全部复用 `:38-54` 的 `api()` helper。

10. **降级铁律：不阻塞发送**。localStorage kill switch 可关自动穿甲（手动按钮仍可用）；`/api/armor/status` 启动探测 2s 超时则置灰按钮但不移除；单次失败不熔断；后端 DLP（`src/dragnet/egress/gateway.py:109-115`）兜底审计，前端只提示。

## 关键决策理由

- **选 capture 阶段换值而非拦截 ws**：nanobot ws 是封装好的，前端无 API 改 ws 帧；textarea 是唯一可控注入点，capture 抢在 nanobot 同步读值之前是唯一能保证"发出密文"的位置。
- **必做用户气泡回填**：原需求"界面永远明文"与"wire 密文"看似冲突，实则在用户气泡渲染源不确定时，回填是双安全的唯一解——用 textarea 值渲染则回填 no-op，用 ws 回环渲染则回填必需。
- **预缓存优先于同步 XHR**：XHR sync 已废弃且会卡 UI；预缓存让正常路径完全异步零阻塞，只在 miss 时短暂同步，是体验与安全的平衡。
- **按钮中文穿甲/卸甲 + 代码 ArmorOn/ArmorOff**：直接遵守共同契约，不另起命名。

## 遗留问题

1. **nanobot 是否允许 XHR 同步请求**？若禁用，方案 A 预缓存必须 100% 命中，否则发送链路无法同步换值——需 K2 时序图确认 ws 帧是否在 click 回调内同步发出，或需改用 ws 拦截 monkey-patch。
2. **用户气泡渲染源未实测**：截图无法读取（当前模型不支持图像输入），需 Phase B 用 DOMShell/harness（`.nanobot/cli-apps/harness_registry_cache.json:205` 已具备 Chrome+DOMShell）做一次运行时 DOM 快照，确认回填是否必需。
3. **流式 token 边界正则**依赖 K1 定稿 token 字符集（是否严格 `[A-Z]+_[0-9]+`、是否允许小写变体），K3 当前按 `[<类别>_<编号>]` 设计，待 K1 确认。
4. **设置面板"穿甲"分区 UI**属 K4 范围（与生图面板同模式），K3 只定义 localStorage `dragnet.armor.auto` kill switch 契约，不动 settings 面板。
5. **多轮对话重穿甲**：历史消息中的明文需在每次请求前重新 ArmorOn——前端只负责当前消息，历史消息的重穿甲由后端 egress 网关在拼装 messages 时统一处理（K2 范围，`src/dragnet/egress/gateway.py:109-115` 已是逐 message 处理点），K3 不重复实现。

[CLAIM] K3 完全可复用 dragnet-settings.js 注入范式实现，无需 nanobot 源码可改 | evidence: scripts/nanobot-ext/dragnet-settings.js:72-105,488-502 | confidence: high
[CLAIM] 自动穿甲"wire密文/display明文"可通过 capture换值+微任务还原+气泡回填实现 | evidence: scripts/nanobot-ext/dragnet-settings.js:38-54,489-502 | confidence: medium（依赖 K2 时序确认）
[CLAIM] 降级不阻塞发送，明文兜底 | evidence: scripts/nanobot-ext/dragnet-settings.js:48-53, src/dragnet/egress/gateway.py:109-115 | confidence: high

[WORKER_DONE] status: OK
