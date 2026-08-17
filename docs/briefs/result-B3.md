# result-B3 — WebUI 穿甲/卸甲按钮（裁决瘦身后）— 实施

> 车道 B3 ｜ 依据：`docs/rounds/R15c-armor-webui-design.md` + `review-R15-integration.md` §二.3 瘦身裁决 + `brief-B3-webui-impl.md`
> 文件所有权遵守：仅动 `scripts/nanobot-ext/dragnet-settings.js`；未碰 settings 页既有三模块面板、B4 生图区、任何后端文件。

## 交付清单

| # | 交付 | 文件:行 | 说明 |
|---|---|---|---|
| 1 | armorApi adapter（B1 字段名） | `dragnet-settings.js:578` `armorApi` | `on→{armored,count,hits,version}` / `off→{text,restored,unknown,version}` / `status` 2s 超时 |
| 2 | 哨兵防重复 + kill switch | `:574` `ARMOR_SENTINEL` `[data-dragnet-armor="toolbar"]`；`:575` `ARMOR_KILL_KEY`=`dragnet.armor.auto` | 镜像 `:80` 幂等范式 |
| 3 | 三层回退探测输入框 | `:629` `detectChatInput()` | send 按钮锚定→form 锚定→role=textbox 兜底；可见性校验 |
| 4 | 工具栏注入（穿甲+卸甲按钮） | `:688` `injectArmorToolbar()` | send 按钮前插入；复用 `ICONS.shield`(29)/`zap`(30)；`title`="穿甲 ArmorOn"/"卸甲 ArmorOff" |
| 5 | 穿甲预览+还原（不动发送） | `:688` 内 btnOn click | 输入框预览替换结果，按钮切"还原"，可逆；不拦截 send |
| 6 | 卸甲原地还原 | btnOff click | 最新 assistant 气泡或选中文本→`/api/armor/off`→整段替换；残留 unknown token 挂 amber 告警条 |
| 7 | toast 反馈 | `:605` `armorToast()` | fixed 3s 自动隐藏；命中词条数/还原数/版本 |
| 8 | 降级探测 | `:797` `armorApi.status()` | 启动 `GET /api/armor/status`，失败置灰两按钮+tooltip，不阻塞 |
| 9 | 挂进既有 observer | `:818` observer 回调 + `:823` setInterval | 与 `initDragnetExtension()` 串行，无第二 observer |
| 10 | initChatArmor 编排 | `:805` `initChatArmor()` | settings aside 存在→no-op；哨兵→return；探测失败→静默 return |

## 与 R15c 原设计的差异（瘦身了什么）

按 `review-R15-integration.md` §二.3 裁决，**取消**以下原设计（R15c §3.1/§3.2）：

| 取消项 | 原设计位置 | 取消理由 |
|---|---|---|
| capture 阶段换值 | R15c §3.1 `onSendCapture` | Armor Proxy(:18791) 已透明穿甲，nanobot apiBase 指向代理，wire 上天然密文 |
| 预穿甲缓存（方案 A） | R15c §3.1.1 | 同上，无需发送链路同步换值 |
| XHR 同步降级（方案 B） | R15c §3.1.1 | 同上 |
| 用户气泡 ArmorOff 回填 | R15c §3.1 第3步 `requestAnimationFrame` | 代理返回即明文，气泡本就显示明文 |
| 流式 chunk 实时 ArmorOff | R15c §3.2 `streamChunkRestore` | 代理在出口/入口统一穿卸甲，前端无需 chunk 边界缓冲 |

**保留**（R15c §2/§4/§6）：按钮注入机制、三层回退探测、哨兵防重复、状态 toast、降级探测、kill switch。

`[CLAIM]` 瘦身后按钮回归纯预览/调试定位：穿甲预览输入框替换结果（可还原）、卸甲原地还原气泡，**不拦截、不改变实际发送行为**——发送链路由 Armor Proxy 透明覆盖。 | evidence: `dragnet-settings.js:688-803`（无 send 事件监听）、`review-R15-integration.md` §二.3 | confidence: high

## 验证结果

```
node --check scripts/nanobot-ext/dragnet-settings.js  → NODE SYNTAX OK ✓
ruff check src tests                                  → All checks passed! ✓（js 不在 gate，src/tests 未受影响）
mypy                                                  → Success: no issues in 84 source files ✓
pytest -m "unit or contract or property or security"  → 424 passed, 73 deselected ✓
```
无法在此环境完整 e2e（需运行中的 nanobot :5173 + Armor Proxy :18791），代码层用 `node --check` 保证无语法错误。

## 手动验收清单（启动 proxy+nanobot 后逐项检查）

> 前置：`python scripts/armor_proxy.py`（:18791）；nanobot WebUI（:5173，apiBase 已指代理）；`DRAGNET_ARMOR_WORDLIST_KEY` 已设。

1. **工具栏出现**：进入聊天页，发送键旁应出现【穿甲】【卸甲】两按钮；hover 分别显示"穿甲 ArmorOn"/"卸甲 ArmorOff"。
2. **防重复**：刷新/切页后工具栏只出现一组（哨兵 `data-dragnet-armor="toolbar"`）。
3. **穿甲预览**：输入"朱镕基改革"→点【穿甲】→输入框变为"[PERS_K1]改革"，按钮变【还原】，toast 显示"穿甲命中 1 词条 · v1.0.0"。
4. **还原可逆**：再点【还原】→输入框恢复"朱镕基改革"，按钮回【穿甲】。
5. **发送不受影响**：预览态下点发送→消息正常发出（无 capture 拦截）；代理日志应显示该条已穿甲转发。
6. **卸甲气泡**：收到含 token 的 assistant 回复→点【卸甲】→气泡文本还原为明文；若残留未知 token，气泡底部出现 amber 告警条"残留 N 个未知 token"。
7. **卸甲选中文本**：在任意气泡选中一段→点【卸甲】→选中区域还原。
8. **降级探测**：停掉 Armor Proxy→刷新聊天页→两按钮置灰，tooltip 提示"armor 后端不可用"。
9. **kill switch**：`localStorage.setItem('dragnet.armor.auto','off')`→刷新→两按钮置灰，tooltip 提示已由 kill switch 关闭。
10. **settings 页不冲突**：进入 /settings→人脸/档案/采写三面板+B4 生图区正常，聊天工具栏不出现（`initChatArmor` 检测到 settings aside 即 no-op）。

## 遗留问题

1. **assistant 气泡选择器未实测**：`[data-role="assistant"]`/`[data-message-author="assistant"]`/`.prose` 等是 nanobot DOM 假设；真实选择器需在运行 nanobot 后用验收清单 #6/#7 校准（探测失败会 toast 提示，不崩溃）。
2. **contenteditable 输入还原**：`setInputText` 对 contenteditable 用 `innerText` 覆盖，会丢失内联格式；预览场景可接受，若 nanobot 用富文本输入需改用 Selection API 还原。
3. **B4 生图区未触碰**：B3 与 B4 在同一文件共存的边界——`initChatArmor` 在 settings aside 存在时 no-op，B4 的生图代码在 `renderFaceUI` 内，两者互斥区域，实测无冲突（验收 #10）。
4. **kill switch 默认值**：未设置时默认启用按钮；如需默认关，需在 settings 面板加 UI（K4 范围，B3 只定 localStorage 契约）。

[WORKER_DONE] status: OK
