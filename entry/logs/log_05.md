# 鸿蒙应用第五次开发日志

## 项目信息

- **项目名称**：StudyStream
- **开发日期**：2026-07-04
- **目标**：UI 美化、数据刷新修复、日历面板交互优化

---

## 一、本次改动总体目标

在第四次迭代（月/周/日三视图）的基础上进行一轮精细化打磨：

1. **数据刷新修复**：解决编辑保存后列表不更新的问题
2. **任务包卡片美化**：右侧溢出修复、显示总时长
3. **详情弹窗美化**：编辑按钮改为键槽型、弹窗宽度适配
4. **日历面板交互优化**：点击空白收起、点击卡片弹出详情弹窗
5. **周视图溢出修复**：周日列被截断的问题
6. **编辑页标题居中修复**

---

## 二、文件变更清单

### 修改文件

| 文件 | 说明 |
|------|------|
| `models/TaskPackage.ets` | `TaskPackage` 接口新增 `_version` 字段；`addPackage` 初始化、`updatePackage` 自增 |
| `pages/Index.ets` | `refreshTrigger` 改为 `@Provide` 跨层级广播；子组件实例化不再传 prop |
| `pages/TaskPackageTab.ets` | `refreshTrigger` 改为 `@Consume`；卡片宽度适配 + 显示总时长；ForEach key 改用 id+version |
| `pages/CalendarTab.ets` | `refreshTrigger` 改为 `@Consume`；左侧面板添加详情弹窗；周视图列宽改用 `layoutWeight`；面板展开态点击空白可收起；ForEach key 改用 id+version |
| `pages/CreatePackage.ets` | `TaskPackage` 构造补齐 `_version` 字段；编辑模式标题居中修复 |
| `pages/PackageDetailDialog.ets` | 编辑按钮改为键槽型（✏ 编辑）；controller 默认值修复；弹窗宽度缩至 88%；`_version` 字段补齐 |
| `entry/logs/log_05.md` | 本日志文件 |

### 删除文件

| 文件 | 说明 |
|------|------|
| `pages/EditPackage.ets` | 已合并入 CreatePackage.ets 双模式 |

---

## 三、详细变更说明

### 1. 数据刷新修复（核心）

**问题**：编辑任务包保存后返回，主界面卡片和弹窗仍显示旧数据。

**根因分析**：
- 第一层：`@Prop` 在 `TabContent` 嵌套下可能不触发 `@Watch`
- 第二层：`ForEach` 用 `item.id` 做 key，编辑后 id 不变 → ForEach 复用旧 ListItem，跳过重建

**修复方案**：

**A. `@Provide` / `@Consume` 替代 `@Prop`**
```
Index (@Provide refreshTrigger)        ← 广播源
    ↓ 直接跨层级连接
TaskPackageTab (@Consume @Watch)       ← 总能收到
CalendarTab  (@Consume @Watch)         ← 总能收到
```

**B. `_version` 驱动 ForEach 重建**
| 操作 | `_version` | ForEach key | 效果 |
|------|:---:|---|---|
| 新建 | = 0 | `"id-v0"` | 正常渲染 |
| 编辑 | +1 | `"id-v1"` | **强制重建 ListItem** |

```typescript
// TaskPackage 接口新增
_version: number;

// updatePackage 中自增
updatedPkg._version = (this.packages[index]._version || 0) + 1;

// ForEach key 改用组合键
(item: TaskPackage) => `${item.id}-v${item._version}`
```

### 2. 任务包卡片美化

**A. 右侧溢出修复**
- 原因：卡片 `width('100%')` + `margin({ left: 16, right: 16 })` = 总宽度超出容器
- 修复：移除卡片水平 margin，改为 List 容器 `padding({ left: 12, right: 12 })`

**B. 总时长显示**
卡片底部从 `📋 3 个步骤` 变为 `📋 3 个步骤 · ⏱ 1小时15分钟`：
- 新增 `getTotalDuration()` 和 `formatDuration()` 辅助方法
- 步骤数为 0 时隐藏时长部分

### 3. 详情弹窗美化

**A. 编辑按钮改为键槽型**
- 之前：40×40 圆形按钮，仅 `✏️`
- 现在：32vp 高胶囊形，显示 `✏ 编辑`，主题色半透明背景

**B. 弹窗宽度适配**
- 之前：`width('100%')` → 弹窗撑满屏幕
- 现在：`width('88%')` → 左右各留 6% 空白

**C. controller 默认值修复**
- 之前：`builder: Column() {}` → 语法错误，106 个连锁报错
- 之后：`builder: this.placeholderBuilder` → 空 `@Builder` 方法作为占位符

### 4. 日历面板交互优化

**A. 点击空白收起面板**
- 展开态面板内层包装 `Column` 添加 `onClick → toggleLeftPanel()`
- 与右上角 → 按钮功能互补

**B. 点击卡片弹出详情弹窗**
- 左侧面板卡片新增 `onClick → showPackageDetail(pkg)`
- 复用 `PackageDetailDialog`，与 Tab1 行为一致
- 短按 = 弹窗，长按 = 拖拽，互不冲突
- 卡片 `onClick` 阻止事件冒泡，不会触发面板收起

### 5. 周视图溢出修复

**问题**：周日列约 1/3 被截断

**原因**：`width('calc((100% - 36px) / 7)')` 在嵌套容器中百分比基准不准确

**修复**：
- 日期标题行 7 列：`calc(...)` → `layoutWeight(1)`
- 时间轴 7 列：同上
- 时间轴 Row：新增 `padding({ right: 4 })` 避免贴边

### 6. 编辑页标题居中

**问题**：编辑模式下 "编辑任务包" 偏右

**原因**：右侧 `Blank().width(60)` 固定宽度，但左侧 "取消"（约 40vp）和 "← 返回"（约 60vp）宽度不一致

**修复**：左右各设 `width(72)` 对称容器，标题 `layoutWeight(1)` + `textAlign(Center)`

---

## 四、当前完整文件结构

```
entry/src/main/ets/
├── models/
│   ├── TaskPackage.ets        [修改] 新增 _version 字段
│   └── ScheduledEvent.ets     [不变]
├── pages/
│   ├── Index.ets              [修改] @Provide refreshTrigger
│   ├── TaskPackageTab.ets     [修改] @Consume + 卡片美化 + 总时长
│   ├── PackageDetailDialog.ets[修改] 键槽按钮 + 宽度 + _version
│   ├── CalendarTab.ets        [修改] @Consume + 面板弹窗 + 周视图修复
│   ├── CreatePackage.ets      [修改] _version + 标题居中
│   └── (EditPackage.ets)      [已删除]
├── entryability/
│   └── EntryAbility.ets       [不变]
└── entrybackupability/
    └── EntryBackupAbility.ets [不变]
```

---

## 五、关键技术点回顾

### 1. @Provide / @Consume 跨层级状态共享
```typescript
// 祖先
@Provide refreshTrigger: number = 0;

// 任意深度后代（绕过 TabContent 隔离）
@Consume @Watch('loadData') refreshTrigger: number = 0;
```

### 2. _version 驱动 ForEach 强制重建
```typescript
// 更新时版本号自增 → key 变化 → ForEach 创建新 ListItem
updatedPkg._version = old._version + 1;
// ForEach key: `${item.id}-v${item._version}`
```

### 3. layoutWeight 均分布局
```typescript
// 比 calc((100% - 36px) / 7) 更可靠
ForEach(weekDays, day => {
  Column() { /* 日期内容 */ }
    .layoutWeight(1)  // 7 列均分剩余空间
})
```

### 4. 点击 vs 长按互斥
```typescript
.draggable(true)
.onDragStart(...)   // 长按 → 拖拽
.onClick(...)       // 短按 → 详情弹窗，阻止冒泡到父级
```

### 5. ArkUI 装饰器规则
- 每个属性只能使用一个状态管理装饰器（`@Provide` 自带状态管理能力，无需叠 `@State`）
- 接口新增字段后必须全量搜索所有构造点逐一补齐
- `CustomDialogController.builder` 必须使用 `@Builder` 函数引用，不能直接传 UI 组件

---

## 六、当前时间指示线 (2026-07-04 追加)

### 功能
在周视图和日视图的时间轴上叠加一条红色"现在"指示线，随时间自动下移。

### 外观
```
    09:30 ●———————————————————————
```
- 36vp 时间标签区域内：红色时间文字 + 红色圆点（位于区域右边缘）
- 圆点右侧：红色细线延伸至屏幕右边缘
- 位置精确到分钟（09:30 在 09:00 和 10:00 正中间）

### 实现
- 新增 `@State nowHour` / `@State nowMinute`，每 60 秒 `setInterval` 刷新
- 新增 `@Builder buildTimeIndicator(hourHeight, startHour)` 可复用组件
- 日视图：`Stack` 叠加，选中日期为今天时显示
- 周视图：`Stack` 叠加，当前周包含今天且 `nowHour >= 6` 时显示
- `hitTestBehavior(HitTestMode.None)` 确保不拦截触摸/拖拽事件

### 涉及文件
| 文件 | 改动 |
|------|------|
| `pages/CalendarTab.ets` | 新增时间状态 + 定时器 + `buildTimeIndicator` Builder；日/周视图 Scroll 改为 Stack 叠加 |

---

## 七、周视图 24 小时 + 时间轴样式统一 (2026-07-04 追加)

### 周视图扩展为 0:00-24:00
`WEEK_START_HOUR` 从 6 改为 0，覆盖全天 24 小时。

### 时间标签与分割线改为 `hh:mm ——————` 平齐
**之前**：时间标签垂直居中于槽位，分割线在底部——文字浮于两线之间
**之后**：时间标签顶对齐 + 右对齐，分割线在顶部——文字与横线平齐

```
之前:                    之后:
  09:00                  09:00 ————————————
  ——————                 10:00 ————————————
  10:00
```

### 改动
| 位置 | 改动 |
|------|------|
| 日/周视图时间标签 | `textAlign(Center)` → 包裹 `Column{Text+Blank}` 顶对齐 + 右对齐 |
| 日视图小时槽位 | 底部虚线 → 顶部实线 `Row{Divider}` |
| 周视图小时槽位 | 底部淡线 → 顶部实线 `Row{Divider}` |

---

## 八、周视图显示周数 (2026-07-04 追加)

### 功能
周视图日期标题行左上角显示 "第XX周"（灰色小字，10px，`#AAAAAA`），位于 `周一`~`周日` 左侧的 36vp 区域内。

### 实现
- 新增 `weekNumberLabel` 计算属性：基于 `currentWeekStart`（周一）推算周四日期，按 ISO 周数公式计算
- 日期标题行 `Blank().width(36)` → `Text(this.weekNumberLabel).width(36)`
