# Brief K3：WebUI 穿甲/卸甲按钮 — 设计

你是 GLM worker，在 Dragnet 仓库根目录一次性执行。只出设计，禁止改业务代码/测试/配置，禁止 git 操作。

## 先读（全部真正读完再动笔）

1. `docs/subclaw-briefs/brief-armor-system-v1.md` — 总规格书（§7 是你的范围）
2. `scripts/nanobot-ext/dragnet-settings.js`（全文 503 行）— WebUI DOM 注入扩展的既有模式，按钮要复用这套机制
3. `src/dragnet/mcp/server.py` — 后端工具注册方式（armor API 的宿主）
4. `docs/prototypes/`、`docs/screenshots/` 里与聊天界面相关的素材（如存在）

## 共同架构契约（必须遵守，不得另起方案）

- 信任边界：ArmorOn/ArmorOff 的计算全部在后端（词表不出后端），前端只调 API。
- 命名：按钮中文 **穿甲** / **卸甲**，hover 显示 "穿甲 ArmorOn" / "卸甲 ArmorOff"；代码 `ArmorOn()` / `ArmorOff()`。
- 服务接口约定（K1 车道负责后端实现设计，你按此调用）：
  - 本地 HTTP API：`POST /api/armor/on`、`POST /api/armor/off`，请求/响应 JSON 结构你可以提需求草案，但标注"以 K1 定稿为准"。
- token 占位格式 `[<类别>_<编号>]`（如 `[PERS_K1]`）。
- 已定稿的交互裁决（解决原需求自相矛盾，不许翻案）：
  - 默认**自动穿甲**：发送时透明 ArmorOn，聊天界面永远显示明文；
  - 按钮是**手动预览/调试**：点"穿甲"在输入框预览替换结果（可一键还原）；点"卸甲"对选中/最新一条回复手动触发还原；
  - 状态指示：当前消息是否已穿甲（图标/颜色）+ 穿甲命中词条数 toast。

## 你的设计范围

1. **注入实现**：在聊天输入框发送键旁注入两个按钮的具体方案——复用 dragnet-settings.js 的 DOM 观察/注入模式，给出选择器策略、注入时机、防重复注入、与现有 settings 面板代码的共存方式。nanobot 聊天页 DOM 结构与 settings 页不同，设计中必须包含"如何探测聊天输入框"的健壮方案（多选择器回退）。
2. **交互细节**：自动穿甲的拦截点（发送前拦截 → 调 API → 替换后发出，界面显示明文）；流式回复中 token 的实时还原表现（允许先显 token 后整段刷新，给出具体方案）；预览模式的状态机（明文态/预览态/已穿甲发送态）。
3. **状态与反馈**：穿甲状态图标、命中词条数 toast、卸甲失败（残留未知 token）的提示样式。
4. **API 需求草案**：前端需要的请求/响应字段清单（含命中计数、版本号），交给 K1 对齐。
5. **降级**：armor API 不可用时的行为（不阻塞发送，明确提示）。

## 交付物（只许写这两个文件）

1. `docs/rounds/R15c-armor-webui-design.md` — 上述全部内容，中文，关键交互给状态图或流程图（mermaid）。
2. `docs/subclaw-briefs/result-K3.md` — 5-10 条设计要点 + 关键决策理由 + 遗留问题。

## 硬性要求

- 引用 dragnet-settings.js 的既有函数/模式时给出行号，必须真实。
- 不许假设 nanobot 源码可改——一切通过注入扩展实现。
- 末尾输出：`[WORKER_DONE] status: OK|PARTIAL|FAIL`；关键结论用 `[CLAIM] 结论 | evidence: 文件:行 | confidence: high|medium|low` 标注。
