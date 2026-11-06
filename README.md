# Colendar

Colendar 是一款使用 ArkTS 和 ArkUI 构建的 HarmonyOS 任务日历应用。它把分步骤任务安排到日历中，并在执行时提供计时与进度引导。

## Contents / 目录

- [中文](#中文)
- [English](#english)

## 中文

### 功能

- **任务包**：将任务拆分为多个步骤，为每个步骤设置时长。
- **日历排程**：在月、周、日视图中安排任务，移动、复制日程并查看开始提醒。
- **分步执行**：按步骤计时，查看进度，并暂停或继续任务。
- **模板与分享**：导入、导出版本化任务模板，通过系统分享或 Share Kit `knockShare` 传递模板。
- **关联动作**：按用户设置打开应用、链接和已授权文件。

### 开发环境

- DevEco Studio、HarmonyOS SDK `26.0.0`，兼容 SDK `6.1.0(23)`。
- Node.js 22、OHPM，以及 DevEco Studio 工具链中的 Hvigor。
- Windows 用于运行仓库提供的 PowerShell 脚本和 `harmonyos-sdk` 自托管工作流。

### 构建

1. 在仓库根目录运行 `ohpm install`。
2. 运行 `node scripts/configure-build.mjs` 生成本地构建配置 `build-profile.json5`。
3. 在 DevEco Studio 构建 `entry` 模块，或在 PowerShell 运行 `.\scripts\build-check.ps1`。
4. 配置本地签名时，将 `config/signing.local.example.json` 复制为 `config/signing.local.json` 并填写本机签名信息。该文件和生成的构建配置由 Git 忽略。

在 DevEco Studio 集成终端中运行构建脚本。若 Hvigor 不在 `PATH` 中，将 `HARMONY_HVIGOR` 设为本机工具链中的 Hvigor 程序路径。

### 测试与数据恢复

运行 `.\scripts\test-check.ps1` 执行已注册的 HarmonyOS 测试。自动化工作流使用安装了 SDK、OHPM 和 Hvigor 的 Windows `harmonyos-sdk` 自托管运行器；设备验收单独进行。

任务包、日程和执行记录保存在版本化快照中。启动时会校验快照；数据无法读取时，恢复页面提供重试、复制备份、恢复上一份快照和重置操作。

### 许可证

仓库当前未提供许可证文件。

## English

Colendar is a HarmonyOS task calendar built with ArkTS and ArkUI. It schedules step-based tasks and guides users through timed sessions.

### Features

- **Task packages**: Split tasks into steps and set a duration for each step.
- **Calendar scheduling**: Plan in month, week, and day views; move or copy events; and view start reminders.
- **Guided execution**: Time each step, track progress, and pause or resume a session.
- **Templates and sharing**: Import and export versioned task templates, then share them through the system share sheet or Share Kit `knockShare`.
- **Linked actions**: Open apps, links, and authorized files according to user settings.

### Development environment

- DevEco Studio and HarmonyOS SDK `26.0.0`, with compatible SDK `6.1.0(23)`.
- Node.js 22, OHPM, and Hvigor from the DevEco Studio toolchain.
- Windows for the repository's PowerShell scripts and the `harmonyos-sdk` self-hosted workflow runner.

### Build

1. Run `ohpm install` from the repository root.
2. Run `node scripts/configure-build.mjs` to generate the local `build-profile.json5`.
3. Build the `entry` module in DevEco Studio, or run the PowerShell script `.\scripts\build-check.ps1`.
4. For local signing, copy `config/signing.local.example.json` to `config/signing.local.json` and fill in your local signing values. Git ignores this file and the generated build profile.

Run the build script in DevEco Studio's integrated terminal. If Hvigor is not on `PATH`, set `HARMONY_HVIGOR` to the Hvigor executable in your local toolchain.

### Tests and data recovery

Run `.\scripts\test-check.ps1` in PowerShell to execute the registered HarmonyOS tests. The automated workflow uses a self-hosted Windows `harmonyos-sdk` runner with the SDK, OHPM, and Hvigor installed. Device verification is performed separately.

Task packages, scheduled events, and execution sessions are stored in a versioned snapshot. The app validates the snapshot at startup. If it cannot read the data, the recovery page offers retry, backup copy, restore from the previous snapshot, and reset actions.

### License

The repository does not currently include a license file.
