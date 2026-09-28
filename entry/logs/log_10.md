# 鸿蒙应用第十次开发日志

## 项目信息

- **项目名称**：StudyStream
- **开发日期**：2026-09-05
- **范围**：需求 0（编辑任务包后时间轴不即时刷新）+ 需求 1（事件块跨小时分隔线显示 / 绝对定位重构），及其两轮编译测试反馈修复

---

# Part 1 · 需求 0：编辑任务包后时间轴不即时刷新

## 一、问题现象

在日历**周/日视图**里点击事件块（或左侧任务包卡片）→ 详情弹窗 →「✏ 编辑」→ 修改步骤时长/数量 →「保存」→ `router.back()` 返回日历后，**时间轴不即时更新**：被编辑任务包对应的事件块高度及其所在小时槽位的高度仍是旧值，只有切换视图（月/周/日）或切换 Tab 再切回来才恢复。

---

## 二、根因分析（两层，缺一不可）

### 第 1 层：刷新链路不可靠

数据层是**正确**的——`TaskStore.updatePackage()` 内部已调用 `scheduleStore.syncPackageFields(updatedPkg)`（见 `log_08`），把日程里冗余的 `steps` / `endHour` / `endMinute` 一并更新，因此 `scheduleStore.events` 里是最新数据。

问题在 UI 层：时间轴高度依赖两个 `@State` 数组 `dayHourHeights` / `weekHourHeights`，它们本应由 `Index.onPageShow() → refreshTrigger++ → CalendarTab.loadData()` 触发重算，但该链路在「从编辑页 `router.back()` 返回」时**没有即时生效**。

### 第 2 层：`ForEach` 复用旧 Item、不重建（关键）

即使 `loadData()` 被调用了、`weekHourHeights` / `dayHourHeights` 也重新赋值了，**视觉上仍不会更新**，因为时间轴的 `ForEach` 都用了**稳定 key**：

| 位置 | key | 问题 |
|------|-----|------|
| 周视图左侧时间标签槽位 | `time-${hour}` | 数据变、key 不变 → 槽位高度不更新 |
| 周视图内容列小时槽位 | `${day.dateStr}-h${hour}` | 同上 |
| 日视图左侧时间标签槽位 | `day-time-${hour}` | 同上 |
| 日视图内容列小时槽位 | `day-col-${hour}` | 同上 |

这正是项目在 `log_06` 已经踩过、并用 `TaskPackage._version` 解决的同一类问题——`TaskPackage.ets` 里 `_version` 的注释写得明白：**「编辑后 id 不变 → key 不变 → ListItem 不重建」**。

---

## 三、修复方案（两部分）

### A. 数据层主动通知（不依赖 onPageShow）

给 `ScheduleStore` 增加订阅/回调机制（`onChange` / `offChange` / `notifyChange`），在级联变更时通知订阅者；`CalendarTab` 订阅后主动调用 `loadData()`。这样无论从哪条路径编辑返回都会触发重算。

- **只通知「级联变更」路径**：`notifyChange()` 仅在 `syncPackageFields`（编辑）和 `removeEventsByPackageId`（删除）时调用。这两个方法由 `TaskStore` 触发、发生在 `CalendarTab` 之外。`addEvent` / `removeEvent` 仍由调用方（`CalendarTab`）在操作后自行刷新，不加通知以避免重复刷新。
- **去重订阅**：`onChange` 用 `indexOf === -1` 去重。
- **生命周期配对**：`aboutToAppear` 订阅、`aboutToDisappear` 退订，防止销毁后泄漏。

### B. 版本号强制 `ForEach` 重建（关键）

给 `CalendarTab` 增加 `@State schedulesVersion`，`loadData()` 末尾自增，并把版本号拼进时间轴的 `ForEach` key。key 一变，`ForEach` 强制重建小时槽位与其中的事件块，从而读到最新的高度与事件 `steps`。

---

## 四、文件变更清单

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/models/ScheduledEvent.ets` | 新增 `listeners` 字段 + `onChange()` / `offChange()` / `notifyChange()`；`syncPackageFields` / `removeEventsByPackageId` 末尾调用 `notifyChange()` |
| `entry/src/main/ets/pages/CalendarTab.ets` | 新增 `scheduleStoreListener` 字段 + `aboutToAppear` 订阅 + `aboutToDisappear` 退订；新增 `@State schedulesVersion` + `loadData()` 自增；时间轴 `ForEach` key 拼入 `-v${schedulesVersion}` |
| `entry/logs/log_10.md` | 本日志文件 |

### 详细变更

**`ScheduledEvent.ets`**

```typescript
// 新增监听器集合
private listeners: Array<() => void> = [];

// syncPackageFields / removeEventsByPackageId 的变更块追加：
if (changed) {                       // 或 length 判断
  this.persist();
  this.notifyChange();
}

// 类末尾新增三个方法
public onChange(listener: () => void): void { /* 去重后 push */ }
public offChange(listener: () => void): void { /* splice 移除 */ }
private notifyChange(): void { /* 遍历调用 */ }
```

**`CalendarTab.ets`**

```typescript
// 1. 新增字段
private scheduleStoreListener: (() => void) | null = null;
@State private schedulesVersion: number = 0;

// 2. aboutToAppear 订阅
this.scheduleStoreListener = (): void => { this.loadData(); };
scheduleStore.onChange(this.scheduleStoreListener);

// 3. 新增 aboutToDisappear 退订
aboutToDisappear(): void {
  if (this.scheduleStoreListener !== null) {
    scheduleStore.offChange(this.scheduleStoreListener);
    this.scheduleStoreListener = null;
  }
}

// 4. loadData 末尾自增
loadData(): void {
  ...
  this.schedulesVersion++;   // 强制时间轴 ForEach 重建
}
```

---

## 五、数据流（修复后）

```
编辑任务包 → CreatePackage.savePackage()
  → taskStore.updatePackage()
      → scheduleStore.syncPackageFields(updatedPkg)   // 数据更新（原有）
          → this.notifyChange()                        // 新增：通知订阅者
              → CalendarTab.scheduleStoreListener
                  → this.loadData()
                      → this.schedulesVersion++        // 新增：强制重建
                          → 时间轴 ForEach key 变化 → 槽位/事件块重建 → 立即刷新
```

---

## 六、编译与测试

### 编译

```
hvigorw assembleHap --mode module -p module=entry@default -p product=default
```

结果：**BUILD SUCCESSFUL**。仅有既有的 `deprecated` 警告（`getY` / `getParams` / `showToast` / `back`），与本次改动无关，无新增错误。

### 测试要点（手动）

1. **核心场景**：日历周视图或日视图 → 点击事件块 → 详情弹窗 →「✏ 编辑」→ 修改某步骤时长（如 20 分钟改成 60 分钟）→「保存」→ `router.back()` 返回日历。✅ **不切任何视图/Tab**，事件块高度、步骤摘要、槽位高度立即变为新值。
2. **改名不改时长**：只改步骤名/任务包名 → 返回后事件块文字也立即更新。
3. **左侧面板入口**：从日历左侧任务包卡片进入详情 → 编辑 → 返回，同样即时刷新。
4. **任务包列表 Tab 回归**：编辑后列表卡片名称/步骤摘要仍正常刷新。
5. **删除任务包**：删除后关联日程级联移除，时间轴即时刷新。
6. **重启持久化回归**：编辑后重启应用，最新内容仍保留。

---

## 七、已知限制与遗留（Part 1）

1. **时间指示线 / 拖拽吸附精度**（`log_09` 已记录的既有问题）：`getTimeIndicatorOffset` 与 `snapTimeFromY` 仍用固定 `hourHeight` 累加，有事件撑高槽位时红色「现在」线会略偏。
2. **跨天导航的槽位高度**：`goToNextDay` / `goToPrevDay` 直接调用 `computeDayHourHeights()` 而不经 `loadData()`。
3. **观察到但未改**：`CalendarTab.timeTimer` 字段注释写着「aboutToDisappear 时清除」，但原代码未实现 `aboutToDisappear`（定时器从未被清除）。本次新增了 `aboutToDisappear` 用于退订监听器，但未顺带清定时器，遵循「外科手术式修改」。

> 注：以上第 1、2 点随 Part 2 需求 1 的绝对定位重构（移除动态高度数组、固定 `hourHeight`）已自然消解或改变，详见下文。

---

# Part 2 · 需求 1：事件块跨小时分隔线显示（绝对定位重构）

## 一、问题现状

改造前，事件块被「装」在 `startHour` 对应的单个槽位 `Column` 里（按 `startHour === hour` 过滤），事件块高度虽已按时间映射（`height = 总时长/60 × hourHeight`），但**跨小时事件会把它所在的槽位撑大**，导致该小时分隔线被撑开、整体错位，而不是让事件块正确覆盖到下一小时分隔线之上。同时为对齐而引入的动态槽位高度（`weekHourHeights` / `dayHourHeights`）也是「按事件块撑大槽位」的产物。

## 二、目标

- 事件块根据 `startHour` / `startMinute` 与总时长，用**绝对定位**精确覆盖在时间轴上，正确跨越小时分隔线。
- 分隔线（网格）位置固定，不随事件块的存在而变化。

## 三、方案

把时间轴渲染从「流式槽位」改为「固定网格背景层 + 绝对定位事件块层」：

```
Scroll
└─ Stack(alignContent: Top)
   ├─ Row
   │   ├─ 左侧时间标签列(36vp)：24 个标签，每行固定 hourHeight
   │   └─ 7 列日期栏（周） / 单列（日）
   │       └─ 每列是一个 Stack(alignContent: Top)
   │           ├─ 背景网格层：24 行固定 hourHeight，每行 Blank(3)+分割线
   │           └─ 事件块层：绝对定位 .position({x, y}) + .height(总时长/60×hourHeight)
   └─ 时间指示线（绝对覆盖）
```

- 垂直坐标：`top = (startHour×60 + startMinute) / 60 × hourHeight`，支持非整点开始。
- 高度：`height = 总时长/60 × hourHeight`，设最小高度（周 20 / 日 28）保证极短事件可见。
- 水平坐标：周视图每列独立 `Stack`，事件块 `x=0` 起、宽度 `calc(100%-2px)`，无需计算 7 列偏移。
- 网格层保留 log_09 的「分割线下移 3vp 对齐字形」方案（`Blank(3)` + 分割线）。
- 移除 `computeWeekHourHeights` / `computeDayHourHeights` 及 `weekHourHeights` / `dayHourHeights` 两个 `@State` —— 槽位高度恢复为标准 `hourHeight`。

## 四、文件变更清单

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/pages/CalendarTab.ets` | 时间轴重构（见下） |
| `entry/logs/log_10.md` | 本日志文件 |

### 详细变更（全部在 `CalendarTab.ets`）

1. **删除** `@State weekHourHeights` / `@State dayHourHeights`（动态高度数组不再需要）。
2. **删除** `computeWeekHourHeights()` / `computeDayHourHeights()` 两个方法，及其全部调用点（`loadData` / `buildWeekData` / `goToDayView` / `goToToday` / `goToPrevDay` / `goToNextDay` / `handleDrop`）。
3. **删除** `getHourEvents()` / `getEventsForDateAndHour()`（重构后无调用方）。
4. **新增** 两个定位辅助方法：
   ```typescript
   private eventBlockTop(evt, hourHeight): number {
     return (evt.startHour * 60 + evt.startMinute) / 60 * hourHeight;
   }
   private eventBlockHeight(evt, hourHeight, minHeight): number {
     return Math.max(getTotalDuration(evt.steps) / 60 * hourHeight, minHeight);
   }
   ```
5. **重写** `buildWeekContent()` / `buildDayContent()` 的时间轴主体：
   - 网格层：`ForEach(generateHourRange(...))` 渲染 24 行 `Column().height(hourHeight)`，行内 `Blank(3)+分割线`，底部 `.border({bottom:1})` 画 24:00 线。
   - 事件块层：`ForEach(getEventsForDate(dateStr))` 渲染事件块，`.position({x, y: eventBlockTop})` + `.height(eventBlockHeight)`，key 用 `${evt.id}-v${schedulesVersion}`（沿用需求 0 的刷新机制）。
   - 保留拖拽目标（`onDrop`/`onDragEnter`/`onDragLeave`）、点击事件块弹详情（`onClick`）、时间指示线。

## 五、结构对比

**改造前（流式槽位）**：事件块嵌在 `startHour` 槽位内，跨小时会把槽位撑大 → 分隔线错位。

**改造后（绝对定位）**：网格固定 `24×hourHeight`，事件块独立定位，`top`/`height` 直接由时间计算 → 跨小时正确、分隔线固定。

## 六、编译与测试

### 编译

```
hvigorw assembleHap --mode module -p module=entry@default -p product=default
```

结果：**BUILD SUCCESSFUL**。无新增错误，仅既有 `deprecated` 警告。

### 测试要点（手动）

1. **跨小时事件**：90 分钟任务包（如 15:00 起）→ 事件块正确覆盖 15:00~16:30 的分隔线，两条分隔线都不被撑开。
2. **非整点开始**：拖拽吸附到 15:30 → 事件块顶部落在半格位置。
3. **网格固定**：同一小时有无事件，该小时及之后所有分隔线位置不变。
4. **周视图**：跨小时事件在对应日期列内正确跨线，7 列网格各自对齐。
5. **需求 0 回归**：编辑任务包改时长 → 返回后事件块高度/位置即时刷新。
6. **拖拽排程回归**：拖任务包到时间轴 → 吸附时间正确、预览条正常、事件块落在正确位置。
7. **时间指示线**：红色「现在」线位置与固定网格对齐。
8. **对齐回归**：左侧时间标签与分割线仍对齐。

## 七、已知限制与遗留（Part 2）

1. **重叠事件视觉处理（待确认点）**：同一时段多个事件会**重叠渲染**。当前未做左右错开/并排，留待需求 3/4 或用户确认。
2. **非整点开始（已支持）**：`startMinute=30` 按公式直接落在半格，无需额外逻辑。
3. **拖拽吸附的 scrollOffset 恒为 0**：周/日视图 `onDrop` 里 `snapTimeFromY(y, 0, hourHeight)` 写死滚动偏移为 0（`scrollOffsetY` 字段从未被更新，属既有问题）。滚动后再拖拽，吸附时间会偏。
4. **`dayEvents` getter 疑似死代码**：`get dayEvents()` 仅被一处注释提及、无实际调用（本次未删，遵循「外科手术式修改」）。
5. **时间指示线偏移（需求 5）** 与 **分割线经过任务包变白（需求 6）**：两轮修复后仍未完全通过，已记入 `left_problem.md` 需求 5 / 需求 6，稍后再修。

## 八、追加修复（第一轮反馈，同日）

### 问题 1：事件块上边界与小时分隔线有 ~3vp 偏差

- **根因**：网格分割线用 `Blank(3)+分割线` 相对槽位顶部下移了 3vp（log_09 的 ascender 对齐方案），但事件块的 `top` 未加偏移，导致上边界比分割线高 3vp。
- **修复**：新增常量 `GRID_LINE_OFFSET = 3`，事件块 `top` 改为 `(startHour×60+startMinute)/60×hourHeight + GRID_LINE_OFFSET`，与分割线精确对齐。

### 问题 2：事件块遮住了小时分隔线，期望分割线在事件块上层

- **根因**：`Stack` 中后渲染的子组件在上层。原实现「网格先、事件块后」，故事件块盖住分割线。
- **修复**：交换渲染顺序——事件块先（下层）、网格后（上层），分割线盖在事件块上；网格加 `.hitTestBehavior(HitTestMode.None)` 让触摸穿透。

## 九、追加修复（第二轮反馈，同日）

### 问题 1：红色指示线（横线）不显示，只有红点 —— ✅ 已通过

- **根因**：`Divider` 的 `strokeWidth`「优先级低于 height，超过通用属性设置大小时按 height 裁切」。原 `buildTimeIndicator` 里 `Row().height(0)` + `Divider().strokeWidth(1)`，红线被 `height(0)` 裁切成 0 而不可见；红点 `Circle` 不是 Divider，不受影响。
- **修复**：重写 `buildTimeIndicator`——红线改用 `Row().height(1).backgroundColor('#FF3B30')`，整体用 `.position()` 绝对定位，替代 `Blank(offset)` + `Row().height(0)`。

### 问题 2：指示线 3vp 偏移 —— ❌ 未通过（记入 `left_problem.md` 需求 5）

- **已尝试**：指示线 y 位置加 `GRID_LINE_OFFSET`。
- **现状**：指示线（红线/红点）与小时分割线仍有视觉偏移，未完全对齐。

### 问题 3：小时分割线经过任务包时变白 —— ❌ 未通过（记入 `left_problem.md` 需求 6）

- **已尝试**：网格分割线从 `Divider().color('#E0E0E0')` 改为 `Row().height(1).backgroundColor('#E0E0E0')`。
- **现状**：分割线经过彩色任务包时仍变白。

### 涉及文件（第二轮）

- `entry/src/main/ets/pages/CalendarTab.ets`：重写 `buildTimeIndicator`；周/日视图网格分割线 `Divider` → `Row`。

### 编译

`hvigorw assembleHap ...` → **BUILD SUCCESSFUL**。期间修复一处 `@Builder` 不允许 `const` 局部变量声明的编译错误（把偏移计算内联进 `.position()`）。

---

## 十、关键结论

> **需求 0** 由两层原因叠加：一是刷新依赖 `onPageShow` 脆弱触发链，二是 `ForEach` 对稳定 key 复用旧 Item、不重建。两层都修（数据层通知 + `schedulesVersion` 强制重建）后从机制上消除。
>
> **需求 1** 的核心是把「事件块 = 槽位内的流式内容」改为「事件块 = 覆盖在固定网格上的绝对定位层」。事件块 `top`/`height` 完全由 `startHour`/`startMinute`/`steps` 计算，跨小时天然正确，分隔线不被撑开；动态高度数组被彻底移除，`hourHeight` 恢复为常量——这为需求 2（双指缩放：`hourHeight` 变为 `@State`）和需求 4（拉伸：拖动改 `top`/`height`）铺平了地基。
>
> 遗留两项（需求 5 指示线偏移、需求 6 分割线变白）已记入 `left_problem.md`，稍后再修。
