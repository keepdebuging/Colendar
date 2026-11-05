/**
 * PackageDetailDialog.ets —— 任务包详情弹窗
 *
 * 用途：在任务包列表（Tab1）点击彩色卡片时弹出，展示任务包的
 * 完整信息（名称、步骤详情），并提供"编辑"入口。
 *
 * 重要：此组件不直接调用 this.controller.close()。
 * 取而代之的是通过 onClose 回调通知父组件来关闭弹窗。
 * 原因：@CustomDialog 的 controller 字段由框架注入，在 builder 内
 * 联创建的实例中 controller 可能为 undefined，导致运行时空指针崩溃。
 *
 * 使用方式（在父组件中）：
 *   const ctrl = new CustomDialogController({
 *     builder: PackageDetailDialog({ package: pkg, onEdit: cb, onClose: cb }),
 *     autoCancel: true, alignment: DialogAlignment.Center,
 *     customStyle: true, cornerRadius: 16,
 *   });
 *   ctrl.open();
 */

import { promptAction, router } from '@kit.ArkUI';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { harmonyShare, systemShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { TaskPackage, TaskStep, generateId } from '../models/TaskPackage';
import { ScheduledEvent } from '../models/ScheduledEvent';
import { ExecutionSession, executionStore } from '../models/ExecutionSession';
import { validateSteps } from '../domain/Validation';
import { copyTaskActions } from '../models/TaskAction';
import { exportTaskPackage } from '../utils/TaskPackageTransfer';

/**
 * 详情弹窗组件
 *
 * @CustomDialog 装饰器标记此 struct 为对话框内容。
 * 框架会自动处理对话框的显示与隐藏动画。
 */
@CustomDialog
export struct PackageDetailDialog {
  /**
   * 系统注入的对话框控制器。
   *
   * 默认值用 placeholderBuilder 满足 ArkTS 编译器要求。
   * 实际运行时此字段可能被框架覆盖为 undefined——
   * 因此弹窗内的关闭操作必须通过 onClose 回调完成，
   * 不能依赖 this.controller.close()。
   */
  controller: CustomDialogController = new CustomDialogController({
    builder: this.placeholderBuilder,
    autoCancel: true
  });

  /**
   * 占位 @Builder，仅供 controller 初始化使用。
   * 实际弹窗内容由 build() 方法定义。
   */
  @Builder
  placeholderBuilder() {
  }

  /**
   * 要展示的任务包数据。
   * 由父组件在创建 CustomDialogController 时传入。
   */
  package: TaskPackage = {
    id: '',
    name: '',
    steps: [],
    color: '#007AFF',
    _version: 0
  };

  /**
   * 当用户点击「✏️ 编辑」按钮时的回调。
   *
   * 父组件（TaskPackageTab）负责：
   * 1. 调用 ctrl.close() 关闭弹窗
   * 2. 调用 router.pushUrl 跳转到编辑页面
   */
  onEdit?: (pkgId: string) => void;

  /** 由父组件拉起系统分享面板，导出可再次导入的模板文本。 */
  onExport?: (pkg: TaskPackage) => void;

  /**
   * 当需要关闭弹窗时的回调（关闭按钮 / 编辑按钮均触发）。
   *
   * 父组件持有真正的 CustomDialogController 引用，
   * 由父组件调用 ctrl.close() 完成实际关闭操作。
   */
  onClose?: () => void;

  private knockShareCallback: (target: harmonyShare.SharableTarget) => void =
    (target: harmonyShare.SharableTarget): void => {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        title: `${this.package.name} · Colendar 任务包`,
        content: exportTaskPackage(this.package)
      });
      target.share(data).catch((error: BusinessError) => {
        promptAction.showToast({ message: `碰一碰分享失败：${error.message}`, duration: 2200 });
      });
    };

  /** 详情页可见期间才注册近场分享，避免后台长期暴露分享内容。 */
  aboutToAppear(): void {
    try {
      harmonyShare.on('knockShare', this.knockShareCallback);
    } catch (_error) {
      // 不支持碰一碰或服务未开启时，仍保留普通系统分享入口。
    }
  }

  aboutToDisappear(): void {
    try {
      harmonyShare.off('knockShare', this.knockShareCallback);
    } catch (_error) {
      // 未注册成功时无需额外处理。
    }
  }

  /**
   * 计算任务包总时长（分钟），用于底部统计信息。
   */
  getTotalMinutes(): number {
    if (!this.package.steps || this.package.steps.length === 0) {
      return 0;
    }
    return this.package.steps.reduce(
      (sum: number, s: TaskStep) => sum + s.duration, 0
    );
  }

  /**
   * 格式化总时长为可读字符串。
   */
  getDurationText(): string {
    const total: number = this.getTotalMinutes();
    if (total === 0) {
      return '暂无步骤';
    }
    if (total >= 60) {
      const hours: number = Math.floor(total / 60);
      const mins: number = total % 60;
      if (mins > 0) {
        return `总时长 ${hours}小时${mins}分钟`;
      }
      return `总时长 ${hours}小时`;
    }
    return `总时长 ${total}分钟`;
  }

  /**
   * 从模板直接开始不会新增日历日程；它只创建带当前模板快照的执行会话。
   */
  async startNow(): Promise<void> {
    const validationMessage: string = validateSteps(this.package.steps);
    if (validationMessage !== '') {
      promptAction.showToast({ message: validationMessage, duration: 2000 });
      return;
    }
    const active: ExecutionSession | undefined = executionStore.getActiveSession();
    if (active) {
      promptAction.showToast({
        message: '已有未结束的任务，请通过首页继续执行或结束任务',
        duration: 2200
      });
      return;
    }
    const now: Date = new Date();
    const totalMinutes: number = this.getTotalMinutes();
    const endMinutes: number = now.getHours() * 60 + now.getMinutes() + totalMinutes;
    const quickEvent: ScheduledEvent = {
      id: `quick-${generateId()}`,
      date: `${now.getFullYear()}-${(now.getMonth() + 1).toString().padStart(2, '0')}-${now.getDate().toString().padStart(2, '0')}`,
      packageId: this.package.id,
      packageName: this.package.name,
      color: this.package.color,
      startHour: now.getHours(),
      startMinute: now.getMinutes(),
      endHour: Math.floor(endMinutes / 60),
      endMinute: endMinutes % 60,
      steps: this.package.steps.map((step: TaskStep) => {
        const copiedStep: TaskStep = { name: step.name, duration: step.duration };
        return copiedStep;
      }),
      actions: copyTaskActions(this.package.actions)
    };
    let session: ExecutionSession | undefined;
    try {
      session = await executionStore.startFromScheduledEvent(quickEvent);
    } catch (_error) {
      promptAction.showToast({ message: '无法开始任务，请检查步骤时长', duration: 2200 });
      return;
    }
    if (!session) {
      promptAction.showToast({ message: '请先结束或继续当前正在执行的任务', duration: 2200 });
      return;
    }
    if (this.onClose) {
      this.onClose();
    }
    router.pushUrl({
      url: 'pages/ExecutionPage',
      params: { sessionId: session.id, prepare: 'true' }
    });
  }

  build() {
    Column() {
      // ==================== 标题栏：名称 + 编辑按钮 ====================
      Row() {
        // ---- 任务包名称（大号加粗） ----
        Text(this.package.name)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        // ---- 编辑按钮（右上角，键槽型） ----
        Button('✏ 编辑')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.package.color)
          .backgroundColor(this.package.color + '20')
          .height(32)
          .borderRadius(16)
          .padding({ left: 14, right: 14 })
          /**
           * 点击编辑按钮：
           * 1. 先通过 onClose 回调让父组件关闭弹窗
           * 2. 再通过 onEdit 回调让父组件跳转编辑页
           *
           * 不使用 this.controller.close() —— controller 可能为 undefined
           */
          .onClick(() => {
            if (this.onClose) {
              this.onClose();
            }
            if (this.onEdit) {
              this.onEdit(this.package.id);
            }
          })
      }
      .width('100%')
      .padding({ left: 20, right: 12, top: 20, bottom: 12 })

      // ---- 主题色装饰线 ----
      Divider()
        .height(3)
        .color(this.package.color)
        .width('100%')

      // ==================== 步骤列表 ====================
      Column() {
        // 小标题
        Row() {
          Text(`步骤列表 (${this.package.steps.length})`)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#888888')
        }
        .width('100%')
        .padding({ left: 20, top: 16, bottom: 8 })

        Scroll() {
          Column() {
            if (this.package.steps.length === 0) {
              Text('暂无步骤')
                .fontSize(14)
                .fontColor('#BBBBBB')
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(24)
            } else {
              ForEach(this.package.steps,
                (step: TaskStep, index: number) => {
                  Row() {
                    // 序号圆点
                    Text(`${index + 1}`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Bold)
                      .fontColor('#FFFFFF')
                      .width(22)
                      .height(22)
                      .borderRadius(11)
                      .backgroundColor(this.package.color)
                      .textAlign(TextAlign.Center)

                    // 步骤名称
                    Text(step.name)
                      .fontSize(16)
                      .fontColor('#333333')
                      .layoutWeight(1)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .padding({ left: 12, right: 8 })

                    // 时长标签
                    Text(`${step.duration} 分钟`)
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.package.color)
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .borderRadius(12)
                      .backgroundColor(this.package.color + '15')
                  }
                  .width('100%')
                  .padding({ left: 20, right: 16, top: 8, bottom: 8 })
                },
                (_step: TaskStep, index: number) => `${this.package.id}-step-${index}`
              )
            }
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 300 })
        .scrollable(
          this.package.steps.length > 6 ? ScrollDirection.Vertical : ScrollDirection.None
        )
      }
      .width('100%')

      // ---- 分割线 ----
      Divider()
        .margin({ top: 12, left: 20, right: 20 })
        .color('#F0F0F0')

      // ==================== 底部信息区 ====================
      Column() {
        // 总时长统计
        Row() {
          Text('⏱')
            .fontSize(14)
          Text(this.getDurationText())
            .fontSize(14)
            .fontColor('#666666')
            .padding({ left: 4 })
        }
        .width('100%')
        .padding({ left: 20, top: 12, bottom: 16 })

        // ---- 快速开始按钮：尺寸与关闭一致，视觉与顶部编辑按钮一致 ----
        Button('现在开始吧！')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.package.color)
          .backgroundColor(this.package.color + '20')
          .width('calc(100% - 40px)')
          .height(44)
          .borderRadius(22)
          .margin({ bottom: 10 })
          .onClick(() => { this.startNow(); })

        Button('导出模板')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.package.color)
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: this.package.color + '80' })
          .width('calc(100% - 40px)')
          .height(44)
          .borderRadius(22)
          .margin({ bottom: 10 })
          .onClick(() => {
            if (this.onExport) {
              this.onExport(this.package);
            }
          })

        Text('详情页打开时可用碰一碰分享；不支持时请使用“导出模板”')
          .fontSize(11)
          .fontColor('#999999')
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ left: 12, right: 12, bottom: 10 })

        // ---- 关闭按钮（通过 onClose 回调通知父组件） ----
        Button('关 闭')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#666666')
          .backgroundColor('#F5F5F5')
          .width('calc(100% - 40px)')
          .height(44)
          .borderRadius(22)
          .onClick(() => {
            if (this.onClose) {
              this.onClose();
            }
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, bottom: 20 })
    }
    .width('88%')
    .backgroundColor('#FFFFFF')
    .borderRadius(16)
  }
}

