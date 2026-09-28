# 鸿蒙应用第二次开发日志

## 项目信息

- **项目名称**：StudyStream
- **开发日期**：2026-06-29
- **目标**：重构应用结构，实现日历视图、拖拽排程和底部导航

---

## 一、本次改动总体目标

将第一次的"单页应用"升级为带底部 Tab 导航的多视图应用：

1. **架构重构**：引入 `Tabs` 底部导航栏，整合任务包列表和日历总览两个视图
2. **日历月视图**：自定义日历组件，支持月份切换，显示日程标记
3. **拖拽排程**：从任务包卡片拖拽到日历日期格子，自动创建日程安排
4. **日视图**：拖拽完成后自动切换到 24 小时时间轴日视图
5. **视觉升级**：任务包卡片使用彩色主题，统一配色体系

---

## 二、文件变更清单

### 新建文件

| 文件 | 行数 | 说明 |
|------|------|------|
| `entry/src/main/ets/models/ScheduledEvent.ets` | ~120 | 日程安排数据模型 + 全局仓库单例 |
| `entry/src/main/ets/pages/TaskPackageTab.ets` | ~160 | Tab 1：彩色卡片式任务包列表 |
| `entry/src/main/ets/pages/CalendarTab.ets` | ~700 | Tab 2：日历总览页（核心，含拖拽和日视图） |

### 修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/models/TaskPackage.ets` | 新增 `color` 字段、`PACKAGE_COLORS` 调色板、`getNextColor()` 工具函数 |
| `entry/src/main/ets/pages/Index.ets` | 从单页改写为 `Tabs` 容器，整合两个子 Tab |
| `entry/src/main/ets/pages/CreatePackage.ets` | 保存时自动分配主题色 |

### 未修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/entryability/EntryAbility.ets` | 应用入口，无需改动 |
| `entry/src/main/module.json5` | 模块配置，无需改动 |
| `entry/src/main/resources/base/profile/main_pages.json` | 路由配置，无需改动（Tab 子页面通过 @Component 嵌入，不需要单独注册） |
| `AppScope/app.json5` | 应用级配置，无需改动 |
| `build-profile.json5` | 构建配置，无需改动 |

---

## 三、每个文件的主要功能描述

### 1. `models/TaskPackage.ets`（修改）

**新增内容**：
- `PACKAGE_COLORS` 数组：8 种预设主题色（橙、蓝、绿、红、紫、黄、天蓝、粉）
- `getNextColor(existingCount)` 函数：按创建顺序循环分配颜色
- `TaskPackage.color` 字段：每个任务包存储其主题色
- `TaskStore.getPackageById(id)` 方法：按 ID 查找任务包

**配色体系**：
```
橙色 #FF9500 → 健身运动
蓝色 #007AFF → 学习阅读
绿色 #34C759 → 家务清洁
红色 #FF3B30 → 紧急重要
紫色 #AF52DE → 兴趣创意
黄色 #FFCC00 → 休闲娱乐
天蓝 #5AC8FA → 日常工作
粉色 #FF6482 → 个人护理
```

### 2. `models/ScheduledEvent.ets`（新建）

**接口定义**：
- `ScheduledEvent`：包含 `id`、`date`（YYYY-MM-DD）、`packageId`、`packageName`、`color`、`startHour`、`startMinute`、`steps`

**单例仓库**：
- `ScheduleStore`：管理所有日程安排
  - `addEvent()` — 添加日程
  - `getEventsByDate(dateStr)` — 按日期查询
  - `isPackageScheduledOnDate()` — 防重复检测
  - `getDatesWithEvents(year, month)` — 月视图标记用

### 3. `pages/Index.ets`（重写）

**功能**：
- 使用 `Tabs({ barPosition: BarPosition.End })` 创建底部导航栏
- 两个 Tab：📋 任务包（Tab 0）、📅 日历（Tab 1）
- 默认显示 Tab 1（`index: 1`）
- `onPageShow()` 和 `onChange()` 时递增 `refreshTrigger`，通知子组件刷新

**数据流**：
```
Index.ets (refreshTrigger)
  ├── TaskPackageTab (@Prop refreshTrigger → @Watch loadData)
  └── CalendarTab (@Prop refreshTrigger → @Watch loadData)
```

### 4. `pages/TaskPackageTab.ets`（新建）

**功能**：
- 彩色卡片式任务包列表（替换第一次的简单文本列表）
- 每张卡片：主题色背景 + 白色文字 + 名称加粗 + 步骤摘要 + 步骤数量
- 步骤摘要示例："锻炼 20分钟 · 休息 5分钟 · 反思 10分钟"
- 保留右下角悬浮 "+" 按钮
- 空状态提示："暂无任务包，点击右下角 + 号创建"

**关键代码模式**：
- `@Prop @Watch('loadData')`：响应父组件传入的刷新信号
- `.maxLines(3).textOverflow(TextOverflow.Ellipsis)`：长文本截断

### 5. `pages/CalendarTab.ets`（新建）⭐ 核心

这是本次最复杂的文件，约 700 行。分为以下几个区域：

#### 5a. 双列布局
```
Row {
  Column (width: 30%)    ← 左侧：拖拽源
  Divider (vertical)
  Column (width: 70%)    ← 右侧：日历
}
```

#### 5b. 左侧面板：可拖拽任务包卡片
- 每个卡片显示名称、步骤列表和"长按拖拽 →"提示
- `.draggable(true)` + `.onDragStart()` 激活拖拽
- 拖拽时记录 `activeDragPkgId`（被拖拽的任务包 ID）

#### 5c. 右侧面板：自定义月视图日历
- **月份导航**：左右箭头切换上/下月
- **星期标题行**：一/二/三/四/五/六/日（周末红色）
- **Grid 日期网格**：7 列 × 6 行 = 42 格
  - 每个有效日期显示日期数字
  - 今天：蓝色圆形背景
  - 有日程的日期：显示彩色小圆点标记（最多 3 个 + "+"）
  - 每个格子是拖拽目标：`.onDrop()` / `.onDragEnter()` / `.onDragLeave()`

#### 5d. 拖拽交互流程
```
1. 用户长按左侧任务包卡片
   → onDragStart → handleDragStart(pkg)
   → 记录 activeDragPkgId = pkg.id
   → 系统创建拖拽预览

2. 用户拖拽到右侧日历日期格子上方
   → onDragEnter → handleDragEnter(dateStr)
   → dropHighlightDate = dateStr
   → 格子显示蓝色半透明高亮 + 虚线边框

3. 用户松手
   → onDrop → handleDropByEvent(dateStr)
   → handleDrop(dateStr, activeDragPkgId)
   → 验证：防重复 + 自动吸附整点
   → 创建 ScheduledEvent → scheduleStore.addEvent()
   → 切换到日视图 (viewMode = 'day')
   → 显示成功 Toast
```

#### 5e. 日视图（24 小时时间轴）
- 当用户在月视图中拖放任务包后**自动切换**
- 顶部：返回按钮 + 日期标题 + 当日日程概览卡片
- 下方：24 行时间轴（00:00 → 23:00）
  - 有日程的小时：显示彩色事件卡（包名 + 步骤列表 + 开始时间）
  - 无日程的小时：灰色虚线

#### 5f. 自动吸附算法
```typescript
const currentHour = new Date().getHours();
const snapMinutes = new Date().getMinutes();
let snappedHour = currentHour;
if (snapMinutes >= 30) {
  snappedHour = (snappedHour + 1) % 24;  // 向上取整到下一个整点
}
```

### 6. `pages/CreatePackage.ets`（修改）

**改动**：保存时调用 `getNextColor(taskStore.packages.length)` 自动分配主题色。

```typescript
const newPackage: TaskPackage = {
  id: generateId(),
  name: this.packageName.trim(),
  steps: validSteps,
  color: getNextColor(taskStore.packages.length)  // ← 第二次新增
};
```

---

## 四、新增数据模型说明

### ScheduledEvent
| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `string` | 唯一标识 |
| `date` | `string` | 日期 "YYYY-MM-DD" |
| `packageId` | `string` | 关联任务包 ID |
| `packageName` | `string` | 任务包名称（冗余，加速显示） |
| `color` | `string` | 主题色（冗余，用于日历标记） |
| `startHour` | `number` | 开始小时 0-23 |
| `startMinute` | `number` | 开始分钟 0-59 |
| `steps` | `{name,duration}[]` | 步骤列表（冗余） |

### 数据关系图
```
TaskStore                    ScheduleStore
├── packages[]              ├── events[]
│   ├── TaskPackage         │   ├── ScheduledEvent
│   │   ├── id ←────────────│───│─── packageId
│   │   ├── name            │   ├── packageName (冗余)
│   │   ├── color ←─────────│───│─── color (冗余)
│   │   └── steps[]         │   ├── date
│   └── ...                 │   ├── startHour
                            │   ├── startMinute
                            │   └── steps[] (冗余)
                            └── ...
```

---

## 五、完整文件结构
```
entry/src/main/ets/
├── models/
│   ├── TaskPackage.ets        [修改] 数据模型 + 颜色系统
│   └── ScheduledEvent.ets     [新建] 日程安排模型
├── pages/
│   ├── Index.ets              [重写] Tab 容器（底部导航）
│   ├── TaskPackageTab.ets     [新建] Tab 1: 彩色卡片列表
│   ├── CalendarTab.ets        [新建] Tab 2: 日历 + 拖拽 + 日视图
│   └── CreatePackage.ets      [修改] 创建页（新增颜色分配）
├── entryability/
│   └── EntryAbility.ets       [不变]
└── entrybackupability/
    └── EntryBackupAbility.ets [不变]
```

---

## 六、运行测试指南

### 操作流程
1. 启动应用 → 默认显示 **📅 日历** Tab（月视图）
2. 点击底部 **📋 任务包** Tab → 看到空状态提示
3. 点击 **+** 按钮 → 进入创建页
4. 创建任务包（如"晨间运动"：跑步 20min + 拉伸 5min）→ 保存
5. 返回后看到彩色卡片（橙色背景）
6. 切换回 **📅 日历** Tab
7. 在左侧栏看到刚创建的任务包卡片
8. **长按卡片** → 拖拽到右侧日历某个日期格子上 → 松手
9. 看到"已安排"提示 → 日历**自动切换到日视图**
10. 日视图中显示该日程的详细信息
11. 点击"← 返回月视图"回到月视图 → 该日期显示橙色小圆点标记
12. 创建更多任务包（不同颜色），拖到不同日期，观察彩色标记

### 预期效果
- ✅ 底部有两个 Tab，默认显示日历
- ✅ 任务包列表显示彩色卡片
- ✅ 不同任务包有不同颜色
- ✅ 日历可以切换月份
- ✅ 今天有蓝色圆形标记
- ✅ 拖拽时日期高亮
- ✅ 松手后自动切换到日视图
- ✅ 日视图显示 24 小时时间轴
- ✅ 月视图日期显示彩色标记

---

## 七、已知限制与后续改进

### 拖拽体验
- [ ] 拖拽预览使用的是系统默认样式（卡片截图），不是自定义的半透明效果
- [ ] 无法在日视图中拖拽调整事件到具体小时（第三次任务）
- [ ] 长按触发拖拽的延迟由系统控制，约 300ms

### 日视图
- [ ] 时间轴行高固定为 56vp，长时间段的日程显示效果待优化
- [ ] 暂不支持跨日拖拽（日视图内部拖拽到不同小时）

### 日历
- [ ] 不支持滚动到不同月份（只能通过箭头逐月切换）
- [ ] 月视图格子较小，标记点显示有限（最多 3 个）

### 数据持久化
- [ ] 所有数据仍在内存中，应用关闭后丢失
- [ ] 后续可考虑引入关系型数据库（RDB）或 Preferences

### 颜色系统
- [ ] 任务包删除后，颜色不会重新分配
- [ ] 用户不能自定义颜色（后续可添加颜色选择器）

---

## 八、关键技术点回顾

### 1. Tabs 底部导航
```typescript
Tabs({ barPosition: BarPosition.End, index: this.currentTabIndex }) {
  TabContent() { /* 内容 */ }.tabBar(this.TabBarBuilder(...))
}
```

### 2. 自定义日历网格
```typescript
Grid() {
  ForEach(cells, (cell) => { GridItem() { /* 日期格子 */ } })
}
.columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
```

### 3. 拖拽系统
```typescript
// 源
.draggable(true)
.onDragStart((event) => { /* 记录被拖拽的数据 */ })

// 目标（共享状态通过 @State 传递）
.onDrop((event) => { /* 处理放下 */ })
.onDragEnter(() => { /* 高亮 */ })
.onDragLeave(() => { /* 取消高亮 */ })
```

### 4. @Watch 数据刷新模式
```typescript
@Prop @Watch('loadData') refreshTrigger: number = 0;
loadData(): void { /* 从全局仓库同步最新数据 */ }
```
