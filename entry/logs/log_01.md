# 鸿蒙应用第一次开发日志

## 项目信息

- **项目名称**：StudyStream
- **Bundle Name**：com.example.studystream
- **目标 SDK**：26.0.0 (HarmonyOS)
- **开发日期**：2026-06-29
- **目标**：实现"任务包创建与展示"的最小闭环

---

## 文件变更清单

### 新建文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/models/TaskPackage.ets` | 数据模型定义 + 全局状态管理（单例） |
| `entry/src/main/ets/pages/CreatePackage.ets` | 任务包创建页面 |
| `entry/logs/log_01.md` | 本日志文件 |

### 修改文件

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/pages/Index.ets` | 首页：从默认模板改写为任务包列表页 |
| `entry/src/main/resources/base/profile/main_pages.json` | 新增 CreatePackage 页面路由注册 |

### 未修改文件（保持原样）

| 文件 | 说明 |
|------|------|
| `entry/src/main/ets/entryability/EntryAbility.ets` | 应用入口，未改动 |
| `entry/src/main/module.json5` | 模块配置，未改动（pages 引用 $profile:main_pages） |
| `AppScope/app.json5` | 应用级配置，未改动 |
| `build-profile.json5` | 构建配置，未改动 |

---

## 详细变更说明

### 1. 数据模型 —— `models/TaskPackage.ets`

**路径**：`entry/src/main/ets/models/TaskPackage.ets`

**定义了以下内容**：

- **`TaskStep` 接口**：包含 `name: string` 和 `duration: number`（单位：分钟）
- **`TaskPackage` 接口**：包含 `id: string`、`name: string`、`steps: TaskStep[]`
- **`generateId()` 函数**：使用时间戳 + 随机数生成唯一 ID
- **`TaskStore` 类（单例模式）**：
  - 私有静态实例，保证全局只有一个数据仓库
  - `packages: TaskPackage[]` 数组存储所有任务包
  - `addPackage()` 方法用于添加任务包
  - 导出 `taskStore` 常量供全局使用

**为什么用单例模式？**
单例确保首页和创建页访问的是同一份数据，一处修改、另一处立即可见。后续可以替换为数据库持久化。

### 2. 路由配置 —— `main_pages.json`

**路径**：`entry/src/main/resources/base/profile/main_pages.json`

**修改内容**：在 `src` 数组中添加了 `"pages/CreatePackage"`。

```json
{
  "src": [
    "pages/Index",
    "pages/CreatePackage"
  ]
}
```

**说明**：鸿蒙应用的所有页面路径必须在此文件中注册，否则 `router.pushUrl()` 会失败。路径相对于 `entry/src/main/ets/`。

### 3. 首页 —— `pages/Index.ets`

**路径**：`entry/src/main/ets/pages/Index.ets`

**功能实现**：
- 顶部显示标题 "我的任务包"
- 使用 `@State packages` 存储任务包列表
- `onPageShow()` 生命周期：每次页面显示时从 `taskStore` 同步数据
- **空状态**：当没有任务包时，居中显示 "暂无任务包，点击右下角 + 号创建"
- **列表模式**：使用 `List` + `ForEach` 展示任务包名称和步骤数量
- **悬浮按钮**：使用 `Stack({ alignContent: Alignment.BottomEnd })` 定位，点击跳转到创建页

**关键技术点**：
- `router.pushUrl({ url: 'pages/CreatePackage' })` 实现页面跳转
- `@State` 装饰器使数据变化自动触发 UI 刷新
- `onPageShow` 确保从创建页返回后能看到新数据

### 4. 创建页 —— `pages/CreatePackage.ets`

**路径**：`entry/src/main/ets/pages/CreatePackage.ets`

**功能实现**：
- 顶部导航栏：返回按钮 + 标题
- 任务包名称输入框（`TextInput`）
- 动态步骤列表（`ForEach` 渲染）：
  - 每个步骤包含：序号、名称输入框、时长输入框（数字键盘）、删除按钮
- "添加步骤" 按钮：在列表末尾新增空白步骤
- "保存" 按钮，点击后：
  1. 验证名称不为空（显示 Toast 提示）
  2. 验证至少有一个有效步骤
  3. 组装 `TaskPackage` 对象
  4. 存入 `taskStore`
  5. 显示成功提示，自动返回首页

**关键技术点**：
- 数组不可变更新模式（创建新数组 → 修改 → 赋值）确保 `@State` 检测到变化
- `InputType.Number` 限制时长输入框只能输入数字
- `promptAction.showToast()` 显示提示信息
- `router.back()` 返回上一页

---

## 架构图

```
┌─────────────────────────────────────────────────┐
│                   应用架构                        │
├─────────────────────────────────────────────────┤
│                                                 │
│   EntryAbility (应用入口)                        │
│       │                                         │
│       ▼                                         │
│   Index.ets (首页)                               │
│       │ router.pushUrl('pages/CreatePackage')    │
│       ├──────────────────────►  CreatePackage.ets │
│       │                              │            │
│       │◄── router.back() ───────────┘            │
│       │                                         │
│       ▼                                         │
│   taskStore (全局单例)                            │
│       │                                         │
│       ▼                                         │
│   TaskPackage.ets (数据模型)                     │
│       - TaskStep 接口                            │
│       - TaskPackage 接口                         │
│       - TaskStore 单例                           │
│       - generateId() 工具函数                    │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 数据流

```
用户输入（CreatePackage）
    │
    ▼
验证 → 组装 TaskPackage 对象
    │
    ▼
taskStore.addPackage(pkg)
    │
    ▼
router.back() → 返回 Index
    │
    ▼
Index.onPageShow() → this.packages = [...taskStore.packages]
    │
    ▼
UI 自动刷新，显示新任务包
```

---

## 运行和测试指南

### 前提条件
1. DevEco Studio 已安装
2. 项目已创建（Empty Ability 模板）
3. 模拟器已创建，或真机已连接

### 步骤

1. **替换文件**：按本日志的变更清单，将所有代码替换/创建到对应位置

2. **同步项目**：在 DevEco Studio 中点击 `File → Sync Project with Ohpm Files`

3. **运行应用**：
   - 点击顶部工具栏的绿色 ▶ 按钮
   - 选择模拟器或真机作为目标设备
   - 等待编译和部署完成

4. **操作流程**：
   - 应用启动后，看到首页显示 "暂无任务包，点击右下角 + 号创建"
   - 点击右下角蓝色 "+" 按钮
   - 进入创建页，输入任务包名称（如 "期末复习"）
   - 默认有一个步骤，填写步骤名称（如 "复习数学"）和时长（如 30）
   - 点击 "+ 添加步骤" 添加更多步骤
   - 点击 "保存" 按钮
   - 看到 "创建成功！" 提示后自动返回首页
   - 首页列表中显示刚创建的任务包

### 预期效果

- ✅ 首页标题显示 "我的任务包"
- ✅ 空状态显示提示文字
- ✅ 悬浮按钮可点击跳转
- ✅ 创建页可以输入名称和步骤
- ✅ 可以动态添加/删除步骤
- ✅ 保存成功后返回首页
- ✅ 首页列表显示新创建的任务包

### 注意事项

- 数据保存在内存中，关闭应用后会丢失（后续会加入数据库持久化）
- 时长输入框使用数字键盘，只能输入整数
- 名称为空的步骤在保存时会被自动过滤
- 如果所有步骤名称都为空，会提示 "请至少为一个步骤填写名称"
