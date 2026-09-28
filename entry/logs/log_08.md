# 鸿蒙应用第八次开发日志

## 项目信息

- **项目名称**：StudyStream
- **开发日期**：2026-09-02
- **目标**：数据持久化（任务包与日程落盘）+ 数据一致性修复（编辑/删除任务包级联同步日程）

---

## 一、本次改动总体目标

前七次迭代中，任务包（`TaskStore`）与日程安排（`ScheduleStore`）都只保存在内存单例里，应用关闭后全部丢失，导致产品核心价值无法在真机上验证。本次引入基于用户首选项（Preferences）的持久化：

1. **持久化持有器**：封装 `@ohos.data.preferences` 的 KV 读写，统一管理沙箱内的持久化文件
2. **两个 store 接入落盘**：`TaskStore` 与 `ScheduleStore` 在增删改后自动写入，启动时自动恢复
3. **启动时恢复**：`EntryAbility.onCreate` 里初始化并恢复数据，早于首页加载

---

## 二、文件变更清单

### 新建文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/models/Persistence.ets` | 持久化持有器（Preferences 封装，同步读写） |
| `entry/logs/log_08.md` | 本日志文件 |

### 修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/models/TaskPackage.ets` | 新增 `persist()` / `restore()`；`addPackage` / `updatePackage` / `deletePackage` 末尾自动落盘 |
| `entry/src/main/ets/models/ScheduledEvent.ets` | 新增 `persist()` / `restore()`；`addEvent` / `removeEvent` 末尾自动落盘 |
| `entry/src/main/ets/entryability/EntryAbility.ets` | `onCreate` 里 `persistence.init()` + 两个 store 的 `restore()` |

### 未修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/pages/Index.ets` | 无需改动（数据刷新机制不变） |
| `entry/src/main/ets/pages/TaskPackageTab.ets` | 无需改动 |
| `entry/src/main/ets/pages/CalendarTab.ets` | 无需改动 |
| `entry/src/main/ets/pages/CreatePackage.ets` | 无需改动 |
| `entry/src/main/ets/pages/PackageDetailDialog.ets` | 无需改动 |
| `entry/src/main/resources/base/profile/main_pages.json` | 无需改动 |
| `AppScope/app.json5` | 无需改动 |
| `entry/src/main/module.json5` | 无需改动 |

---

## 三、详细变更说明

### 1. 持久化持有器 —— `models/Persistence.ets`（新建）

**职责**：把 Preferences 的获取与读写集中到一处，供两个 store 复用。核心考量是**避免循环依赖**——本模块不 import 任何 store，只提供通用的字符串读写能力，由 store 自己决定存什么 key、怎么序列化。

**关键 API 选择**：

| API | 版本 | 选择理由 |
|------|------|---------|
| `preferences.getPreferencesSync(context, { name })` | API 10+ | 同步获取实例，启动时一次性拿到，无异步时序问题 |
| `putSync(key, value)` | API 10+ | 同步写入内存缓存 |
| `getSync(key, defValue)` | API 10+ | 同步读取，带默认值 |
| `flushSync()` | API 14+ | 同步落盘，保证写入即持久化 |

本项目 `compatibleSdkVersion 6.1.0(23)`，远超上述接口所需版本，同步接口安全可用。

**导入**：`import { preferences } from '@kit.ArkData';`——与项目现有 `@kit.AbilityKit` 等系统 Kit 用法一致，无需在 `oh-package.json5` 声明依赖。

```typescript
class Persistence {
  private prefs: preferences.Preferences | null = null;

  public init(context: common.Context): void {
    if (this.prefs !== null) return;
    this.prefs = preferences.getPreferencesSync(context, { name: STORE_NAME });
  }

  public readString(key: string): string {
    if (this.prefs === null) return '';
    return this.prefs.getSync(key, '') as string;
  }

  public writeString(key: string, value: string): void {
    if (this.prefs === null) return;
    this.prefs.putSync(key, value);
    this.prefs.flushSync();
  }
}
```

### 2. TaskStore 接入持久化

**存储键**：`task_packages`，值为 `TaskPackage[]` 的 JSON 字符串。

```typescript
// addPackage / updatePackage / deletePackage 末尾统一调用
public persist(): void {
  persistence.writeString(TASK_PACKAGES_KEY, JSON.stringify(this.packages));
}

// 仅启动时调用一次
public restore(): void {
  const raw: string = persistence.readString(TASK_PACKAGES_KEY);
  if (raw !== '') {
    this.packages = JSON.parse(raw) as TaskPackage[];
  }
}
```

**改动点**：
- `addPackage()`：`push` 后 `this.persist()`
- `updatePackage()`：替换数组元素后 `this.persist()`
- `deletePackage()`：删除后，仅当实际发生删除（`changed === true`）才 `persist()`

> 删除时先判断 `changed` 再落盘，避免删除不存在的 id 时无谓写盘。

### 3. ScheduleStore 接入持久化

**存储键**：`scheduled_events`，值为 `ScheduledEvent[]` 的 JSON 字符串。改动模式与 TaskStore 完全一致：

- `addEvent()`：`push` 后 `this.persist()`
- `removeEvent()`：删除后，仅当实际删除才 `persist()`

### 4. EntryAbility 启动恢复

```typescript
import { persistence } from '../models/Persistence';
import { taskStore } from '../models/TaskPackage';
import { scheduleStore } from '../models/ScheduledEvent';

onCreate(want, launchParam): void {
  // 初始化持久化并恢复数据（早于 loadContent，保证首页渲染时数据已就绪）
  persistence.init(this.context);
  taskStore.restore();
  scheduleStore.restore();
  // ...原有 colorMode 设置等
}
```

**时机保证**：`onCreate` 先于 `onWindowStageCreate`（其中才 `loadContent('pages/Index')`），因此首页 `aboutToAppear` / `onPageShow` 触发 `loadData()` 时，store 内存数据已恢复完毕。

---

## 四、数据流

```
写路径（用户操作）
  创建/编辑/删除任务包 ──► taskStore.add/update/deletePackage()
                                │
                                └─► persist() ──► preferences.putSync + flushSync ──► 沙箱文件
  拖拽排程 / 删除日程 ──► scheduleStore.add/removeEvent()
                                │
                                └─► persist() ──► preferences.putSync + flushSync ──► 沙箱文件

读路径（应用启动）
  EntryAbility.onCreate()
    ├─► persistence.init(context)      ── 获取 Preferences 实例
    ├─► taskStore.restore()            ── getSync + JSON.parse ── 恢复内存
    └─► scheduleStore.restore()        ── getSync + JSON.parse ── 恢复内存
         │
         ▼
  Index 页面 onPageShow ──► refreshTrigger++ ──► 子 Tab loadData() 读取内存
```

---

## 五、运行测试指南

### 操作流程

1. 启动应用，创建 1~2 个任务包，并拖拽到日历安排 1 个日程
2. **完全退出应用**（从最近任务列表划掉，而非仅按 Home 键）
3. 重新启动应用
4. 切换到 📋 任务包 Tab → 之前创建的任务包卡片仍在
5. 切换到 📅 日历 Tab → 之前的日程标记仍在，进入对应日视图可见日程详情

### 预期效果

- ✅ 任务包在应用重启后仍存在
- ✅ 日程安排（含拖拽创建的）在应用重启后仍存在
- ✅ 编辑任务包后重启，保留的是最新内容
- ✅ 删除任务包后重启，该任务包不再出现
- ✅ 首次启动（无历史数据）时，空状态提示正常

---

## 六、已知限制与后续改进

### 数据一致性（遗留自 log_06，本次未处理）
- [ ] 编辑任务包不级联更新 `ScheduledEvent` 中的冗余字段（`packageName` / `color` / `steps`）
- [ ] 删除任务包不级联删除关联的 `ScheduledEvent`（"幽灵日程"）

### 持久化本身
- [ ] 每次写操作都调用 `flushSync()`，数据量大时可能有性能开销；当前数据量小，可接受
- [ ] JSON 序列化整表覆盖，未做增量写入
- [ ] 未做数据版本号 / 迁移机制（后续数据结构变更时需考虑）
- [ ] 未加密存储，敏感数据（如未来接入的账号信息）需另行处理

---

## 七、关键技术点回顾

### 1. 避免循环依赖

`Persistence` 不 import 任何 store，store 单向依赖 `Persistence`，依赖关系为：

```
TaskPackage ──► Persistence
ScheduledEvent ──► Persistence
ScheduledEvent ──► TaskPackage（原有，仅为取 TaskStep 类型）
EntryAbility ──► Persistence / TaskPackage / ScheduledEvent
```

无环，模块初始化安全。

### 2. 同步接口的选择依据

异步接口（`getPreferences` + Promise）会引入"恢复数据是否已完成"的时序问题，需要额外状态协调。同步接口在启动路径上一次性调用，代码更简单直接，符合"最小代码解决问题"。

### 3. 幂等的 init 与防御性判空

- `init()` 通过 `if (this.prefs !== null) return` 保证幂等
- `readString` / `writeString` 在 `prefs === null` 时安全返回，避免在 init 前调用导致崩溃

### 4. JSON 序列化与 ArkTS 类型断言

```typescript
this.packages = JSON.parse(raw) as TaskPackage[];
```

`JSON.parse` 返回 `Object`（ESObject），通过 `as TaskPackage[]` 收窄为具体类型，这是 ArkTS 处理 JSON 反序列化的标准写法。

---

## 八、数据一致性修复（2026-09-02 追加）

### 目标

修复 log_06 就记录的两个数据一致性问题：

1. **编辑任务包不级联同步日程**：`ScheduledEvent` 冗余存储了 `packageName` / `color` / `steps`，编辑任务包后这些字段仍是旧数据。
2. **删除任务包不级联删除日程**：删除任务包后，关联的 `ScheduledEvent` 残留，产生"幽灵日程"。

本次把一致性规则内聚到数据层（`ScheduleStore`），由 `TaskStore` 增删改时自动触发。

### 文件变更清单

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/models/ScheduledEvent.ets` | 新增 `syncPackageFields()`（同步冗余字段 + 重算结束时间）、`removeEventsByPackageId()`（级联删除） |
| `entry/src/main/ets/models/TaskPackage.ets` | `updatePackage` / `deletePackage` 成功后调用级联方法；更新过时注释 |

### 详细变更说明

**`syncPackageFields(pkg)`** —— 编辑后同步冗余字段并重算结束时间：

```typescript
public syncPackageFields(pkg: TaskPackage): void {
  let changed: boolean = false;
  for (const event of this.events) {
    if (event.packageId === pkg.id) {
      event.packageName = pkg.name;
      event.color = pkg.color;
      event.steps = pkg.steps;
      // 基于新的步骤总时长重算结束时间
      const totalMin: number = getTotalDuration(pkg.steps);
      const endTotalMin: number = event.startHour * 60 + event.startMinute + totalMin;
      event.endHour = Math.floor(endTotalMin / 60) % 24;
      event.endMinute = endTotalMin % 60;
      changed = true;
    }
  }
  if (changed) {
    this.persist();
  }
}
```

结束时间公式与 `CalendarTab` 拖拽吸附处完全一致，避免两处逻辑漂移。

**`removeEventsByPackageId(packageId)`** —— 删除后级联删除，仅在真正删除了数据时才 `persist()`。

**`TaskStore` 接入**：`updatePackage` 后调 `scheduleStore.syncPackageFields(updatedPkg)`；`deletePackage` 后调 `scheduleStore.removeEventsByPackageId(id)`。

### 关键技术点：循环依赖的成因与安全性

本次改动后两个 model 文件形成循环依赖：

```
TaskPackage.ets  ──import scheduleStore──►  ScheduledEvent.ets
      ▲                                            │
      └──────import TaskPackage / TaskStep─────────┘
```

安全的原因：

1. **类型导入无运行时影响**：`ScheduledEvent.ets` 导入的 `TaskPackage` / `TaskStep` 都是 `interface`，编译期擦除。
2. **延迟访问**：`scheduleStore` 的引用都发生在方法内部（运行时调用时才求值），此时两模块均已加载完毕、`scheduleStore` 已初始化，不触发 TDZ。
3. **无顶层互相调用**：两模块顶层只做 `const xxx = new Xxx()` 实例化。

### 测试指南

1. 编辑任务包（改名/改色/改步骤）→ 日历上关联日程的名称、颜色、步骤摘要、结束时间同步更新。
2. 删除任务包 → 关联日程被级联删除，无"幽灵日程"。
3. 重启应用后上述同步结果仍正确（持久化生效）。

### 已知限制

- [ ] `event.steps = pkg.steps` 是共享引用（非深拷贝），当前只读展示、无副作用，可接受。
- [ ] 删除任务包的 UI 入口尚未实现（`deletePackage` 方法已就绪并自动级联）。

---

## 九、时间轴对齐遗留问题（待办，未实施）

> 本节为「待办记录」，供下次会话接续，代码尚未改动。

### 问题现状（详见 `left_problem.md`）

1. **字体 ascender 微偏**：`Text("09:00").fontSize(9)` 的字形不从 y=0 开始，与水平分割线存在 1-2vp 固有视觉偏差。目前靠「魔法 padding」硬凑——周视图顶部差 2vp、日视图差 1vp，两个视图还不一致。
2. **24:00 底部留白**：日视图两列总 padding 不对称（标签列 6vp vs 内容列 5vp），灰底不贴边。

### 已定方案（Canvas 重构，未实施）

用 **Canvas 自绘时间轴网格背景**，事件块保持流式布局。要点：

- **Canvas 画**：左侧 36vp 灰底 `#FAFAFA` + 25 条水平分割线 `#E0E0E0` + 25 个时间标签；标签用 `fillText` + `textBaseline='middle'` + `textAlign='right'` 精确控制字形位置，**彻底消除字体 ascender 微偏**（纯布局无法做到，这是选 Canvas 而非 Stack 的原因）。
- **事件块**：保持现有 `Column` 流式布局（周视图 7 列、日视图单列），去掉每小时内 `Column` 里的 `Divider()`；无事件槽位 `Blank().height(heights[h])`（不再 `-1`）。
- **高度数组**：`computeWeekHourHeights()` / `computeDayHourHeights()` 去掉 `+1`（不再有 Divider 补偿）。
- **坐标同步基准**：第 h 小时槽位 top = `GRID_TOP_PADDING + Σ heights[0..h-1]`，Canvas 分割线与事件块层共享同一个 `heights` 数组和同一个顶部偏移。
- **拖拽/时间线适配**：`snapTimeFromY()` 与 `buildTimeIndicator()` / `getTimeIndicatorOffset()` 需减去顶部偏移 `GRID_TOP_PADDING`。
- **重绘**：Canvas `onReady` 首次绘制 + 数据变化（`loadData`/`buildWeekData`/`goToDayView`/切周/切日/`handleDrop` 等）时显式调用 `drawWeekGrid`/`drawDayGrid`，与现有 `computeWeekHourHeights` 触发链一致。

### 技术依据（已查离线文档确认）

- `Canvas(context)` 需 `RenderingContextSettings(true)` + `CanvasRenderingContext2D`；`.onReady(() => {})` 里绘制（`harmony-next/references/.../topics/components/Canvas.md`）。
- 绘制 API：`fillRect` / `beginPath`+`moveTo`+`lineTo`+`stroke` / `font='9vp sans-serif'` + `textAlign='right'` + `textBaseline='middle'` + `fillText`（`CanvasRenderingContext2D.md`）。

### 状态

- 方案已设计完成（本会话 plan 文件 `radiant-brewing-petal.md`）。
- **代码未改动**，`CalendarTab.ets` 仍是流式布局 + 魔法 padding 的现状。
