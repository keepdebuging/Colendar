/**
 * TaskPackageTab.ets —— Tab 1 任务包列表
 *
 * Week 2 重构：从原来的简单文本列表升级为彩色卡片式布局。
 *
 * 功能：
 * 1. 卡片式展示所有已保存的任务包（不同颜色背景）
 * 2. 每张卡片显示：名称（加粗）+ 步骤摘要 + 步骤数量
 * 3. 右下角悬浮 "+" 按钮，跳转到创建页
 * 4. 空状态提示
 */

import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { TaskPackage, taskStore, generateId } from '../models/TaskPackage';
import { PackageDetailDialog } from './PackageDetailDialog';
import { ImportPackageDialog } from './ImportPackageDialog';
import {
  exportTaskPackage,
  importTaskPackage,
  TaskPackageImportResult
} from '../utils/TaskPackageTransfer';
import { DEFAULT_PACKAGES } from '../onboarding/DefaultPackages';
import { buildDiagnosticReport } from '../diagnostics/DiagnosticReport';

/**
 * 注意：这里使用 @Component 而不是 @Entry，
 * 因为它作为 TabContent 的子组件，不是独立页面。
 */
@Component
export struct TaskPackageTab {
  /**
   * @Consume refreshTrigger：从 Index 的 @Provide 直连获取，
   * 绕过 TabContent 的 @Prop 传递限制。
   * 当用户在标签间切换或从创建/编辑页返回时，父组件递增此值，
   * @Watch('loadData') 检测到变化后调用 loadData() 同步最新数据。
   */
  @Consume @Watch('loadData') refreshTrigger: number = 0;
  @State packages: TaskPackage[] = [];
  @State private importingExamples: boolean = false;

  /**
   * 从全局仓库同步数据
   * 使用展开运算符创建新数组，触发 @State 变更检测
   */
  loadData(): void {
    this.packages = [...taskStore.packages];
  }

  /**
   * 组件即将出现时（首次加载）同步数据
   */
  aboutToAppear(): void {
    this.loadData();
  }

  private showImportDialog(): void {
    const dialogController: CustomDialogController = new CustomDialogController({
      builder: ImportPackageDialog({
        onClose: () => dialogController.close(),
        onImport: (text: string) => { void this.importPackageText(text, dialogController); }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      cornerRadius: 16
    });
    dialogController.open();
  }

  private async importPackageText(text: string, dialogController: CustomDialogController): Promise<void> {
    const result: TaskPackageImportResult = importTaskPackage(text, taskStore.packages.length);
    if (!result.package) {
      promptAction.showToast({ message: result.error, duration: 2200 });
      return;
    }
    try {
      await taskStore.addPackage(result.package);
      this.loadData();
      dialogController.close();
      promptAction.showToast({ message: '任务包已导入，关联动作默认关闭', duration: 2200 });
    } catch (_error) {
      promptAction.showToast({ message: '导入失败，现有数据保持不变', duration: 2200 });
    }
  }

  private sharePackage(pkg: TaskPackage): void {
    const sharedData: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.PLAIN_TEXT,
      title: `${pkg.name} · Colendar 任务包`,
      content: exportTaskPackage(pkg)
    });
    const controller: systemShare.ShareController = new systemShare.ShareController(sharedData);
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    }).catch((error: BusinessError) => {
      promptAction.showToast({ message: `导出失败：${error.message}`, duration: 2200 });
    });
  }

  private async importExamples(): Promise<void> {
    if (this.importingExamples) {
      return;
    }
    this.importingExamples = true;
    try {
      const examples: TaskPackage[] = DEFAULT_PACKAGES.map((preset) => ({
        id: generateId(),
        name: preset.name,
        color: preset.color,
        _version: 0,
        steps: preset.steps.map((step) => ({ name: step.name, duration: step.duration }))
      }));
      await taskStore.addPackages(examples);
      this.loadData();
      promptAction.showToast({ message: '示例已添加。打开日历即可安排到合适的时间。', duration: 2500 });
    } catch (_error) {
      promptAction.showToast({ message: '导入示例失败，现有数据保持不变' });
    } finally {
      this.importingExamples = false;
    }
  }

  private copyDiagnostics(): void {
    try {
      const report: string = buildDiagnosticReport('TaskPackageTab');
      pasteboard.getSystemPasteboard().setDataSync(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, report)
      );
      promptAction.showToast({ message: '诊断信息已复制；报告不含任务名称或步骤内容' });
    } catch (_error) {
      promptAction.showToast({ message: '复制诊断信息失败' });
    }
  }

  /**
   * 生成步骤摘要文字
   * 例如："锻炼 20分钟 · 休息 5分钟 · 反思 10分钟"
   */
  getStepsSummary(pkg: TaskPackage): string {
    if (pkg.steps.length === 0) {
      return '暂无步骤';
    }
    return pkg.steps
      .map((s) => `${s.name} ${s.duration}分钟`)
      .join(' · ');
  }

  /**
   * 计算任务包总时长（分钟）
   */
  getTotalDuration(pkg: TaskPackage): number {
    if (!pkg.steps || pkg.steps.length === 0) {
      return 0;
    }
    return pkg.steps.reduce((sum: number, s) => sum + s.duration, 0);
  }

  /**
   * 格式化总时长为可读字符串
   * 例如：65分钟 → "1小时5分钟"，30分钟 → "30分钟"
   */
  formatDuration(total: number): string {
    if (total === 0) {
      return '';
    }
    if (total >= 60) {
      const hours: number = Math.floor(total / 60);
      const mins: number = total % 60;
      if (mins > 0) {
        return `${hours}小时${mins}分钟`;
      }
      return `${hours}小时`;
    }
    return `${total}分钟`;
  }

  /**
   * 点击任务包卡片时调用：弹出详情弹窗。
   *
   * 每次点击都会新建一个 CustomDialogController，确保弹窗中
   * 展示的是被点击卡片的实时数据（而非缓存值）。
   *
   * 弹窗数据流：
   *   卡片 onClick → showPackageDetail(pkg)
   *   → 创建 CustomDialogController( PackageDetailDialog{ pkg, onEdit } )
   *   → 弹窗打开
   *   → 用户点击 ✏️ → onEdit 回调 → 关闭弹窗 → 跳转编辑页
   *
   * @param pkg 被点击的任务包数据
   */
  showPackageDetail(pkg: TaskPackage): void {
    /**
     * 每次点击卡片都创建新的 CustomDialogController。
     * 对话框的关闭操作通过 onClose 回调完成——
     * PackageDetailDialog 内部不直接调用 this.controller.close()，
     * 因为 @CustomDialog 的 controller 在 builder 内联创建时可能为 undefined。
     */
    const dialogController: CustomDialogController = new CustomDialogController({
      builder: PackageDetailDialog({
        package: pkg,
        /**
         * onClose 回调：弹窗需要关闭时调用。
         * 父组件持有真正的 dialogController，由父组件执行 close()。
         */
        onClose: () => {
          dialogController.close();
        },
        /**
         * onEdit 回调：弹窗中的 ✏️ 按钮点击后触发。
         *
         * 注意：onClose 已在 PackageDetailDialog 内部先调用，
         * 所以此处只需处理导航逻辑。
         */
        onEdit: (pkgId: string) => {
          router.pushUrl({
            url: 'pages/CreatePackage',
            params: { packageId: pkgId }
          });
        },
        onExport: (targetPackage: TaskPackage) => {
          this.sharePackage(targetPackage);
        }
      }),
      /** 点击半透明背景可关闭弹窗 */
      autoCancel: true,
      /** 弹窗居中显示 */
      alignment: DialogAlignment.Center,
      /** 启用自定义样式（使 cornerRadius 等生效） */
      customStyle: true,
      /** 弹窗圆角 */
      cornerRadius: 16,
    });
    // 打开弹窗
    dialogController.open();
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // ---- 标题栏 ----
        Row() {
          Text('我的任务包')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
          Button('导入')
            .fontSize(12)
            .onClick(() => this.showImportDialog())
          Button('复制诊断信息')
            .fontSize(12)
            .onClick(() => this.copyDiagnostics())
        }
        .width('100%')
        .padding({ left: 16, right: 12, top: 12, bottom: 12 })
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#F5F5F5')

        // ---- 内容区域 ----
        if (this.packages.length === 0) {
          // 空状态
          Column() {
            Blank()
            Text('暂无任务包，点击右下角 + 号创建')
              .fontSize(16)
              .fontColor('#999999')
              .textAlign(TextAlign.Center)
              .padding(20)
            Text('先创建任务包，再安排到日历，最后开始执行。')
              .fontSize(14)
              .fontColor('#777777')
              .textAlign(TextAlign.Center)
              .padding({ left: 24, right: 24, bottom: 16 })
            Button('创建自己的任务包')
              .onClick(() => router.pushUrl({ url: 'pages/CreatePackage' }))
              .margin({ bottom: 10 })
            Button('使用示例任务包')
              .enabled(!this.importingExamples)
              .onClick(() => { void this.importExamples(); })
            Blank()
          }
          .width('100%')
          .layoutWeight(1)
        } else {
          // 卡片列表
          List({ space: 12 }) {
            ForEach(this.packages,
              (item: TaskPackage) => {
                ListItem() {
                  // ---- 彩色卡片 ----
                  Column() {
                    // 主标题（加粗）
                    Text(item.name)
                      .fontSize(18)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#FFFFFF')
                      .width('100%')
                      .padding({ bottom: 8 })

                    // 步骤摘要
                    Text(this.getStepsSummary(item))
                      .fontSize(14)
                      .fontColor('#FFFFFF')
                      .opacity(0.9)
                      .width('100%')
                      .maxLines(3)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    // 底部行：步骤数量 + 总时长
                    Row() {
                      Text(`📋 ${item.steps.length} 个步骤`)
                        .fontSize(12)
                        .fontColor('#FFFFFF')
                        .opacity(0.8)

                      if (this.getTotalDuration(item) > 0) {
                        Text(' · ')
                          .fontSize(12)
                          .fontColor('#FFFFFF')
                          .opacity(0.6)

                        Text(`⏱ ${this.formatDuration(this.getTotalDuration(item))}`)
                          .fontSize(12)
                          .fontColor('#FFFFFF')
                          .opacity(0.8)
                      }

                      Blank()

                      Text('⟐')
                        .fontSize(16)
                        .fontColor('#FFFFFF')
                        .opacity(0.6)
                    }
                    .width('100%')
                    .padding({ top: 8 })
                  }
                  .width('100%')
                  .padding(16)
                  .borderRadius(12)
                  .backgroundColor(item.color)
                  .shadow({
                    radius: 4,
                    color: '#20000000',
                    offsetX: 0,
                    offsetY: 2
                  })
                  /**
                   * 点击卡片弹出详情弹窗。
                   *
                   * 注意：CalendarTab 左侧面板中的卡片使用 onDragStart 处理拖拽，
                   * 但 TaskPackageTab 中的卡片只需处理点击。短按 = 详情弹窗，
                   * 不干扰 CalendarTab 的长按拖拽逻辑。
                   */
                  .onClick(() => {
                    this.showPackageDetail(item);
                  })
                }
              },
              (item: TaskPackage) => `${item.id}-v${item._version}`
            )
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ top: 8, left: 12, right: 12 })
          .backgroundColor('#F0F0F0')
        }
      }
      .width('100%')
      .height('100%')

      // ---- 悬浮 + 按钮 ----
      Button('+')
        .fontSize(32)
        .fontWeight(FontWeight.Lighter)
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor('#007AFF')
        .fontColor('#FFFFFF')
        .shadow({
          radius: 8,
          color: '#40000000',
          offsetX: 0,
          offsetY: 4
        })
        .margin({ right: 24, bottom: 24 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/CreatePackage' });
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0F0F0')
  }
}

