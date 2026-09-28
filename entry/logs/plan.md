# StudyStream / TimeCraft 后续开发规划

> 文档状态：可执行规划初稿  
> 编写日期：2026-09-09  
> 依据：`README.md`、`log_0107.md`、`log_08.md`～`log_11.md`、`left_problem.md` 与当前源码  
> 适用平台：HarmonyOS NEXT，当前工程兼容 API 23

---

## 1. 这份规划要解决什么

当前应用已经能够创建任务包、把任务包安排到月/周/日历并持久化，但用户到达计划时间后，应用没有继续帮助用户执行任务。下一阶段的首要目标不是增加更多展示效果，而是完成下面这条可验证闭环：

```text
创建任务包
→ 安排到今天
→ 打开已安排日程
→ 手动开始
→ 按步骤计时执行
→ 暂停/恢复/跳过/提前完成
→ 完成整包
→ 日历显示结果
→ 杀掉并重启应用后结果仍然正确
```

这条闭环跑通之前，不启动创意工坊、NFC、跨设备联动和复杂推荐系统的开发。

### 1.1 本规划采用的产品假设

1. `TaskPackage` 是可复用的母模板。
2. `ScheduledEvent` 是母模板在某一天、某个时间的计划实例。
3. `ExecutionSession` 是用户真正开始后产生的一次执行记录，必须与前两者分开。
4. 第一版一次只允许一个处于 `running`、`paused` 或 `waiting-next` 的执行会话。
5. 到达计划时间不等于用户已经开始；第一版必须由用户确认“开始任务”。
6. 第一版以单设备、本地数据为准，不引入账号和云同步。
7. 第一版步骤时长仍以分钟配置，执行界面以秒展示。
8. 进程进入后台后不能依赖普通定时器持续执行；真实时间以持久化时间戳计算。

### 1.2 第一阶段明确不做的事情

- 不自动修改用户当天其他日程来“智能腾挪时间”。
- 不在任务开始时自动修改勿扰模式或其他系统设置。
- 不接第三方音乐服务。
- 不做 AI 自动排程。
- 不做账号、云同步、好友或社区。
- 不做 NFC 导入。
- 不一次性重写现有 `CalendarTab.ets`。
- 不为了展示流畅而每秒把倒计时写入 Preferences。

这些功能不是永久取消，而是在执行闭环验收前不进入开发范围。

---

## 2. 当前工程基线

### 2.1 已具备能力

| 能力 | 当前状态 | 可复用部分 |
|---|---|---|
| 任务包模板 | 已完成 | `TaskPackage`、`TaskStore`、`CreatePackage.ets` |
| 月/周/日视图 | 已完成 | `CalendarTab.ets` |
| 拖拽安排 | 已有可用版本 | `ScheduledEvent`、`ScheduleStore` |
| 本地持久化 | 已完成 | `Persistence.ets` + Preferences |
| 编辑母任务包 | 已完成 | `CreatePackage` 的 `packageId` 模式 |
| 日历事件绝对定位 | 已完成 | 时间到 Y 坐标、时长到高度的换算 |
| 时间轴缩放 | 代码已完成 | `weekHourHeight` / `dayHourHeight`，仍需设备复验红线联动 |
| 系统文本分享 | 已有实现尝试 | `@kit.ShareKit`，后续需按新文本格式调整 |

### 2.2 当前缺口

1. 没有“开始已安排任务”的入口。
2. 没有运行中会话、步骤状态、暂停和完成记录。
3. 没有可靠的后台/重启恢复逻辑。
4. 日历不知道一个事件是未开始、运行中还是已完成。
5. 当前 `entry/src/test` 和 `entry/src/ohosTest` 仍是模板示例，没有产品逻辑测试。
6. `ScheduleStore` 的变更通知不统一：部分方法持久化后不通知 UI。
7. `CalendarTab.ets` 已经承担日历、缩放、拖拽、菜单、分享、拉伸等多种职责；继续直接堆状态会提高回归风险。
8. `left_problem.md` 中长按聚焦、单实例编辑、复制/剪切、拉伸、自由拖放和重复安排仍待实现。

### 2.3 不进行全量架构重构

下一阶段只新增执行域所需文件，并在必要连接点修改现有文件。不要先把所有 Store 改成 MVVM，也不要先拆完整 CalendarTab。只有一个逻辑被三个以上调用方共同使用时，才抽成独立模块。

---

## 3. 目标数据结构

### 3.1 三层对象职责

| 对象 | 表达内容 | 是否会被执行过程修改 |
|---|---|---|
| `TaskPackage` | 可复用母模板 | 否 |
| `ScheduledEvent` | 某次计划的日期、时间和内容副本 | 单实例编辑/拉伸时会修改；运行计时不修改 |
| `ExecutionSession` | 一次实际执行及结果 | 是 |

任务开始时，从 `ScheduledEvent` 深拷贝名称、颜色和步骤生成 `ExecutionSession`。开始之后，即使母任务包或日程实例被编辑，正在运行的会话也不改变。

### 3.2 `ScheduledEvent` 后续补充字段

为支持单实例编辑和铅笔标记，后续在 `ScheduledEvent` 增加：

```typescript
/** 当前日程实例是否已经偏离母任务包 */
isCustomized?: boolean;
```

兼容规则：

- 旧 Preferences 数据没有此字段时按 `false`。
- 单实例编辑保存后设为 `true`。
- 拉伸导致步骤时长变化后也设为 `true`。
- `TaskStore.updatePackage()` 触发 `syncPackageFields()` 时，跳过 `isCustomized === true` 的事件名称和步骤，防止覆盖实例修改。
- `packageId` 继续保留，用于说明实例来源；不能把 `packageId` 当成日程实例唯一标识。

### 3.3 新增执行模型

建议新增文件：

```text
entry/src/main/ets/models/ExecutionSession.ets
```

建议的数据结构如下。字段只覆盖第一版需要的恢复、计时和结果记录，不预留社区或云端字段。

```typescript
export type ExecutionStatus =
  'running' | 'paused' | 'waiting-next' | 'completed' | 'abandoned';

export type ExecutionStepStatus =
  'pending' | 'running' | 'completed' | 'skipped';

export interface ExecutionStepRecord {
  index: number;
  name: string;
  plannedDurationMs: number;
  status: ExecutionStepStatus;

  /** 已经实际执行的累计毫秒数，不包含暂停时间 */
  elapsedActiveMs: number;

  /** 当前一段运行开始的 Unix 毫秒时间；非运行态为 0 */
  runStartedAt: number;

  /** 暂停或恢复时固化的剩余时间 */
  remainingMs: number;

  completedAt: number;
}

export interface ExecutionSession {
  id: string;
  scheduledEventId: string;
  sourcePackageId: string;

  /** 开始时从日程实例复制，之后不再跟随模板变化 */
  packageName: string;
  color: string;
  steps: ExecutionStepRecord[];

  currentStepIndex: number;
  status: ExecutionStatus;
  startedAt: number;
  completedAt: number;
  updatedAt: number;
}
```

### 3.4 为什么保存 `remainingMs` 和 `runStartedAt`

运行时剩余时间按下面公式实时计算：

```text
实时剩余时间
= max(0, remainingMs - (Date.now() - runStartedAt))
```

暂停时执行一次状态提交：

```text
elapsed = Date.now() - runStartedAt
remainingMs = max(0, remainingMs - elapsed)
elapsedActiveMs += elapsed
runStartedAt = 0
status = paused
```

恢复时只需要：

```text
runStartedAt = Date.now()
status = running
```

这样页面每 250ms 或 1000ms 刷新一次只影响 UI，不写磁盘；应用进入后台或进程被终止后，通过时间戳仍能算出正确结果。

### 3.5 后台跨步骤策略

第一版不让多个步骤在后台悄悄连续跑完：

- 页面在前台时，当前步骤倒计时归零后自动完成，并立即启动下一步骤。
- 页面不在前台、进程被挂起或被终止时，只允许当前步骤的时间继续流逝。
- 用户返回后如果发现当前步骤已经到时，将其结算为完成，并把会话设为 `waiting-next`。
- 用户点击“开始下一步”后才启动下一步骤。

这样不会因为用户半小时没有打开应用，就把没有实际做过的后续步骤全部标记为完成。

### 3.6 执行数据存储格式

在 `ExecutionSession.ets` 内新增 `ExecutionStore`，使用独立 Preferences 键：

```text
execution_sessions_v1
```

存储内容使用带版本号的包装对象：

```typescript
interface ExecutionStorePayload {
  schemaVersion: number;
  sessions: ExecutionSession[];
}
```

第一版 `schemaVersion = 1`。以后字段发生不兼容变化时写迁移函数，不能静默丢弃历史。

存储规则：

- 开始、暂停、恢复、完成步骤、跳过步骤、放弃和完成整个任务时持久化。
- `onBackground()` 和页面销毁前，如果当前状态发生过未提交变化，则持久化一次。
- 普通 UI tick 不持久化。
- Store 每次成功变更后统一通知订阅者。
- 恢复 JSON 时捕获解析异常；异常数据先保留原字符串到备份键，再回到空会话列表并记录日志，不能让应用启动崩溃。

---

## 4. 执行状态机

### 4.1 会话状态转换

| 当前状态 | 用户/系统动作 | 下一状态 | 必须写入的数据 |
|---|---|---|---|
| 无会话 | 点击“开始任务” | `running` | 会话快照、首步骤、开始时间 |
| `running` | 点击暂停 | `paused` | 本段已运行时间、剩余时间 |
| `paused` | 点击继续 | `running` | 新的 `runStartedAt` |
| `running` | 当前步骤到时（前台） | `running` 或 `completed` | 完成当前步；若有下一步则启动 |
| `running` | 回到前台时发现步骤到时 | `waiting-next` 或 `completed` | 只结算当前步，不消耗后续步骤 |
| `waiting-next` | 点击开始下一步 | `running` | 下一步 `runStartedAt` |
| `running` / `paused` | 提前完成步骤 | `running` 或 `completed` | 实际时长、当前步完成 |
| `running` / `paused` | 跳过步骤 | `running`、`waiting-next` 或 `completed` | 当前步 `skipped` |
| 活跃状态 | 点击结束并确认 | `abandoned` | 结束时间、已完成/跳过情况 |

### 4.2 状态约束

1. 同一时间只允许一个活跃会话。
2. 用户开始另一任务时，如果已有活跃会话，显示“继续当前任务 / 结束当前任务后开始 / 取消”，不能静默覆盖。
3. `completed` 和 `abandoned` 不允许重新回到 `running`。
4. `currentStepIndex` 必须指向有效步骤；全部结束后固定为最后一项或 `steps.length`，实现时选择一种并通过测试固定下来。
5. 任何步骤的 `remainingMs` 不得小于 0。
6. 同一状态转换重复调用必须是幂等的。例如倒计时归零触发两次，只能完成一次步骤。

### 4.3 Store 对外方法

`ExecutionStore` 第一版只暴露以下方法：

```typescript
restore(): void
getActiveSession(): ExecutionSession | undefined
getLatestSessionByEventId(eventId: string): ExecutionSession | undefined
startFromScheduledEvent(event: ScheduledEvent, nowMs?: number): ExecutionSession | undefined
pause(sessionId: string, nowMs?: number): boolean
resume(sessionId: string, nowMs?: number): boolean
completeCurrentStep(sessionId: string, nowMs?: number): boolean
skipCurrentStep(sessionId: string, nowMs?: number): boolean
startNextStep(sessionId: string, nowMs?: number): boolean
abandon(sessionId: string, nowMs?: number): boolean
reconcile(sessionId: string, nowMs?: number): void
onChange(listener: () => void): void
offChange(listener: () => void): void
```

方法允许传入 `nowMs` 是为了让单元测试使用确定时间；生产调用省略时再使用 `Date.now()`。不需要为此创建一整套 Clock 抽象。

`startFromScheduledEvent()` 的返回规则必须固定：同一事件已有活跃会话时返回该会话；另一个事件正在活跃时返回 `undefined`，由 UI 显示选择弹窗；不存在冲突时创建并返回新会话。

---

## 5. 第一主线：完成执行闭环

以下阶段按依赖顺序执行。每个阶段单独构建、测试和真机验收；上一阶段未通过时不进入下一阶段。

## 阶段 E1：执行模型与 Store

### 要修改的文件

- 新建 `entry/src/main/ets/models/ExecutionSession.ets`
- 修改 `entry/src/main/ets/entryability/EntryAbility.ets`
- 新建或替换 `entry/src/test/ExecutionSession.test.ets`
- 修改 `entry/src/test/List.test.ets` 注册测试套件

### 实施步骤

1. 定义执行状态、步骤记录和会话接口。
2. 实现从 `ScheduledEvent` 深拷贝生成会话。
3. 实现上述状态转换方法。
4. 所有转换统一调用一次 `persist()` 和一次 `notifyChange()`。
5. 在 `EntryAbility.onCreate()` 中，按 `persistence.init → taskStore.restore → scheduleStore.restore → executionStore.restore` 顺序恢复。
6. 暂不修改任何日历 UI。

### 单元测试

- 开始会话时名称、颜色和步骤为深拷贝。
- 修改来源 `ScheduledEvent.steps` 不影响会话快照。
- 暂停 10 秒后，剩余时间和累计执行时间正确。
- 暂停期间经过 10 分钟，剩余时间不变。
- 恢复后从新的时间戳继续。
- 提前完成、跳过、正常到时分别产生正确状态。
- 最后一步完成后会话变成 `completed`。
- 同一转换调用两次不重复推进步骤。
- 已有活跃会话时禁止创建第二个活跃会话。
- 序列化后恢复得到相同状态。

### 完成标准

- 上述测试全部通过。
- 工程 `assembleHap` 构建成功。
- 不修改 `CalendarTab`，现有日历行为无回归。

## 阶段 E2：执行页面

### 要修改的文件

- 新建 `entry/src/main/ets/pages/ExecutionPage.ets`
- 修改 `entry/src/main/resources/base/profile/main_pages.json` 注册页面
- 视需要新增少量颜色/字符串资源

### 页面最小内容

1. 任务名称。
2. “步骤 X / 总步骤数”。
3. 当前步骤名称。
4. 大号 `MM:SS` 倒计时。
5. 当前步骤进度条和整个任务进度。
6. 暂停/继续按钮。
7. 提前完成当前步骤按钮。
8. 跳过当前步骤按钮。
9. 结束任务按钮，二次确认后标记 `abandoned`。
10. `waiting-next` 状态显示“当前步骤已结束”和“开始下一步”。

### 页面刷新方案

- 页面只维护一个用于刷新显示的 `@State nowMs`。
- 前台使用 `setInterval` 每 250ms 更新 `nowMs`，剩余时间始终由 Store 快照和 `nowMs` 计算。
- tick 不修改会话对象、不写 Preferences。
- 检测到当前步骤归零时，只调用一次 Store 状态转换。
- 页面销毁时清理 timer；重新进入时调用 `executionStore.reconcile()`。

### 稳定 UI 标识

为后续 ohosTest 添加稳定 ID：

```text
execution-page
execution-title
execution-step-name
execution-timer
execution-progress
execution-pause-resume
execution-complete-step
execution-skip-step
execution-abandon
execution-start-next
```

### 完成标准

- 可以通过临时测试入口打开一个模拟会话。
- 计时、暂停、继续、提前完成、跳过和最终完成均能操作。
- 页面离开再返回后显示正确。
- 没有负数倒计时或一步被完成两次的问题。

## 阶段 E3：从日历开始执行

### 要修改的文件

- 新建 `entry/src/main/ets/pages/ScheduledEventDetailDialog.ets`
- 修改 `entry/src/main/ets/pages/CalendarTab.ets`
- 修改 `PackageDetailDialog.ets` 仅限必要复用；不要让它同时承担模板和日程两套数据语义

### 实施方案

1. 已安排事件短按时，不再优先反查母 `TaskPackage` 展示；直接把当前 `ScheduledEvent` 交给日程实例详情弹窗。
2. 弹窗显示实际实例的名称、时间和步骤。
3. 增加“开始任务”按钮。
4. 点击后调用 `executionStore.startFromScheduledEvent(evt)`，再通过路由进入 `ExecutionPage`，路由参数传 `sessionId`。
5. 如果该事件已经有活跃会话，按钮改为“继续任务”。
6. 如果事件已经完成或放弃，按钮显示“再次开始”；点击后为同一 `ScheduledEvent` 创建新的独立执行记录，历史记录继续保留。
7. 如果另一个事件正在运行，按状态约束显示选择弹窗。

### 完成标准

- 从任意已安排事件可以开始执行。
- 开始后修改母任务包不会改变当前会话。
- 返回日历再点同一事件会继续同一会话，不会创建重复会话。
- 已完成或已放弃的事件可以再次开始，并从第一步完整时长创建新会话。
- 同时启动第二个事件会被明确拦截。

## 阶段 E4：后台、进程终止和恢复

### 要修改的文件

- `ExecutionSession.ets`
- `ExecutionPage.ets`
- `EntryAbility.ets`
- 对应单元测试和 ohosTest

### 实施方案

1. `ExecutionPage.aboutToDisappear()` 清理显示 timer，但不把 `running` 自动改成 `paused`。
2. `EntryAbility.onBackground()` 只做一次状态持久化，不尝试保持一个永久后台定时器。
3. `EntryAbility.onForeground()` 或 `ExecutionPage.aboutToAppear()` 调用 `reconcile(now)`。
4. 若当前步骤在后台已到时，只结算这一项并进入 `waiting-next`；不连续消耗后续步骤。
5. 进程重启时先恢复 Store，再决定首页是否显示“继续当前任务”入口。
6. 用户手动调整系统时间属于第一版已知限制；记录日志，不在这一阶段引入双时钟校正。

### 必测场景

- 运行 10 秒后锁屏 30 秒，再回来剩余时间减少约 30 秒。
- 暂停后锁屏，剩余时间不变。
- 运行中从最近任务划掉应用，再打开，状态恢复。
- 当前步骤在后台过期，回来后只进入 `waiting-next`，下一步没有被自动消耗。
- 完成后重启，仍显示完成记录。

### 完成标准

- 上述场景逐项通过真机或模拟器测试并记录结果。
- 没有依赖后台 `setInterval` 或长时后台任务。

## 阶段 E5：日历状态反馈与完成次数

### 日历展示

`CalendarTab` 从 `ExecutionStore` 为当前可见事件构造一次状态映射，不要在每个 Builder 中反复遍历全部历史。

| 执行状态 | 日历事件块表现 |
|---|---|
| 未开始 | 保持当前样式 |
| `running` | 右上角显示播放/进行中图标，可增加细进度条 |
| `paused` | 显示暂停图标 |
| `waiting-next` | 显示“下一步”提示点 |
| `completed` | 降低透明度、标题增加删除线，并显示累计完成次数 |
| `abandoned` | 显示中止标记，不伪装成完成 |

### 完成结果

第一版不单独制作结果页。完成结果通过日历事件块的弱化样式和“已完成 x 次”反馈；详情页提供“再次开始”，每次执行保留独立历史记录。

### 完成标准

- 执行页面状态变化后，返回日历立即更新。
- 重启后日历标记仍正确。
- 每正常完成一轮，标题中的累计次数增加 1；放弃不计入完成次数。
- 完成和放弃有明确不同的视觉结果。

---

## 6. 第二主线：补齐排程交互

执行闭环 E1～E5 完成后，再按以下顺序处理 `left_problem.md`。每一项单独验收，不合并成一次大改。

## 阶段 S1：允许同日重复安排同一任务包

### 方案

- 删除 `CalendarTab.handleDrop()` 中 `isPackageScheduledOnDate(packageId, date)` 的拒绝逻辑。
- 每次安排均生成新的 `ScheduledEvent.id`。
- 检查删除、移动、编辑、执行和复制逻辑全部以 `ScheduledEvent.id` 定位。
- `isPackageScheduledOnDate()` 如果无其他调用，保留或删除均可；不要让它继续承担业务约束。

### 验收

- 同一母任务包在同一天安排三次，重启后均存在。
- 编辑、删除或执行其中一个不影响另外两个。

## 阶段 S2：单实例编辑与铅笔标记

### 方案

- 为 `ScheduleStore` 增加 `getEventById()`。
- 给 `CreatePackage.ets` 增加互斥 `eventId` 模式，或新建日程实例编辑页面；优先复用现有表单，不复制一整套输入 UI。
- `eventId` 模式保存时只调用 `scheduleStore.updateEvent()`。
- 根据步骤总时长重新计算结束时间。
- 设置 `isCustomized = true`，事件块右上角显示铅笔。
- 修改 `syncPackageFields()`：不覆盖已定制事件。
- `updateEvent()` 完成后统一 `notifyChange()`。

### 验收

- 编辑一个日程实例，母任务包和同源其他实例保持不变。
- 返回日历立即刷新并显示铅笔。
- 编辑母任务包时，不覆盖定制实例。

## 阶段 S3：长按聚焦态

具体视觉和状态机以 `left_problem.md` 需求 3 为准。

### 实施顺序

1. 先只做“静止长按 400ms 进入聚焦、移动则滚动、点击背景退出”。
2. 使用页面最外层 `Stack`：原页面、模糊蒙层、清晰事件副本、自定义菜单分层。
3. 模糊只在聚焦态启用；选中副本和菜单不得放在被模糊父节点中。
4. 设备验证长按/滚动冲突后，再接菜单动作。

### 验收

- 静止长按可稳定弹出；快速滑动从事件块内部起手仍只滚动。
- 背景模糊，选中事件块保持清晰并有蓝色细边框。
- 菜单固定为编辑、剪切、复制、分享。

## 阶段 S4：上下边缘直接拉伸

### 方案

- 聚焦态蓝色上、下边缘各提供约 12～16vp 命中区，视觉线保持 1～2vp。
- `PanGesture` 仅挂在两个边缘命中区。
- 拖动上边缘保持结束时间不变；拖动下边缘保持开始时间不变。
- 5 分钟吸附；拖动中只改预览，松手一次持久化。
- 步骤按比例缩放，最后一步补齐取整差额，每一步至少 1 分钟。
- 拉伸后设置 `isCustomized = true`。

### 验收

- 普通状态仍能从任务包内部滚动。
- 聚焦后上下边缘容易命中，主体不会误拉伸。
- 缩放倍率不同、时间轴滚动后拉伸结果仍准确。

## 阶段 S5：复制/剪切两段确认

### 方案

- 使用统一主状态：`copy-await-target`、`cut-await-target`、`paste-preview`。
- 剪切后只在 UI 层临时隐藏源事件，不立即删除持久化数据。
- 第一次点击空白位置只放置带“+”的虚线框。
- 第二次点击虚线框内部才提交。
- 复制创建新 ID；剪切更新原 ID。
- 点击其他空白位置移动预览框；取消时恢复被隐藏事件。

### 验收

- 中途取消不会丢失剪切源事件。
- 粘贴结果与虚线框最终位置完全一致。
- 复制可与 S1 的同日重复安排共存。

## 阶段 S6：自由拖放、虚线框和磁吸

### 前置重构

在实现该阶段前，抽取一个纯计算文件：

```text
entry/src/main/ets/utils/TimelineGeometry.ets
```

只包含以下函数：

- 时间分钟数 → 时间轴 Y。
- 时间轴局部 Y + Scroller 偏移 → 分钟数。
- 整点/半点磁吸判定。
- 事件时长 → 预览框高度。
- 0:00～24:00 边界裁剪。

这个抽取是必要的，因为拖放、复制、剪切、红色时间线和事件块定位都依赖同一坐标语义。

### 磁吸规则

1. 非磁吸状态先按 5 分钟粒度计算。
2. 计算目标位置到最近 `HH:00` 和 `HH:30` 的 vp 距离。
3. 距离小于设备调试确定的阈值（初始建议 8vp）时吸附。
4. 离开阈值立即解除吸附。
5. 松手直接使用最后一次预览状态，禁止重新调用另一套落点算法。

### 验收

- 不同缩放倍率和滚动位置下，预览框不漂移。
- 接近整点/半点才吸附，其他位置可自由安排。
- 拖放、复制和剪切共用同一几何结果。

---

## 7. 第三主线：提醒能力

提醒分成两级，避免系统权限阻塞执行 MVP。

## 阶段 R1：应用内提醒

### 方案

- 新安排的日程默认开启应用内通知，旧数据未包含开关字段时同样按开启处理。
- 月视图直接安排时，默认开始时间设为当前时间约 1 分钟后，便于快速验证提醒闭环；周/日视图继续使用用户放置的时间。
- 应用前台时每秒检查尚未开始的日程；进入开始前 1 分钟后先显示一次弱提示。
- 开始前 20 秒显示应用内确认框，按钮为“确认（xx秒）”和“稍后”；归零时进入执行准备流程。
- “稍后”第一版固定延后 5 分钟，只保存在当前前台会话的内存状态中。
- 日程详情页右上角提供通知开关；关闭后不再产生一分钟提示和 20 秒确认框。
- 同一事件在同一轮开始时间内只提示一次；已有执行历史的事件不重复触发原计划提醒。
- 新一轮开始统一经过白色界面隐去、任务色背景、横屏和 3、2、1 倒数；准备阶段不消耗第一步时间。

### 验收

- 前台停留时能在开始前约 1 分钟看到弱提示，并在最后 20 秒看到实时倒数确认框。
- 倒数归零后经过 3、2、1 进入计时页，第一步仍保持完整计划时长。
- 关闭通知后不再提示；点击稍后会在 5 分钟后重新进入提醒流程。
- 已完成、已放弃或已经运行的事件不重复提示。

## 阶段 R2：系统级后台提醒

HarmonyOS 的后台代理提醒可以在应用退后台或进程终止后定时通知，但手机、平板和 2in1 存在能力管控。该阶段开始前必须先确认上架主体和开放能力申请条件。

### 接入步骤

1. 在 AppGallery Connect 申请代理提醒开放能力。
2. 重新生成并配置签名 Profile。
3. 在模块中声明 `ohos.permission.PUBLISH_AGENT_REMINDER`。
4. 在运行时请求通知授权；拒绝后保留应用内提醒，不循环骚扰用户授权。
5. 使用 `reminderAgentManager.publishReminder()` 为计划开始时间发布日历提醒。
6. 保存系统返回的 `reminderId` 与 `ScheduledEvent.id` 映射。
7. 日程移动、删除或取消时调用 `cancelReminder(reminderId)`。
8. 修改时间时先取消旧提醒，再发布新提醒，最后更新映射。
9. 通知点击通过经验证的 Want/路由进入对应日程详情或执行页。

### 限制

- 不用普通 `setInterval` 模拟后台准时提醒。
- 不为了计时申请长期后台任务。
- 代理提醒能力未获批时，不阻塞应用其他功能发布。
- API 20 起模拟器支持该能力，但权限、通知点击和后台行为仍需真机验收。

### 验收

- 应用退后台和进程结束后仍能收到测试提醒。
- 移动/删除日程后旧时间不再弹提醒。
- 拒绝通知权限时应用不崩溃，执行功能仍可使用。

---

## 8. 第四主线：场景自动化

该阶段的进入条件是：执行闭环稳定，并且测试用户确实会点击“开始任务”。自动化必须由“用户确认开始”触发，不能仅因为计划时间到达就自动操作设备。

## 阶段 A1：只支持低风险动作

第一版动作类型限制为：

```text
open-app    打开用户选择的应用
open-link   打开 URL 或 App Linking
open-file   打开用户明确选择且仍有权限访问的文件
```

建议模型：

```typescript
interface TaskAction {
  id: string;
  trigger: 'session-start' | 'step-start';
  type: 'open-app' | 'open-link' | 'open-file';
  target: string;
  enabled: boolean;
}
```

实施约束：

- 每个动作由用户明确添加和开启。
- 执行失败只提示并继续任务，不让整包失败。
- 外部应用不存在、链接无处理方或文件权限过期时提供可理解错误。
- 第一次运行某动作前显示即将发生的操作。
- 不存储第三方账号密码。

## 阶段 A2：高权限系统动作

勿扰模式、通知控制、智能设备等功能逐项做能力和权限调研。只有对应公开 API、权限申请和设备覆盖均确认后，才把动作类型加入模型。无法稳定实现的能力必须在产品界面中隐藏，不能用“规划中”按钮占位。

### 自动化验收

- 动作只在用户开始会话或明确开始步骤后触发一次。
- 页面重建、恢复会话或重复点击不会重复打开应用。
- 动作失败不破坏计时状态。

---

## 9. 分享、NFC 与创意工坊

## 阶段 C1：先定义可导入模板格式

当前系统分享是人类可读纯文本，适合发送但无法可靠导入。NFC 和社区开始前先定义版本化模板格式：

```typescript
interface SharedTaskPackageV1 {
  schemaVersion: 1;
  name: string;
  steps: TaskStep[];
  actions?: TaskAction[];
}
```

安全规则：

- 导入时始终生成本地新 ID。
- 不接收来源的本地文件路径和内部数据库 ID。
- 动作默认关闭，用户逐项确认后才能启用。
- 对名称长度、步骤数量、单步时长和总数据大小设置上限。
- 先完成“导出文件/文本 → 本地导入”的闭环，再接 NFC。

## 阶段 C2：NFC

NFC 只传递版本化模板或安全的导入链接，不直接执行动作。验收必须覆盖设备不支持 NFC、NFC 关闭、数据损坏和版本不兼容。

## 阶段 C3：创意工坊

进入条件：至少已经证明用户会重复执行任务包并主动分享模板。社区第一版只做：

- 浏览公开模板。
- 查看详情。
- 导入到本地。
- 举报不合适内容。

点赞、关注、排行榜、创作者分成和评论在导入闭环稳定后再做。社区需要账号、服务端、审核、隐私政策和内容治理，不与本地 MVP 同时开发。

---

## 10. 测试与质量门槛

## 10.1 单元测试优先覆盖纯逻辑

必须测试：

- 执行状态转换。
- 时间戳与剩余时间计算。
- 步骤完成、跳过和取整。
- 序列化/恢复。
- 时间轴坐标正反换算。
- 整点/半点磁吸阈值。
- 单实例编辑不污染母模板。
- 同日重复实例互不影响。

不要用 UI 测试验证可以由纯函数确定的算术。

## 10.2 ohosTest 覆盖关键闭环

替换当前占位测试，使用稳定组件 ID 验证：

1. 打开事件详情。
2. 点击开始。
3. 暂停和继续。
4. 完成步骤。
5. 完成整个任务。
6. 返回日历看到完成标记。

长按、拖拽、双指缩放仍需设备手势验收；自动化测试不能代替真实触摸体验。

## 10.3 每阶段构建门槛

每个阶段至少执行当前已验证的打包命令：

```text
hvigorw --no-daemon --mode module -p module=entry@default assembleHap
```

要求：

- `CompileArkTS`、`PackageHap`、`PackingCheck`、`SignHap` 全部成功。
- 不新增 ArkTS 编译警告；既有 deprecated 警告单独记录，不趁功能阶段大范围修改。
- 每次设备验收记录具体操作、预期、实际结果和设备/API 版本。

## 10.4 执行闭环回归清单

每次修改执行域后至少人工验证：

- 正常完成全部步骤。
- 暂停后返回。
- 运行中锁屏。
- 运行中杀进程。
- 当前步骤在后台到时。
- 提前完成。
- 跳过中间步骤。
- 放弃任务。
- 来源日程被编辑。
- 母任务包被编辑。
- 重启后查看历史和日历标记。

---

## 11. 数据安全与迁移

1. 新字段优先使用可选字段并提供默认值，保证已有本地数据可恢复。
2. 对新 Store 使用 `schemaVersion`，不继续无限增加没有版本的裸数组 JSON。
3. 任何迁移先解析到新对象，验证通过后再覆盖正式键。
4. 剪切操作确认前不删除原数据。
5. 拖动、拉伸等连续交互只更新预览；手势结束时一次持久化。
6. 运行中的会话采用快照，不依赖母任务包始终存在。
7. 删除母任务包与保留执行历史的关系：执行历史保留自身快照；日程是否级联删除沿用现有规则，后续若要修改必须单独立需求。
8. 不在日志中记录用户的完整任务文本、分享内容或本地文件路径。

---

## 12. 产品验证，不以功能数量判断进度

执行闭环上线内部测试后，先记录本地匿名聚合指标，不立即接远程分析 SDK：

- 创建的任务包数量。
- 每个任务包被安排次数。
- 已安排事件中点击开始的比例。
- 开始后完成的比例。
- 平均完成步骤比例。
- 同一任务包在不同日期重复执行的次数。
- 用户从安排到开始执行的间隔。

### 小规模试用门槛

先找少量真实用户连续使用 7 天。以下指标作为是否继续投入的方向信号，不当作统计学结论：

1. 多数测试者能在没有开发者指导的情况下完成“创建 → 安排 → 开始 → 完成”。
2. 至少一半测试者在一周内重复执行同一个任务包。
3. 用户主要抱怨是功能缺失，而不是“创建和安排太麻烦”。
4. 实际开始率明显高于零；若用户只安排不执行，应先修执行入口和提醒，不做社区。
5. 用户能说清任务包相比普通日历为他节省了什么操作或决策。

如果这些条件不成立，优先简化创建和开始流程，而不是继续增加自动化类型。

---

## 13. 文档与代码维护规则

1. 每完成一个阶段，在 `entry/logs` 新建或更新对应日志，写清问题、方案、文件、验证和遗留。
2. `left_problem.md` 只记录尚未完成或设备验收未通过的问题；完成后更新状态并链接日志。
3. `README.md` 在执行闭环完成后更新真实路线图，解决 StudyStream/TimeCraft 名称与当前功能状态不一致的问题。
4. 一个阶段只处理本阶段范围；发现无关问题先记录，不顺手重构。
5. `CalendarTab.ets` 只有在共享几何逻辑或独立事件组件确实出现多个调用方时才拆分。
6. 新增公共方法必须有实际调用方和验收用例。

---

## 14. 推荐实施顺序总表

| 顺序 | 阶段 | 交付物 | 进入下一阶段的条件 |
|---|---|---|---|
| 1 | E1 | `ExecutionSession` + `ExecutionStore` + 单测 | 状态机和恢复测试通过 |
| 2 | E2 | `ExecutionPage` | 前台完整执行一个任务 |
| 3 | E3 | 日历开始/继续入口 | 同一日程不会重复创建会话 |
| 4 | E4 | 后台与重启恢复 | 锁屏、杀进程、过期场景通过 |
| 5 | E5 | 日历状态和结果 | 返回/重启后状态一致 |
| 6 | S1 | 同日重复安排 | 三个实例互不影响 |
| 7 | S2 | 单实例编辑 + 铅笔 | 母模板不被修改 |
| 8 | S3 | 长按聚焦态 | 长按和滚动设备验收通过 |
| 9 | S4 | 直接拉伸 | 多倍率下拉伸准确 |
| 10 | S5 | 复制/剪切二次确认 | 取消无数据损失 |
| 11 | S6 | 自由拖放 + 磁吸 | 所有入口共用同一坐标结果 |
| 12 | R1 | 应用内到点提示 | 前台不重复提醒 |
| 13 | R2 | 系统后台提醒 | 能力获批且真机通过 |
| 14 | A1 | 打开应用/链接/文件 | 失败不影响会话 |
| 15 | C1 | 可导入模板格式 | 本地导入导出稳定 |
| 16 | C2/C3 | NFC / 创意工坊 | 用户复用与分享需求已验证 |

---

## 15. 下一次开发应直接执行的任务

下一次不要同时修改日历手势。只完成阶段 E1：

1. 新建 `ExecutionSession.ets`。
2. 实现会话与步骤状态结构。
3. 实现 `ExecutionStore` 的开始、暂停、恢复、完成、跳过、放弃和恢复方法。
4. 使用独立版本化 Preferences 键持久化。
5. 在 `EntryAbility` 启动时恢复。
6. 用可注入 `nowMs` 的方式编写确定性单元测试。
7. 构建 HAP，确认没有影响现有日历。
8. 在新的开发日志中记录实现和测试结果。

E1 的完成定义是“执行状态机在无 UI 情况下已经可靠”，而不是“文件已经创建”。只有 E1 测试通过，才开始绘制执行页面。
