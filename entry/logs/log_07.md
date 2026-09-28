# 鸿蒙应用第七次开发日志

## 项目信息

- **项目名称**：StudyStream
- **开发日期**：2026-07-06
- **目标**：日历 Tab 优化 —— 周视图和日视图添加小时分割线（hh:mm | ——————）

---

## 一、本次改动总体目标

在 CalendarTab 的周视图和日视图中，为时间轴添加垂直分割线，实现 `hh:mm | ——————————` 的视觉效果：

1. **垂直分割线**：时间标签列（36vp）与内容列之间插入 `Divider().vertical(true)`，形成 `|` 分隔
2. **水平分割线对齐**：每小时的横向分割线顶对齐，与左侧时间标签文字平齐，结合垂直分割线形成完整的分割效果

---

## 二、文件变更清单

### 修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/pages/CalendarTab.ets` | 周视图和日视图各添加一条垂直分割线（时间标签与内容之间） |
| `entry/logs/log_07.md` | 本日志文件 |

### 未修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/models/TaskPackage.ets` | 无需改动 |
| `entry/src/main/ets/models/ScheduledEvent.ets` | 无需改动 |
| `entry/src/main/ets/pages/Index.ets` | 无需改动 |
| `entry/src/main/ets/pages/TaskPackageTab.ets` | 无需改动 |
| `entry/src/main/ets/pages/CreatePackage.ets` | 无需改动 |
| `entry/src/main/ets/pages/PackageDetailDialog.ets` | 无需改动 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 无需改动 |
| `entry/src/main/resources/base/profile/main_pages.json` | 无需改动 |

---

## 三、详细变更说明

### 最终方案（第三版）

#### A. 移除垂直分割线 `|`

用户反馈：灰底时间标签区与白底内容区已有天然色块区分，无需额外垂直分割线。

移除两处时间标签 Column 上的 `.border({ width: { right: 1 }, color: '#D0D0D0' })`。

#### B. 小时标签与分割线对齐修复（核心）

**问题根因**：时间标签 Column 和内容 Column 使用不同的高度体系：
- 时间标签每槽位 = `DAY_HOUR_HEIGHT`（固定 60vp）
- 内容每槽位 = `Divider(1vp)` + `Blank(60vp)` = 61vp（或有事件时更高）

每小时内容区比标签区多 1vp，24 小时累计偏移 23vp。只有首尾对齐，中间全部错位。

**修复方案**：引入动态高度数组，让时间标签和内容区使用**完全相同**的高度值。

```
时间标签槽位高度 = weekHourHeights[hour] / dayHourHeights[hour]
                          ‖ (完全相同)
内容槽位高度     = weekHourHeights[hour] / dayHourHeights[hour]
```

**新增状态字段**：
```typescript
@State weekHourHeights: number[] = [];  // 周视图 24 个槽位高度
@State dayHourHeights: number[] = [];   // 日视图 24 个槽位高度
```

**计算逻辑**（`computeWeekHourHeights` / `computeDayHourHeights`）：
```
对于每个小时 h (0-23):
  maxH = STANDARD_HOUR_HEIGHT  (周=42vp, 日=60vp)
  遍历该小时所有事件:
    eventH = totalDuration / 60 × HOUR_HEIGHT
    maxH = max(maxH, eventH)
  heights[h] = maxH
```

周视图取所有 7 天中同一小时的最大事件高度，确保所有列对齐。

**触发时机**：

| 操作 | 周视图重算 | 日视图重算 |
|------|:---:|:---:|
| `loadData()` | ✅ (via `buildWeekData`) | ✅ |
| `goToPrevWeek()` / `goToNextWeek()` | ✅ (via `buildWeekData`) | - |
| `goToPrevDay()` / `goToNextDay()` | - | ✅ |
| `goToToday()` | ✅ (via `buildWeekData`) | ✅ |
| `goToDayView(dateStr)` | - | ✅ |

**使用方式**（以周视图时间标签为例）：
```typescript
// 改前
Column { Text("09:00") + Blank() }.height(WEEK_HOUR_HEIGHT)  // 固定 42vp

// 改后
Column { Text("09:00") + Blank() }
  .height(this.weekHourHeights[hourIndex] > 0 ?
    this.weekHourHeights[hourIndex] : WEEK_HOUR_HEIGHT)
// 内容区空槽位使用同样的 weekHourHeights[hour]，保证对齐
```

### 涉及代码位置

| 位置 | 行号 | 改动 |
|------|------|------|
| 状态声明 | 133-145 | 新增 `@State weekHourHeights` 和 `@State dayHourHeights` |
| `computeWeekHourHeights()` | 438-456 | 新增：遍历 7 天 × 24 小时，取最大事件高度 |
| `computeDayHourHeights()` | 464-480 | 新增：遍历选中日期 24 小时，取最大事件高度 |
| `buildWeekData()` | 428 | 末尾新增 `this.computeWeekHourHeights()` |
| `loadData()` | 271 | 末尾新增 `this.computeDayHourHeights()` |
| `goToDayView()` | 561 | 新增 `this.computeDayHourHeights()` |
| `goToToday()` | 617 | 新增 `this.computeDayHourHeights()` |
| `goToPrevDay()` | 661 | 新增 `this.computeDayHourHeights()` |
| `goToNextDay()` | 676 | 新增 `this.computeDayHourHeights()` |
| 周视图时间标签 | 1528-1529 | `WEEK_HOUR_HEIGHT` → `this.weekHourHeights[hourIndex]` |
| 周视图空槽位 | 1603-1604 | `WEEK_HOUR_HEIGHT` → `this.weekHourHeights[hour]` |
| 日视图时间标签 | 1745-1746 | `DAY_HOUR_HEIGHT` → `this.dayHourHeights[hour]` |
| 日视图空槽位 | 1830-1831 | `DAY_HOUR_HEIGHT` → `this.dayHourHeights[hour]` |
| 两处 border | - | 移除 `.border({ width: { right: 1 }, color: '#D0D0D0' })` |

---

## 四、当前完整文件结构

```
entry/src/main/ets/
├── models/
│   ├── TaskPackage.ets        [不变]
│   └── ScheduledEvent.ets     [不变]
├── pages/
│   ├── Index.ets              [不变]
│   ├── TaskPackageTab.ets     [不变]
│   ├── CalendarTab.ets        [修改] 周/日视图添加垂直分割线
│   ├── CreatePackage.ets      [不变]
│   └── PackageDetailDialog.ets[不变]
├── entryability/
│   └── EntryAbility.ets       [不变]
└── entrybackupability/
    └── EntryBackupAbility.ets [不变]
```

---

## 五、运行测试指南

### 操作流程

1. 启动应用 → 切换到底部 **📅 日历** Tab
2. 点击右上角 **「周」** 按钮 → 切换到周视图
3. 观察：
   - 左侧时间标签 "00:00" ~ "23:00"
   - 时间标签右侧有一条垂直细线（`|`）
   - 每小时有一条横向分割线，与时间标签平齐
   - 形成 `09:00 | ——————————` 的视觉效果
4. 点击右上角 **「日」** 按钮 → 切换到日视图
5. 观察：日视图同样有垂直分割线 + 水平分割线

### 预期效果

- ✅ 周视图：时间标签与内容之间有垂直分割线 `|`
- ✅ 日视图：时间标签与内容之间有垂直分割线 `|`
- ✅ 垂直分割线高度随内容自动适配
- ✅ 水平分割线（已有）与垂直分割线交汇，形成网格状布局
- ✅ 两视图风格统一，视觉一致

---

## 六、已知限制与后续改进

（待补充）

---

## 七、关键技术点回顾

### 1. 时间轴对齐的核心原理

```
时间标签 Column                内容 Column
┌─────────────────┐           ┌─────────────────┐
│ 00:00           │ ← 顶对齐 → │ —————————————— │
│                 │           │                 │
│ 高度 = H[0]     │           │ 高度 = H[0]     │  ← 必须相等！
├─────────────────┤           ├─────────────────┤
│ 01:00           │ ← 顶对齐 → │ —————————————— │
│                 │           │                 │
│ 高度 = H[1]     │           │ 高度 = H[1]     │  ← 必须相等！
├─────────────────┤           ├─────────────────┤
│ ...             │           │ ...             │
```

**对齐条件**：两个 Column 中相同索引的槽位高度必须相同（`H[i]`）。

**破坏对齐的原因**：
- Divider 占 1vp 布局空间（内容 61vp vs 标签 60vp）
- 事件块高度 ≠ 标准小时高度（如 90min → 63vp vs 42vp）

**修复方法**：预计算 `H[i]` 数组，两边共用。

### 2. 动态槽位高度算法

```typescript
// 周视图：取 7 天中同一小时的最大值
private computeWeekHourHeights(): void {
  for (let h = 0; h < 24; h++) {
    let maxH = WEEK_HOUR_HEIGHT;  // 默认 42vp
    for (const day of this.weekDays) {
      for (const evt of getEventsForDateAndHour(day, h)) {
        const eh = getTotalDuration(evt.steps) / 60 * WEEK_HOUR_HEIGHT;
        maxH = Math.max(maxH, eh);  // 取最大值
      }
    }
    heights.push(maxH);
  }
}

// 日视图：只取选中日期的事件
private computeDayHourHeights(): void {
  for (let h = 0; h < 24; h++) {
    let maxH = DAY_HOUR_HEIGHT;  // 默认 60vp
    for (const evt of getHourEvents(h)) {
      const eh = getTotalDuration(evt.steps) / 60 * DAY_HOUR_HEIGHT;
      maxH = Math.max(maxH, eh);
    }
    heights.push(maxH);
  }
}
```

### 3. 防御性 fallback

```typescript
.height(this.weekHourHeights[hour] > 0 ?
  this.weekHourHeights[hour] : WEEK_HOUR_HEIGHT)
```

数组为空或值异常时回退到标准高度，避免高度为 0 导致不可见。

### 4. 高度重算触发链

```
用户操作 → 导航方法 → computeXXXHourHeights() → @State 更新 → UI 刷新
                                          ↓
                             时间标签 + 内容列同步更新高度
```

---

## 八、日志更新记录

| 时间 | 更新内容 |
|------|---------|
| 2026-07-06 15:00 | 初始化日志文件 |
| 2026-07-06 15:10 | 第一版：Divider().vertical(true) + Row().height(0) 包裹水平分割线 |
| 2026-07-06 15:30 | 第二版：border 替代垂直 Divider + 简化水平 Divider 渲染 |
| 2026-07-06 16:00 | 第三版：移除垂直分割线 + 动态槽位高度修复对齐问题 |
| 2026-07-06 16:45 | 第四版：重构为 Stack 逐小时 Row（标签+分割线同行）—— height(0) 导致标签消失，废弃 |
| 2026-07-06 17:00 | 第五版：回退 Row-based 布局 + padding |
| 2026-07-06 17:20 | 第六版：`.border({ top: 1 })` 替代 Divider —— 漂移未解决（仅 17:00 对齐） |
| 2026-07-06 17:50 | 第七版：Divider 方案 + 高度精确计算 `maxH + 1` + Blank 减 1vp |
| 2026-07-06 18:10 | 第八版（当前）：分隔线下移 1px（content padding: `top:5, bottom:3`）；新增 24:00（WEEK_END_HOUR=25, ForEach 0..25） |

### 第七版核心公式

```
computeWeekHourHeights:  heights[h] = maxContentHeight + 1   ( +1 = Divider 高度)
computeDayHourHeights:   heights[h] = maxContentHeight + 1

时间标签槽位:  Column { Text + Blank }.height(heights[h])          = H
内容槽位:      Column { Divider(1vp) + Blank(H-1) }.height(auto)   = 1 + (H-1) = H

→ 两边槽位高度精确相等 ✅
```

| 组件 | 周视图 | 日视图 |
|------|:---:|:---:|
| 时间标签列 padding | `top:4, bottom:4` | `top:4, bottom:4` |
| 内容列 padding | `top:4, bottom:4` | `top:4, bottom:4` |
| 标签槽位高度 | `weekHourHeights[h]` | `dayHourHeights[h]` |
| 内容槽位高度 | `1 + (weekHourHeights[h] - 1)` | `1 + (dayHourHeights[h] - 1)` |
| 结果 | **= weekHourHeights[h]** ✓ | **= dayHourHeights[h]** ✓ |

---

## 九、第十版：周/日视图拖拽 + 预览条 + 自动吸附 (2026-07-08)

### 改动目标

1. **周视图和日视图支持拖拽安排**：从左侧面板拖拽任务包到时间轴区域，自动吸附时间并创建日程
2. **底部预览条**：拖拽时在日历底部显示半透明预览（日期 + 吸附时间 + 任务包名）
3. **自动吸附到半小时**：根据手指 Y 坐标 + 滚动偏移量计算时间，吸附到最近整点/半点
4. **ScheduledEvent 新增 endHour/endMinute**：记录日程结束时间

### 文件变更

| 文件 | 说明 |
|------|------|
| `models/ScheduledEvent.ets` | 新增 `endHour`、`endMinute` 字段；导出 `getTotalDuration()` |
| `pages/CalendarTab.ets` | 新增拖拽状态/吸附算法/预览Builder/Scroll偏移追踪/拖拽目标绑定 |

### 核心实现

#### 自动吸附算法

```
effectiveY = getY() + scrollOffset - topPadding
hourFloat  = effectiveY / HOUR_HEIGHT
snappedMin = round(hourFloat × 60 / 30) × 30   // 吸附到半小时
hour       = floor(snappedMin / 60)
minute     = snappedMin % 60
```

#### 拖拽流程

```
onDragStart → 记录 pkgId + 时长 + 名称 + 颜色
    ↓
onDragMove → snapTimeFromY() → 更新预览 @State
    ↓
onDrop → snapTimeFromY() → handleDrop(date, pkgId, hour, minute)
    ↓
handleDrop → 计算 endHour/endMinute → 创建 ScheduledEvent → 刷新 UI
```

#### 预览条 (buildDragPreviewBar)

- 半透明 `#CC333333` 背景，白色文字，圆角 8vp
- 格式：`"6月30日 15:00 - 15:45 健身包"`
- 右侧颜色指示条
- Stack 底部叠加，`hitTestBehavior(None)` 不拦截触摸

#### 涉及代码位置

| 位置 | 内容 |
|------|------|
| `ScheduledEvent.ets:31-36` | endHour/endMinute 字段 |
| `ScheduledEvent.ets:40-47` | getTotalDuration 导出 |
| `CalendarTab.ets:127-145` | 拖拽预览 @State 变量 |
| `CalendarTab.ets:755-768` | handleDragStart 扩展 |
| `CalendarTab.ets:825-915` | handleDrop 支持时间参数 + endTime |
| `CalendarTab.ets:925-1025` | snapTimeFromY + handleDragMove/DropInTimeAxis |
| `CalendarTab.ets:1350-1410` | buildDragPreviewBar Builder |
| `CalendarTab.ets:1707 / 1925` | Scroll onScroll 偏移追踪 |
| `CalendarTab.ets:1795-1810` | 周视图 7 列拖拽目标 |
| `CalendarTab.ets:2028-2042` | 日视图内容列拖拽目标 |
| `CalendarTab.ets:1044-1068` | build() Stack 包装预览条 |

### 已知限制

- 月视图拖拽暂未加入预览条
- `endHour`/`endMinute` 跨日使用 `% 24` 截断
