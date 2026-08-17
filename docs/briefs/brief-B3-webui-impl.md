# Brief B3：WebUI 穿甲/卸甲按钮（裁决瘦身后版本）— 实施

**前置：B1 已完成（`/api/armor/*` 可用）、B4 已完成（它先改过 dragnet-settings.js）。** 你是 GLM worker，在 Dragnet 仓库根目录一次性执行。本次是**实施**任务。禁止 git 任何操作。

## 先读

1. `docs/rounds/R15c-armor-webui-design.md` — 你的原始设计
2. `docs/subclaw-briefs/review-R15-integration.md` §二.3 —— **强制瘦身裁决**，覆盖原设计的以下部分：
   - ❌ 取消 capture 阶段换值、预穿甲缓存、XHR 同步降级（Armor Proxy 已在 `:18791` 透明穿甲，nanobot apiBase 已指向代理，wire 上天然密文）
   - ❌ 取消用户气泡 ArmorOff 回填（代理返回即明文）
   - ✅ 保留：按钮注入机制、三层回退探测、哨兵防重复、状态徽标/toast、降级探测、kill switch
3. `docs/subclaw-briefs/result-B1.md` — API 的最终字段名（以此为准，不以 R15c §5 草案为准）
4. `scripts/nanobot-ext/dragnet-settings.js` 全文（注意 B4 刚改过的生图区，别碰）

## 文件所有权

只许动 `scripts/nanobot-ext/dragnet-settings.js` 一个文件，且只新增聊天页 armor 工具栏代码（新 IIFE 内函数 `initChatArmor()`，挂进既有 observer）。**禁止碰**：settings 页既有三模块面板、B4 的生图区、任何后端文件。

## 交付内容

1. **聊天输入框工具栏**：发送键旁注入 **穿甲**（hover "穿甲 ArmorOn"）、**卸甲**（hover "卸甲 ArmorOff"）两按钮；三层回退探测输入框；`data-dragnet-armor="toolbar"` 哨兵防重复。
2. **按钮语义（预览/调试定位）**：
   - 穿甲：取输入框文本调 `POST /api/armor/on`，在输入框内预览替换结果（可再次点击/快捷键还原原文）——让用户能亲眼确认哪些词被换掉；不拦截、不改变实际发送行为
   - 卸甲：对最新一条 assistant 气泡（或选中文本）调 `POST /api/armor/off` 并原地还原
3. **状态与反馈**：命中词条数 toast（复用 `:480-485` status-tag 写法）；卸甲后残留未知 token 的 amber 告警条；localStorage `dragnet.armor.auto` kill switch 置灰按钮。
4. **降级**：启动时 `GET /api/armor/status`（2s 超时）探测，失败则按钮置灰 + tooltip 说明，不影响任何既有功能。
5. **API 调用**：走 `:38-54` 的 `api()` helper，外面包一层 `armorApi` adapter（字段名以 B1 定稿为准：`on → {armored, count, hits, version}`、`off → {text, restored, unknown, version}`、`status → {ok, version, digest, loaded_count}`）。

## 验证

无法在此环境完整 e2e（需运行中的 nanobot），交付一份**手动验收清单**（写进 result-B3.md）：启动 proxy+nanobot 后逐项检查的步骤与预期。代码层面用 node 语法检查（`node --check`）保证无语法错误。

## 收尾

写 `docs/subclaw-briefs/result-B3.md`：交付清单、与 R15c 原设计的差异说明（瘦身了哪些）、手动验收清单、遗留问题。
最后输出 `[WORKER_DONE] status: OK|PARTIAL|FAIL`，关键结论带 `[CLAIM] ... | evidence: 文件:行 | confidence: ...`。
