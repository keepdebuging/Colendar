# 鸿蒙应用第三次开发日志

## 项目信息

- **项目名称**：StudyStream
- **开发日期**：2026-06-29
- **目标**：完善 CalendarTab 日历组件 —— 代码结构重组、交互增强、性能优化

---

## 一、本次改动总体目标

对第二次的 CalendarTab 日历组件进行一轮"修整式"完善，解决声明顺序、拖拽传递、视觉区分、性能和导航便利性等方面的 6 个问题。不改动数据模型或其他页面。

---

## 二、文件变更清单

### 修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/pages/CalendarTab.ets` | 代码重组 + 今天按钮 + 填充格视觉区分 + 日程查询 Set 优化 + 拖拽数据通道完善 |

### 新建文件

| 文件 | 说明 |
|------|------|
| `entry/logs/log_03.md` | 本日志文件 |

### 未修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/models/TaskPackage.ets` | 无需改动 |
| `entry/src/main/ets/models/ScheduledEvent.ets` | 无需改动（其 `getDatesWithEvents()` 被 CalendarTab 新代码利用） |
| `entry/src/main/ets/pages/Index.ets` | 无需改动 |
| `entry/src/main/ets/pages/TaskPackageTab.ets` | 无需改动 |
| `entry/src/main/ets/pages/CreatePackage.ets` | 无需改动 |
| `entry/src/main/resources/base/profile/main_pages.json` | 无需改动 |

---

## 三、详细变更说明

### 1. 代码结构重组

**问题**：原文件成员声明顺序松散，`@State activeDragPkgId` 在第 633 行声明，却在第 219 行和 626 行被使用；计算属性、生命周期方法、处理函数和 UI Builder 交错分布。

**改动**：按规范顺序重新排列所有成员：

```
@Component struct CalendarTab
  ├── @Prop 声明
  ├── @State 声明（activeDragPkgId 移入此处）
  ├── 私有字段（eventsDateSet）
  ├── 计算属性（get dayEvents / getHourEvents / monthLabel）
  ├── 生命周期（aboutToAppear）
  ├── 数据加载（loadData / refreshEventsDateSet）
  ├── 日历计算（formatDateStr / buildCalendar）
  ├── 月份导航（goToPrevMonth / goToNextMonth / goToToday）
  ├── 日程标记（hasEventsOnDate / getEventsForDate）
  ├── 拖拽处理（handleDragStart / handleDragEnter / handleDragLeave /
  │            handleDrop / handleDropByEvent / backToMonthView）
  ├── UI 构建入口（build）
  ├── 月视图（buildMonthView @Builder）
  ├── 辅助方法（isCurrentMonthToday / isWeekend / formatHour）
  └── 日视图（buildDayView @Builder）
```

---

### 2. 新增「今天」快速跳转按钮

**问题**：月份导航只有 ← → 箭头，用户浏览到其他月份后无法一键返回。

**改动**：

- 新增 `goToToday()` 方法：读取系统当前日期，重置 `currentYear` 和 `currentMonth`，刷新日期集合并重建日历
- 新增 `isCurrentMonthToday()` 辅助方法：判断当前显示的月份是否是今天所在月份
- 在导航栏中插入「今天」Button：浅蓝背景 (`#EBF5FF`)、圆角 12vp、当前已是本月时置灰 (`opacity: 0.3`, `enabled: false`)

**导航栏新布局**：
```
〈  今天  2026年 6月  〉
```

---

### 3. 填充格视觉区分

**问题**：上月/下月补位的空白格 (`isCurrentMonth === false`) 与当月空格外观完全一致，且响应拖拽事件，容易让用户困惑。

**改动**：

- 当月格子背景保持白色 (`#FFFFFF`)，非当月填充格设为浅灰色 (`#F0F0F0`)
- 拖拽高亮覆盖层增加 `cell.isCurrentMonth` 条件，填充格不再显示高亮效果
- 底层安全：`handleDropByEvent` 中 `if (!dateStr) return;` 的双重保护保持不变

---

### 4. 日程查询性能优化

**问题**：`hasEventsOnDate()` 在 42 个格子中逐一调用，每次调用都遍历全量 `schedules` 数组做 `.some()`，复杂度 O(42 × N)。

**改动**：

- 新增 `private eventsDateSet: Set<string>` 字段，缓存当月有日程的日期集合
- 新增 `refreshEventsDateSet()` 方法，调用 `scheduleStore.getDatesWithEvents(year, month)` 填充 Set
- 在 `loadData()`、月份切换 (`goToPrevMonth` / `goToNextMonth` / `goToToday`)、拖拽放下 (`handleDrop`)、返回月视图 (`backToMonthView`) 中均同步刷新 Set
- `hasEventsOnDate()` 重写为 `this.eventsDateSet.has(dateStr)` —— **O(1) 替代 O(N)**

---

### 5. 完善拖拽数据传递

**问题**：`onDragStart` 中有注释 "通过 event.setData 将 packageId 传递给 drop 目标"，但从未实际调用。整个拖拽链路仅依赖 `@State activeDragPkgId` 作为中转，在多拖拽并发等场景下不够可靠。

**改动**：

- **`onDragStart`**：实际调用 `event.setData({ uniformTypeDescriptor: 'general.plain-text', data: pkg.id })`，将 packageId 写入系统拖拽数据通道
- **`handleDropByEvent`**：改为接收 `DragEvent` 参数；优先通过 `event.getData()` 提取 packageId（类型守卫 `typeof raw === 'string'` 安全窄化），仅当系统通道无数据时回退到 `@State activeDragPkgId`
- **`onDrop` 回调**：传递 `event` 对象给 `handleDropByEvent`

**数据流**：
```
onDragStart
  ├── event.setData({ data: pkg.id })  ← 主通道（系统级）
  └── this.activeDragPkgId = pkg.id    ← 后备通道（@State）

onDrop
  └── handleDropByEvent(dateStr, event)
        ├── event.getData() → 提取 pkgId  ← 优先
        └── this.activeDragPkgId           ← 后备
              └── handleDrop(dateStr, pkgId)
```

---

## 四、技术要点回顾

### Set 预计算模式
```typescript
// loadData / 月份切换 / drop / backToMonthView 中统一调用
private refreshEventsDateSet(): void {
  this.eventsDateSet = scheduleStore.getDatesWithEvents(
    this.currentYear, this.currentMonth
  );
}

// O(1) 查找替代 O(N) 遍历
hasEventsOnDate(dateStr: string): boolean {
  if (!dateStr) return false;
  return this.eventsDateSet.has(dateStr);
}
```

### 拖拽双通道数据传递
```typescript
// 发送端：系统通道 + 状态后备
.onDragStart((event: DragEvent) => {
  this.handleDragStart(pkg);
  event.setData({ uniformTypeDescriptor: 'general.plain-text', data: pkg.id });
})

// 接收端：系统通道优先，状态后备
handleDropByEvent(dateStr: string, event: DragEvent): void {
  let pkgId = '';
  const dragData = event.getData();
  if (dragData !== null) {
    const raw = dragData['general.plain-text'];
    if (typeof raw === 'string') pkgId = raw;
  }
  if (!pkgId && this.activeDragPkgId) pkgId = this.activeDragPkgId;
  if (pkgId) { this.handleDrop(dateStr, pkgId); this.activeDragPkgId = ''; }
}
```

---

## 五、验证方式

1. DevEco Studio 编译无报错
2. 月份导航正常：← → 切换月份，「今天」按钮一键跳回当月
3. 当前已是本月时「今天」按钮置灰不可点击
4. 当月格子白色背景，非当月填充格浅灰背景
5. 任务包拖拽到日期格子 → 创建日程 → 自动切换到日视图
6. 已安排日程的日期显示正确颜色的标记小圆点
7. 同一任务包不能在同一日期重复安排（防重复检测仍生效）

---

## 六、后续可改进项

- [ ] 拖拽预览使用自定义半透明样式（当前为系统默认卡片截图）
- [ ] 日视图支持拖拽调整事件到不同小时
- [ ] 数据持久化（关系型数据库 RDB 或 Preferences）
- [ ] 用户自定义任务包颜色
- [ ] 月视图支持滑动切换月份
- [ ] 周视图支持
