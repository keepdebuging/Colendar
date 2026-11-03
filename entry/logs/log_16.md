# Colendar 第十六次开发日志

## 项目信息

- 开发日期：2026-10-29
- 执行依据：`plan.md`、`README.md` 与当前源码
- 目标：按阶段补齐尚未完成的本地 MVP，逐阶段构建并记录验证结果

## 一、开始前审计

### 1.1 工作区与已有改动

- 项目已由 `studystream` 更名并移动到 `C:\Users\31263\Colendar`，本轮以该目录为唯一工程根目录。
- 保留上一轮 E4 的未提交改动，不覆盖、不回滚。
- 代码中已经存在 E1～E5 的执行闭环主体和 R1 应用内提醒主体。
- S1～S6 中存在部分旧实现，但仍缺少同日重复安排、实例定制标记、统一聚焦态、两段式粘贴和共享时间轴几何等计划要求。

### 1.2 基线构建

- 使用 DevEco Studio 自带 JBR、SDK 和 Hvigor 执行：
  `hvigorw.bat --no-daemon --mode module -p module=entry@default assembleHap`
- 结果：`BUILD SUCCESSFUL`。
- `CompileArkTS`、`PackageHap`、`PackingCheck`、`SignHap` 均成功。

## 二、阶段实施记录

> 本节将在每个阶段完成后继续更新；阶段只有在代码验证和 HAP 构建通过后才会在 `plan.md` 中标记完成。

### 2.1 S1：允许同日重复安排同一任务包

- 删除 `CalendarTab.handleDrop()` 中以 `packageId + date` 拒绝重复安排的判断。
- 保留同一时段最多两个重叠事件的既有约束；S1 只解除同一母模板在同一天只能出现一次的限制。
- 新建日程仍通过 `generateId()` 生成独立 `ScheduledEvent.id`，后续删除、移动和执行均继续按事件 ID 定位。
- 阶段构建：`BUILD SUCCESSFUL`；未新增 ArkTS 编译错误。
- `ScheduleStore.isPackageScheduledOnDate()` 已无业务调用，暂保留为只读查询接口，不再承担约束。

### 2.2 S2：单实例编辑与铅笔标记

- 为 `ScheduledEvent` 增加可选 `isCustomized` 字段，旧数据缺少字段时按 `false` 处理。
- `ScheduleStore` 新增 `getEventById()`，并在同步母任务包字段时跳过已定制实例。
- 日程详情中调整开始时间、单步时长或总时长后，将该实例标记为已定制。
- 上下边缘拉伸保存后同样标记为已定制。
- 新安排的事件显式初始化为未定制；复制/剪切克隆时保留原实例的定制属性。
- 日历标题对已定制实例追加 `✎` 标记。
- 新增 `ScheduleStore.test.ets`，覆盖定制实例不被母模板同步覆盖，以及同源重复实例按独立 ID 查询。
- 阶段构建：`BUILD SUCCESSFUL`；新增字段、日历标记与测试注册通过 ArkTS 编译。

### 2.3 S3/S4：长按聚焦与直接边缘拉伸

- 复用现有 400ms `LongPressGesture`，识别成功后直接进入统一聚焦态。
- 聚焦事件显示 2vp 蓝色边框；其他事件块使用模糊效果弱化，目标事件保持清晰。
- 聚焦菜单固定为“编辑、复制、剪切、分享”，移除旧的“拉伸”菜单入口。
- 聚焦后立即显示上下 12vp 命中区，用户可以直接拖动边缘拉伸。
- 点击时间轴空白退出聚焦，不写入任何日程数据。
- 继续沿用上边缘保持结束时间、下边缘保持开始时间、5 分钟吸附、松手一次持久化和最后一步补齐取整差额的既有实现。

### 2.4 S5：复制/剪切两段确认

- 第一次点击时间轴只计算目标位置并显示带“+”的静态虚线框，不写入 Store。
- 再次点击虚线框覆盖的时间范围才提交；点击其他时间只移动预览框。
- 剪切期间源日程仅以透明方式临时隐藏，取消会完整恢复，持久化数据始终保留到确认时。
- 复制确认时生成新 ID；剪切确认时更新原 ID；两者都使用预览中保存的日期和时间。
- 目标区超过当天末尾时裁剪到最晚可开始时间，重叠上限校验在预览阶段完成。

### 2.5 S6：共享时间轴几何、自由拖放与磁吸

- 新建纯计算模块 `utils/TimelineGeometry.ets`，统一分钟与 Y 坐标正反换算、时长到高度、全天边界裁剪和磁吸规则。
- 默认按 5 分钟粒度安排；只有距离最近整点/半点小于等于 8vp 时才吸附。
- 拖拽移动实时更新虚线框；松手直接使用最后一次预览保存的时间，不再重新计算另一套落点。
- 拖放与复制/剪切使用同一 `resolveTimelinePlacement()` 规则。
- 事件块顶部、拖拽预览顶部、当前时间线统一使用 `timelineMinutesToY()`。
- 新增 `TimelineGeometry.test.ets`，覆盖带滚动/网格偏移的正反换算、磁吸阈值、自由五分钟落点和当天边界裁剪。
- S3、S4、S5、S6 阶段构建均为 `BUILD SUCCESSFUL`；手势体感和多倍率坐标仍需设备验收。

### 2.6 R1：应用内提醒复核

- 已有实现包含开始前一分钟弱提示、最后 20 秒确认框、确认倒数、稍后 5 分钟、详情通知开关和同一日程去重。
- 到点或确认后统一以 `prepare=true` 进入执行页，经过背景过渡、横屏与 3、2、1 倒数；第一步在准备阶段保持暂停，不消耗时长。
- 已完成、已放弃或已有运行记录的日程不会重复触发原始计划提醒。

### 2.7 R2：系统级后台提醒外部阻塞

- 查阅 HarmonyOS API 23 本地文档并核对华为开发者官网：代理提醒仍需 `ohos.permission.PUBLISH_AGENT_REMINDER`，手机/平板/2in1 还需在 AppGallery Connect 申请开放能力。
- 审批通过后必须重新生成 Profile 并使用手动签名；当前仓库和本机无法证明该权益已经获批。
- 因此本轮不盲目加入受控权限或伪造可用状态，避免 HAP 可编译但无法安装/发布。
- 官方资料同时确认 API 20 起模拟器支持接口开发，但权限、通知点击和后台行为最终仍需获批 Profile 与真机验收。

### 2.8 A1：低风险场景动作

- 新增 `TaskAction` 模型，支持 `open-app`、`open-link`、`open-file` 和“任务开始/步骤开始”触发条件。
- 创建/编辑任务包页面增加关联动作编辑区；动作由用户明确添加并通过开关启用。
- 动作随任务包、日程实例和执行会话逐层深拷贝，运行中不受母模板后续修改影响。
- 新增 `TaskActionExecutor`：通过 `UIAbilityContext.openLink()` 或 `startAbility()` 打开目标。
- 会话保存已执行动作键；任务开始动作每轮最多执行一次，步骤动作每一步最多执行一次，页面重建不会重复拉起。
- 外部目标不存在或 URI 无处理方时只提示“计时已继续”，不会暂停、放弃或破坏会话。
- 不支持勿扰模式、通知控制等高权限动作；A2 仍按官方公开能力和权限审批逐项评估。

### 2.9 A2：高权限动作边界

- 继续遵守“公开 API、可申请权限、设备覆盖三项同时确认后才加入”的约束。
- 当前不向模型或界面加入勿扰、通知控制、智能家居等动作，也不显示无法使用的“规划中”按钮。
- 该阶段在 `plan.md` 标记为外部条件未满足，不用假实现冒充交付。

### 2.10 C1：版本化任务包导入与导出

- 新增 `utils/TaskPackageTransfer.ets`，定义 `SharedTaskPackageV1` 和统一导入结果类型。
- 导出内容使用带 `schemaVersion: 1` 的 JSON，而不是不可回读的人类描述文本。
- 导入限制为 16KB、名称 1～80 字、步骤 1～50 个、单步 1～1440 分钟、动作最多 20 个。
- 所有导入任务包和动作重新生成 ID；本地文件动作被剥离，应用/链接动作默认关闭。
- 新增 `ImportPackageDialog.ets`；任务包页右上角提供“导入”，任务包详情提供“导出模板”。
- 导出复用 HarmonyOS 系统分享面板；导入成功后立即进入本地 `TaskStore`。
- 快速开始生成的日程快照补齐任务包动作，避免模板入口与日历入口行为不一致。
- 新增 `TaskPackageTransfer.test.ets` 覆盖安全往返、版本拒绝和本地路径过滤。
- 阶段构建：`BUILD SUCCESSFUL`。

### 2.11 C2：Share Kit 碰一碰

- 核对当前 SDK 的 `@kit.ShareKit`，确认公开 `harmonyShare.on('knockShare', callback)` 与 `off` 接口可用。
- 任务包详情可见期间注册碰一碰监听，离开详情立即注销，避免后台长期暴露待分享内容。
- 碰触发生时发送与 C1 完全相同的版本化纯文本模板，不执行任何关联动作。
- 不支持该能力或华为分享未开启时捕获注册异常，并保留“导出模板”系统分享兜底。
- HAP 完整构建、打包和签名成功；双真机亮屏解锁、华为分享与碰触流程仍需设备验收。

### 2.12 测试与质量

- 为主 Tabs 和执行页的标题、步骤、计时、进度、暂停、结束、上下步骤等控件增加稳定 ID。
- 将 `ohosTest` 的示例字符串断言替换为真实冒烟用例：启动 `EntryAbility`、定位主 Tabs、切换任务包页、验证“我的任务包”。
- 新增 `UsageMetrics.ets`，只从本地任务包、日程和执行历史推导创建量、开始率、完成率、步骤完成率、重复执行和安排到开始间隔，不上传数据。
- 新增 `UsageMetrics.test.ets`，并从测试入口移除模板 `LocalUnit.test`。
- 本地单元测试命令 `hvigorw test -p module=entry@default` 实际运行成功：16 个产品逻辑测试全部通过，0 Failure，0 Error（最终复跑结果写入本日志末尾）。
- 应用 HAP 和 ohosTest HAP 均完成 `CompileArkTS/PackageHap/PackingCheck/SignHap`。

### 2.13 DevEco/模拟器探测

- 本机 Emulator 版本为 `26.0.0.200`，存在 Mate X7、MateBook Pro、Pura 90 Pro 三个 API 26 HVD，探测时均未运行。
- `hdc list targets -v` 仅返回多个无法唯一归属的 UART Ready 目标，没有 TCP Connected 模拟器目标，因此未对未知目标安装应用。
- Harmony NEXT 技能附带的 `hvd_manager.py` 在本机为 1 字节占位文件，无法建立私有 trace helper；按技能规则未拼凑不完整 CLI 启动命令。
- Windows Computer Use 运行时在当前工具会话中不可调用，因此无法从 DevEco 设备管理 UI 启动 HVD。
- 结论：本轮完成编译与本地单元测试；安装、ohosTest 执行、锁屏/杀进程/手势和双真机碰一碰留入 `check.md`。

## 三、文档收尾

- `plan.md` 增加阶段状态总览，并逐项更新 E1～E5、S1～S6、R1～R2、A1～A2、C1～C3。
- `README.md` 更名为 Colendar，改为当前真实能力、路线图和外部阻塞，不再把社区或高权限联动写成已交付功能。
- 新增 `check.md`，集中记录改动、自动验证结果、设备验收步骤和外部前置条件。

## 四、最终门禁结果

- 应用 HAP：`BUILD SUCCESSFUL`，完整经过 ArkTS 编译、打包、PackingCheck 与签名。
- 本地单元测试：`Tests run: 16, Failure: 0, Error: 0, Pass: 16, Ignore: 0`。
- ohosTest HAP：`BUILD SUCCESSFUL`，真实运行等待 Connected 设备。
- `git diff --check` 清理本轮新增的空白符问题后通过。
- 编译仍会报告工程既有的 deprecated、Preferences 异常提示和 API 兼容警告；本轮没有新增 ArkTS 编译错误。
