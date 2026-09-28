# 鸿蒙应用第十二次开发日志

## 项目信息

- **项目名称**：StudyStream / TimeCraft
- **开发日期**：2026-09-12
- **范围**：执行闭环 E1～E3 的最小实现，以及横屏专注执行界面
- **技术栈**：HarmonyOS NEXT / ArkTS / ArkUI（API 23+）

---

## 一、本轮目标

实现从已安排日程进入执行会话的最小闭环：

```text
点击已安排日程
→ 开始任务
→ 横屏白场淡入主题色执行页
→ 分步骤倒计时与切换
→ 结束后返回日历
```

仍遵循 `plan.md` 的产品边界：**计划时间到达不等于自动开始任务**。本轮在用户从日程详情确认“开始任务”后才切换横屏；前台到点提醒和系统后台提醒仍分别属于 R1 / R2，未提前实现。

## 二、新增执行数据域

新建 `entry/src/main/ets/models/ExecutionSession.ets`：

- 定义 `ExecutionSession`、`ExecutionStepRecord`、执行/步骤状态。
- `ExecutionStore` 使用独立、版本化的 Preferences 键 `execution_sessions_v1` 持久化。
- 开始时深拷贝 `ScheduledEvent` 的名称、颜色和步骤；之后编辑模板或日程不会改变执行快照。
- 支持开始、暂停、继续、完成当前步骤、跳过、回到上一步、后台恢复结算、放弃。
- 计时以 `remainingMs + runStartedAt` 计算；页面刷新不写 Preferences。
- `reconcile()` 只结算后台期间到期的当前步骤，并置为 `waiting-next`，不会偷偷消耗后续步骤。
- `EntryAbility.onCreate()` 已按 `Persistence → TaskStore → ScheduleStore → ExecutionStore` 顺序恢复数据。

## 三、新增横屏执行页

新建 `entry/src/main/ets/pages/ExecutionPage.ets`，并注册 `pages/ExecutionPage` 路由。

### 视觉和交互

- 进入时使用 `window.getLastWindow(...).setPreferredOrientation(window.Orientation.LANDSCAPE)` 请求横屏；离开时恢复竖屏。
- 页面先显示白底，再在 550ms 内过渡到任务包主题色。
- 正上方为全宽“章节”时间线：每段按计划时长分配宽度，标出各步骤名称和当前步骤。
- 画面中心偏上显示大号 `MM:SS` 倒计时，下方显示当前步骤及步骤序号。
- 两侧以 75% 白色透明度显示箭头和相邻步骤：左侧无前一步时显示“无”，最后一步右侧显示“完成！”。
- 左右侧均采用两次点击确认。第一次显示气泡提示，第二次才切换：右侧跳过当前步骤并开始下一步；左侧重新开始上一步，并将当前未完成步骤保留为待执行。
- 正常步骤切换依赖响应式状态更新与缩放/透明度动画；倒计时每 250ms 刷新，但不写磁盘。
- 提供暂停/继续、后台恢复后的“开始下一步”和结束任务按钮；步骤推进统一由右侧两次点击完成，整包完成后短暂保留完成状态再返回日历，主动结束直接返回日历。

## 四、从日历进入执行页

新建 `entry/src/main/ets/pages/ScheduledEventDetailDialog.ets`，并将 `CalendarTab` 的日程短按详情替换为实例详情：

- 展示该 `ScheduledEvent` 实际保存的时间与步骤，而不是反查模板后展示模板。
- “开始任务”创建会话并进入执行页。
- 已有会话时显示“继续任务”；已完成/已放弃时显示“查看结果”（本轮先复用执行页快照展示，完整结果页属于 E5）。
- 若已有其他活跃会话，显示提示且不覆盖原会话。

任务包列表中的 `PackageDetailDialog` 保持模板语义，未被改造成日程详情。

## 五、测试

新增 `entry/src/test/ExecutionSession.test.ets` 并注册到测试套件，覆盖：

1. 从日程创建会话是深拷贝。
2. 使用注入时间戳暂停和恢复时，剩余时间计算正确。
3. 后台恢复只完成当前已到期步骤并进入 `waiting-next`，下一步骤保持 `pending`。

## 六、验证状态与后续

- 已完成源码静态核对；横屏 API 使用 HarmonyOS 离线 API 文档中的 `Window.setPreferredOrientation` 方式。
- 当前工作区未提供 `hvigorw` / 可调用的 DevEco Hvigor CLI，因此本轮无法在此环境运行 `assembleHap` 或 Hypium；需在 DevEco Studio 环境执行：

```text
hvigorw --no-daemon --mode module -p module=entry@default assembleHap
```

- 真机重点验收：横竖屏切换、白场到主题色过渡、左右两次点击、锁屏后的 `waiting-next` 行为、杀进程后的会话恢复。
- R1 应用内到点提醒、E4 后台/进程终止专项验收、E5 日历状态图标和结果页仍按 `plan.md` 后续阶段执行。

---

## 七、任务包详情快速开始（同日追加）

修改 `entry/src/main/ets/pages/PackageDetailDialog.ets`：

- 在“总时长”和“关闭”之间加入“现在开始吧！”按钮。
- 它与关闭按钮同宽、同高（44vp），但使用顶部“编辑”按钮相同的主题色文字与 `color + '20'` 浅色背景。
- 点击后从当前模板深拷贝步骤并创建独立执行会话，随后进入横屏计时页。
- 快速开始不会创建或写入 `ScheduledEvent`，因此不会在日历中产生虚假的计划事件。
- 空任务包会提示先添加步骤；已有其他活跃会话时会提示先处理当前任务。

### ArkTS 严格对象字面量修复

- `ExecutionSession.ets` 中映射生成的步骤记录先声明为 `ExecutionStepRecord`，再返回。
- `PackageDetailDialog.ets` 中快速开始的步骤副本先声明为 `TaskStep`，再返回。
- 两处均消除了 `arkts-no-untyped-obj-literals`，数据和交互行为不变。

---

## 八、执行页导航与实时总进度修复（2026-09-13）

- 将上/下一步骤从两个绝对定位节点改为全宽 `Row`：上一步固定左侧、下一步固定右侧，二者不再重叠。
- 移除“完成当前步骤”按钮。右侧两次点击已覆盖推进步骤的操作，保留它会造成重复入口；底部只保留暂停/继续（或等待态的“开始下一步”）和结束任务。
- 最后一步右侧显示“完成！”，第二次点击后会完成该步骤、将会话置为 `completed`，并在短暂完成反馈后自动返回日历。
- 顶部进度条改为累计式：已完成/跳过步骤占满各自的计划时长，当前步骤按 `remainingMs` 与 `runStartedAt` 每秒实时推进；步骤切换后进度自然进入下一个章节，不再停留在第一段。
- 同时修复暂停路径将当前步骤误标为 `pending` 的问题，暂停后的累计进度会稳定保留，不会回退。

---

## 九、全屏背景与章节边界（2026-09-13）

- 执行页根 `Stack` 使用 `expandSafeArea` 扩展到系统安全区四边，主题色背景会覆盖横屏时底部原本留出的白色导航安全区。
- 顶部累计进度条新增位于填充层上方的竖向章节分隔线；无论该章节已完成、正在进行还是未开始，均能辨认步骤边界。

---

## 十、沉浸式窗口与执行提示（2026-09-13）

- 在执行页进入/离开时调用 `Window.setWindowLayoutFullScreen(true/false)`；它从窗口层扩大可用布局范围，配合已有的安全区扩展覆盖横屏底部仍残留的白区。
- 首步骤的左侧“无”按钮改为单击提示“现在已经是第一个步骤”，气泡与按钮下方反馈文字一致；非首步骤仍保持两次点击回到上一步。
- 暂停和继续按钮分别显示“倒计时已暂停”“倒计时已开始”气泡提示；后台恢复后的“开始下一步”也使用相同开始反馈。
