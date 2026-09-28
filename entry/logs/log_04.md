# 鸿蒙应用第四次开发日志

## 项目信息

- **项目名称**：StudyStream
- **开发日期**：2026-06-30
- **目标**：完善 CalendarTab 日历组件 —— 视图切换（月/周/日）、平滑动画、非本月日期显示、导航扩展

---

## 一、本次改动总体目标

在第二次和第三次的基础上，对日历组件进行一轮重大功能扩展：

1. **视图切换按钮组**：在日历区域右上角添加「月」「周」「日」三个切换按钮
2. **周视图（全新）**：7 列时间轴布局，显示一周内每天的日程条
3. **日视图改进**：事件块高度与任务包总时长成正比
4. **平滑切换动画**：使用 `animateTo` + `Curve.EaseInOut` 实现视图间的柔和过渡
5. **非本月日期显示**：月视图网格中上月/下月填充格显示实际日期，使用浅灰色
6. **导航扩展**：周视图支持上一周/下一周，日视图支持前一天/后一天
7. **跨视图日期同步**：月/周/日视图间的选中日期保持一致

---

## 二、文件变更清单

### 修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/pages/CalendarTab.ets` | 全面重写：新增周视图/视图切换/动画/非本月日期/导航扩展 |
| `entry/logs/log_04.md` | 本日志文件 |

### 未修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/models/TaskPackage.ets` | 无需改动 |
| `entry/src/main/ets/models/ScheduledEvent.ets` | 无需改动 |
| `entry/src/main/ets/pages/Index.ets` | 无需改动 |
| `entry/src/main/ets/pages/TaskPackageTab.ets` | 无需改动 |
| `entry/src/main/ets/pages/CreatePackage.ets` | 无需改动 |
| `entry/src/main/resources/base/profile/main_pages.json` | 无需改动 |

---

## 三、详细变更说明

### 1. 视图切换按钮组

**位置**：在右侧日历区域（非全局）的导航栏中，标题右侧。

**样式**：
- 三个紧凑排列的文字按钮：「月」「周」「日」
- 当前激活的按钮：蓝色填充背景（`#007AFF`）+ 白色加粗文字
- 未激活的按钮：透明背景 + 灰色文字
- 整体包裹在灰色圆角容器中（`#F0F0F0`，圆角 6vp）

**实现**：通过 `@Builder buildViewSwitcher()` 方法构建，被月/周/日三个视图的导航栏共用。

```typescript
// 点击「月」按钮 → 切换到月视图
Text('月')
  .backgroundColor(this.viewMode === 'month' ? '#007AFF' : '#00000000')
  .fontColor(this.viewMode === 'month' ? '#FFFFFF' : '#666666')
  .onClick(() => { this.switchToView('month'); })
```

### 2. 三种视图详解

#### 2a. 月视图（保持兼容）

- 保持原有 7×6 网格布局，**拖拽功能完全保留**
- 第四次新增：点击日期格子可切换到该日期的日视图
- 第四次新增：非当月格子显示实际日期数字，用浅灰色（`#C0C0C0`）区分
- 非当月格子背景更淡（`#F5F5F5`），不响应拖放（但仍可点击进入日视图）

#### 2b. 周视图（全新）

- **布局**：左侧时间标签列（36vp宽）+ 右侧 7 列日期栏
- **时间范围**：6:00 - 24:00（18 小时），每小时占 42vp 高度，可滚动
- **日期标题行**：每列显示星期名 + 日期号（如"周一" + "6/22"），今天蓝色高亮
- **事件显示**：每个日程以彩色条块显示在对应小时行，包含任务包名称和步骤摘要
- **事件高度**：`总时长(分钟) / 60 × WEEK_HOUR_HEIGHT`，与时间轴比例一致
- **交互**：点击某天的标题或时间轴区域 → 切换到该天的日视图
- **背景**：今天的列有淡蓝色背景（`#F0F7FF`）
- **导航**：← → 箭头切换上一周/下一周

**核心代码结构**：
```typescript
Scroll() {
  Row() {
    Column() { /* 时间标签 06:00 ~ 24:00 */ }.width(36)
    ForEach(weekDays, day => {
      Column() {
        ForEach(hours, hour => {
          // 查找该小时的事件 → 渲染彩色块 或 空槽位
        })
      }.width('calc((100% - 36px) / 7)')
    })
  }
}
```

#### 2c. 日视图（改进）

- 保持 24 小时时间轴（0:00 - 23:59）
- 第四次改进：事件块高度与任务包总时长成正比
  - 每分钟 = `DAY_HOUR_HEIGHT / 60` vp（DAY_HOUR_HEIGHT = 60）
  - 60 分钟的事件 = 60vp 高，30 分钟 = 30vp 高
  - 最小高度 36vp（保证文字可读）
- 第四次改进：事件卡片使用浅色背景（颜色 + 白色混合，ratio=0.85）
- 第四次改进：导航栏支持前一天/后一天切换 + 「今天」按钮
- 第四次改进：可在月/周/日之间自由切换，日期保持同步

### 3. 平滑切换动画

使用鸿蒙的 `animateTo` 显式动画 API：

```typescript
switchToView(mode: string): void {
  if (mode === this.viewMode) return;  // 已在目标视图
  animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
    this.viewMode = mode;
    // 同步更新对应的导航状态（年份/月份/周起始日等）
  });
}
```

- `duration: 250`（250 毫秒）提供快速但不突兀的过渡
- `Curve.EaseInOut` 缓入缓出曲线，视觉柔和
- 在闭包内修改所有相关状态，ArkUI 自动计算属性插值

### 4. 非本月日期显示

**原逻辑**：`isCurrentMonth === false` 时，`date = -1, dateStr = ''`，格子为空。

**新逻辑**：
- 首部填充格：计算上月末尾的实际日期（如上月 31 天，则展示 29/30/31）
- 尾部填充格：计算下月开头的实际日期（如 1/2/3...）
- 这些日期的 `dateStr` 也是有效的 `"YYYY-MM-DD"` 字符串
- 字体颜色设为浅灰色 `#C0C0C0`
- 背景色设为更淡的 `#F5F5F5`
- **不响应拖放**，但可点击切换到日视图

### 5. 导航扩展

#### 月视图导航
```
〈  今天  2026年 6月  [月|周|日]  〉
```
- ← 上一个月，→ 下一个月

#### 周视图导航
```
〈  今天  6月22日 - 6月28日  [月|周|日]  〉
```
- ← 上一周，→ 下一周
- 「今天」按钮：当前周包含今天时置灰

#### 日视图导航
```
〈  今天  2026年6月30日 星期二  [月|周|日]  〉
```
- ← 前一天，→ 后一天
- 「今天」按钮：选中日期为今天时置灰

### 6. 跨视图日期同步

切换视图时，`selectedDateStr` 始终保留当前聚焦的日期：

| 切换 | 行为 |
|------|------|
| 月 → 日 | 使用 selectedDateStr（如果通过点击日期格子触发，则为该日期） |
| 月 → 周 | 用 selectedDateStr 所在周的周一作为周视图起始日 |
| 周 → 日 | 使用 selectedDateStr（如果通过点击某天触发） |
| 周 → 月 | 用 selectedDateStr 的年月设置月视图 |
| 日 → 月 | 用 selectedDateStr 的年月设置月视图 |
| 日 → 周 | 用 selectedDateStr 所在周的周一设置周视图 |

---

## 四、新增/修改的辅助方法

| 方法 | 说明 |
|------|------|
| `switchToView(mode)` | 视图切换核心方法，含 animateTo 动画 |
| `goToDayView(dateStr)` | 从月/周视图点击日期进入日视图 |
| `goToPrevWeek()` / `goToNextWeek()` | 周视图导航 |
| `goToPrevDay()` / `goToNextDay()` | 日视图导航 |
| `buildWeekData()` | 构建周视图的 7 天数据 |
| `buildViewSwitcher()` | 构建视图切换按钮组的 @Builder |
| `buildLeftPanel()` | 提取左侧任务包面板为独立 @Builder |
| `buildMonthContent()` / `buildWeekContent()` / `buildDayContent()` | 三种视图内容 @Builder |
| `getTotalDuration(steps)` | 计算任务包总时长（分钟） |
| `getEventsForDateAndHour(dateStr, hour)` | 按日期+小时查询日程 |
| `isCurrentWeekContainingToday()` | 周视图今天按钮判断 |
| `isSelectedDateToday()` | 日视图今天按钮判断 |
| `generateHourRange(start, end)` | 生成小时数组 |
| `mixWithWhite(hexColor, ratio)` | 颜色混合工具 |
| `static getMondayOf(date)` | 获取某日期所在周的周一 |

---

## 五、当前文件结构

```
entry/src/main/ets/
├── models/
│   ├── TaskPackage.ets        [不变] 数据模型 + 颜色系统
│   └── ScheduledEvent.ets     [不变] 日程安排模型
├── pages/
│   ├── Index.ets              [不变] Tab 容器（底部导航）
│   ├── TaskPackageTab.ets     [不变] Tab 1: 彩色卡片列表
│   ├── CalendarTab.ets        [重写] Tab 2: 日历 + 三视图 + 拖拽 + 动画
│   └── CreatePackage.ets      [不变] 创建页
├── entryability/
│   └── EntryAbility.ets       [不变]
└── entrybackupability/
    └── EntryBackupAbility.ets [不变]
```

---

## 六、运行测试指南

### 操作流程

1. 启动应用 → 默认显示 **📅 日历** Tab（月视图）
2. 观察月视图：上月/下月的填充格显示灰色日期数字
3. 点击右上角 **「周」** 按钮 → 平滑切换到周视图
4. 周视图显示当前周 7 天，每小时一行，有日程的显示彩色条块
5. 点击 **← →** 箭头切换上一周/下一周
6. 点击某天标题 → 切换到该天的日视图
7. 日视图显示 24 小时时间轴，事件块高度与时长成正比
8. 点击 **← →** 切换前一天/后一天
9. 点击 **「月」** 按钮 → 平滑返回月视图
10. 在月视图中拖拽任务包到日期格子 → 日程创建，日历出现彩色标记
11. 点击某个有日程的日期格子 → 进入该日期的日视图，看到刚创建的日程

### 预期效果

- ✅ 视图切换按钮（月/周/日）正常显示和切换
- ✅ 切换时有平滑的淡入淡出动画
- ✅ 月视图：非本月日期显示为灰色
- ✅ 月视图：拖拽任务包到日期格子功能正常
- ✅ 月视图：点击日期进入日视图
- ✅ 周视图：显示 7 天时间轴，日程彩色条块
- ✅ 周视图：← → 切换上一周/下一周
- ✅ 日视图：24 小时时间轴，事件高度与时长成正比
- ✅ 日视图：← → 切换前一天/后一天
- ✅ 三个视图间切换时，日期保持一致
- ✅ 「今天」按钮在各视图中正常工作

---

## 七、已知限制与后续改进

### 周视图
- [ ] 暂不支持从左侧面板拖拽任务包到周视图的日期列
- [ ] 时间轴精度为 1 小时，非整点开始的日程显示不够精确
- [ ] 事件块以小时槽位为单位排列，不支持精确到分钟的位置

### 日视图
- [ ] 暂不支持从左侧面板拖拽任务包到日视图
- [ ] 同一小时内多个事件的排列无重叠处理（当前垂直堆叠）

### 动画
- [ ] 视图切换使用 `animateTo` 整体过渡，不是每个元素独立的入场动画
- [ ] 日历网格重绘时无过渡效果（直接替换）

### 数据
- [ ] 所有数据仍在内存中，应用关闭后丢失
- [ ] 关系型数据库持久化留到后续迭代

---

## 八、关键技术点回顾

### 1. animateTo 动画
```typescript
animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
  this.viewMode = mode;
  // 在闭包内修改的所有 @State 都会产生动画过渡
});
```

### 2. 视图切换按钮组（条件样式）
```typescript
Text('月')
  .backgroundColor(this.viewMode === 'month' ? '#007AFF' : '#00000000')
  .fontColor(this.viewMode === 'month' ? '#FFFFFF' : '#666666')
  .fontWeight(this.viewMode === 'month' ? FontWeight.Bold : FontWeight.Normal)
```

### 3. 周视图数据结构
```typescript
interface WeekDayInfo {
  dateStr: string;    // "YYYY-MM-DD"
  dayOfWeek: number;  // 0=周一, 6=周日
  dayNumber: number;  // 1-31
  monthNumber: number; // 1-12
  isToday: boolean;
  dayName: string;    // "周一"~"周日"
}
```

### 4. 事件块高度计算
```typescript
// 周视图
.height(Math.max(totalDuration / 60 * WEEK_HOUR_HEIGHT, 20))
// 日视图
.height(Math.max(totalDuration / 60 * DAY_HOUR_HEIGHT, 36))
```

### 5. 非本月日期计算
```typescript
// 上月填充：dayNum 为 0, -1, -2... → prevMonthDays + dayNum
if (dayNum < 1) {
  const prevDay = prevMonthDays + dayNum;
  const dateStr = formatDateStr(prevYear, prevMonth, prevDay);
  // isCurrentMonth: false, fontColor: '#C0C0C0'
}
// 下月填充：dayNum 超过当月天数
else if (dayNum > daysInMonth) {
  const nextDay = dayNum - daysInMonth;
  const dateStr = formatDateStr(nextYear, nextMonth, nextDay);
}
```
