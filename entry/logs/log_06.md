# 鸿蒙应用第五次开发日志

## 项目信息

- **项目名称**：StudyStream
- **开发日期**：2026-07-03
- **目标**：实现任务包的详情查看与编辑功能

---

## 一、本次改动总体目标

在前四次迭代的基础上，为任务包模块补齐"查看详情"和"编辑已有任务包"两条关键用户路径：

1. **卡片点击 → 详情弹窗**：在 Tab1 中点击彩色卡片，弹出详情弹窗（任务包名称、步骤列表、时长统计）
2. **弹窗内一键编辑**：弹窗右上角 ✏️ 按钮 → 关闭弹窗 → 跳转编辑页
3. **CreatePackage 双模式复用**：改造 `CreatePackage.ets`，同时支持创建和编辑两种模式，通过路由参数 `packageId` 区分
4. **全局状态刷新**：利用已有的 `refreshTrigger` + `@Watch('loadData')` 机制自动刷新

---

## 二、文件变更清单

### 新建文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/pages/PackageDetailDialog.ets` | 任务包详情弹窗组件（`@CustomDialog`） |
| `entry/logs/log_task_detail_edit.md` | 本日志文件 |

### 修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/models/TaskPackage.ets` | 新增 `updatePackage()` 和 `deletePackage()` 方法 |
| `entry/src/main/ets/pages/CreatePackage.ets` | 改造为双模式（创建 + 编辑），通过路由参数切换 |
| `entry/src/main/ets/pages/TaskPackageTab.ets` | 卡片添加 `onClick` → 详情弹窗；导入 `PackageDetailDialog` |
| `entry/src/main/ets/pages/PackageDetailDialog.ets` | 修复 controller 默认值递归引用问题（崩溃根因） |

### 未修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/models/ScheduledEvent.ets` | 无需改动 |
| `entry/src/main/ets/pages/Index.ets` | 无需改动（`refreshTrigger` 机制自动生效） |
| `entry/src/main/ets/pages/CalendarTab.ets` | 无需改动（左侧面板卡片拖拽功能不变） |
| `entry/src/main/resources/base/profile/main_pages.json` | 无需改动（CreatePackage 已注册，不需新路由） |
| `entry/src/main/ets/entryability/EntryAbility.ets` | 无需改动 |

---

## 三、崩溃原因分析与修复

### 崩溃根因

第一版 `PackageDetailDialog.ets` 中 `controller` 字段的默认值引发了循环引用：

```typescript
// ❌ 错误写法：导致递归初始化 + 运行时崩溃
controller: CustomDialogController = new CustomDialogController({
    builder: PackageDetailDialog({ package: {} as TaskPackage }),
    //       ↑ 这里又创建了一个 PackageDetailDialog，
    //         它的 controller 字段又会创建新的 CustomDialogController，
    //         而那个 controller 又会创建 PackageDetailDialog...
    //         形成无限循环引用
});
```

### 修复方案

用空 `Column` 占位符替代递归引用：

```typescript
// ✅ 正确写法：占位符满足编译器要求，运行时被系统注入的真实 controller 覆盖
controller: CustomDialogController = new CustomDialogController({
    builder: Column() {},
    autoCancel: true
});
```

### 架构改进：删除独立 EditPackage.ets，统一到 CreatePackage.ets

第一版创建了独立的 `EditPackage.ets`，但与 `CreatePackage.ets` 存在大量代码重复。用户建议"套用创建页面"，改进后的方案是：

- `CreatePackage.ets` 通过 `router.getParams()` 检测是否有 `packageId` 参数
- **无参数** → 创建模式（空白表单）
- **有参数** → 编辑模式（预填充当前数据）
- 保存时根据模式分别调用 `addPackage()` 或 `updatePackage()`

这样做的好处：
- 零代码重复
- 创建和编辑的验证规则 100% 一致
- 不需要新增路由注册
- 后续维护只需改一份代码

---

## 四、弹窗与编辑页面的数据流转

### 完整数据流

```
┌─────────────────────────────────────────────────────────┐
│ TaskPackageTab                                          │
│   │                                                     │
│   ├── onClick(item)                                     │
│   │     └── showPackageDetail(pkg)                      │
│   │           └── new CustomDialogController({           │
│   │                 builder: PackageDetailDialog({       │
│   │                   package: pkg,                     │
│   │                   onEdit: (pkgId) => {              │
│   │                     router.pushUrl(                 │
│   │                       'pages/CreatePackage',        │
│   │                       { packageId }                 │
│   │                     )                               │
│   │                   }                                 │
│   │                 })                                  │
│   │               })                                    │
│   │               .open()                               │
│   │                                                     │
│   ▼                                                     │
│ PackageDetailDialog (弹窗)                               │
│   │                                                     │
│   ├── 展示：名称 + 步骤 + 时长                           │
│   ├── ✏️ onClick → controller.close() + onEdit(id)      │
│   │                                                     │
│   ▼                                                     │
│ CreatePackage.ets (创建/编辑页)                          │
│   │                                                     │
│   ├── aboutToAppear()                                   │
│   │     ├── router.getParams().packageId → 编辑模式      │
│   │     ├── taskStore.getPackageById() → 预填充表单      │
│   │     └── 无参数 → 创建模式（默认空白）                 │
│   │                                                     │
│   ├── savePackage()                                     │
│   │     ├── 编辑模式 → taskStore.updatePackage()         │
│   │     └── 创建模式 → taskStore.addPackage()            │
│   │                                                     │
│   └── router.back()                                     │
│         │                                               │
│         ▼                                               │
│   Index.onPageShow()                                    │
│         │                                               │
│         └── refreshTrigger++                            │
│               ├── TaskPackageTab.@Watch('loadData')     │
│               │     └── 卡片列表刷新                    │
│               └── CalendarTab.@Watch('loadData')        │
│                     └── 左侧面板 + 日历标记刷新           │
└─────────────────────────────────────────────────────────┘
```

---

## 五、使用指南

### 完整操作步骤

1. **启动应用** → 切换到底部 **📋 任务包** Tab
2. **点击任意彩色卡片** → 弹出详情弹窗（居中、半透明背景）
   - 弹窗显示任务包名称（大号加粗）、步骤列表（序号圆点 + 时长标签）、总时长统计
3. **点击弹窗外侧半透明区域** 或 **底部「关闭」按钮** → 弹窗关闭
4. **再次点击卡片** → 弹窗重新打开（每次打开数据都是最新的）
5. **点击弹窗右上角 ✏️** → 弹窗关闭 → 自动跳转到编辑页面
6. **编辑页面**（与创建页面是同一个，只是预填充了数据）：
   - 标题显示「编辑任务包」而非「创建任务包」
   - 左上角显示「取消」而非「← 返回」
   - 所有字段已预填充（名称、步骤名称、时长）
   - 可修改任意字段、删除步骤、添加新步骤
7. **点击「保 存」** → 验证 → 更新全局仓库 → Toast "保存成功！" → 自动返回
8. **列表页自动刷新** → 卡片显示更新后的名称和步骤摘要
9. **切换到 📅 日历 Tab** → 左侧面板任务包信息也同步更新（名称、颜色、步骤摘要）

### 快捷验证路径

```
启动 App → 📋 Tab → 点击卡片 → 弹窗出现 → ✏️ → 编辑页（预填充）
→ 修改名称 → 保存 → 返回列表 → 卡片已更新 ✅
```

---

## 六、已知限制与后续改进

### 详情弹窗
- [ ] 弹窗内部不支持直接编辑（需跳转编辑页）
- [ ] 不支持在弹窗内拖拽排序步骤
- [ ] 不支持在弹窗内删除任务包
- [ ] 弹窗动画为系统内置 fade+scale，未自定义

### 编辑功能
- [ ] 编辑时不显示/不可修改任务包颜色
- [ ] 编辑后已安排日程（ScheduledEvent）中的冗余字段不会同步更新
- [ ] 不支持编辑页内删除整个任务包（需后续添加）

### 数据一致性
- [ ] 删除任务包不级联删除关联的 ScheduledEvent
- [ ] 编辑任务包不级联更新 ScheduledEvent 中的冗余字段

### 视觉增强
- [ ] 步骤列表可添加滑动删除手势
- [ ] 步骤支持拖拽排序
- [ ] 保存成功后可添加成功动画

---

## 七、关键技术点回顾

### 1. CustomDialog 动态数据（每次重建 Controller）

```typescript
showPackageDetail(pkg: TaskPackage): void {
  // 每次点击创建新的 controller，确保弹窗数据是实时的
  const dialogController = new CustomDialogController({
    builder: PackageDetailDialog({ package: pkg, onEdit: callback }),
    autoCancel: true, alignment: DialogAlignment.Center,
    customStyle: true, cornerRadius: 16,
  });
  dialogController.open();
}
```

### 2. CreatePackage 双模式路由判断

```typescript
aboutToAppear(): void {
  const params = router.getParams() as Record<string, Object>;
  if (params && params['packageId']) {
    this.isEditMode = true;
    const pkg = taskStore.getPackageById(params['packageId'] as string);
    if (pkg) { /* 预填充 */ }
  }
  // 无参数 → 创建模式，保持默认空白表单
}
```

### 3. 保存时的模式分支

```typescript
if (this.isEditMode) {
  taskStore.updatePackage(this.editPackageId, {
    id: this.editPackageId,          // 保留原始 ID
    name: this.packageName.trim(),
    steps: validSteps,
    color: this.originalColor        // 保留原始颜色
  });
} else {
  taskStore.addPackage({
    id: generateId(),                // 新建 ID
    name: this.packageName.trim(),
    steps: validSteps,
    color: getNextColor(...)         // 自动分配颜色
  });
}
```

### 4. controller 占位符（避免循环引用崩溃）

```typescript
// ✅ 关键：默认值只能用不会递归引用 PackageDetailDialog 的简单 builder
controller: CustomDialogController = new CustomDialogController({
    builder: Column() {},  // 空占位符
    autoCancel: true
});
```
