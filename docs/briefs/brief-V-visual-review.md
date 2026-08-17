# Brief V：多模态视觉走查 — nanobot 扩展 UI

> 本任务指定多模态模型执行（sensenova-6.7-flash-lite，支持 image_url 内容块）。
> 你是 UI 审查员：逐张读取截图并给出结构化审查结论，不需要改任何代码。

## 待审截图（全部在 evidence/screenshots/ 下，用 Read 工具逐张读图）
1. `fix-verify-settings-page.png` — 设置页（应含"爬虫写文章""已移入设置"两个新分区项）
2. `verify-step1-sidebar.png` / `regression-r2-sidebar-patched.png` — 侧边栏
   （应有"人脸录入""图书馆"两个新条目带图标；"应用""技能"应不可见）
3. `verify-step2-face-panel.png` — 人脸录入面板
4. `verify-step3-library-panel.png` — 图书馆面板
5. `verify-step5-crawler-panel.png` / `verify-step5-crawler-panel-full.png` — 爬虫写文章面板
6. `fix-verify-test1-apps-page.png` — 原生应用页（对照参照）

## 审查维度（每张图逐项过）
1. **布局完整性**：要求的元素是否都在、位置是否符合描述；
2. **视觉一致性**：新元素与 nanobot 原生的配色/圆角/字号是否协调，有无明显"外挂感"；
3. **溢出与截断**：文字是否被截断、按钮是否超出容器、表格是否错位；
4. **可用性**：返回按钮/卡片层级是否清晰可辨；
5. **主题适配**：light 主题下对比度是否足够。

## 输出
写 `docs/subclaw-briefs/result-V.md`：
- 每张截图一节：通过项 + 问题项（严重度 P0 阻断/P1 建议/P2 吹毛求疵）；
- 末尾给总体结论：扩展 UI 是否可交付用户验收，最值得修的 3 件事。
不改任何代码，不跑测试，不 git commit。
