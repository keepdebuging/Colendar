import { promptAction, router } from '@kit.ArkUI';
import { ScheduledEvent, getTotalDuration, scheduleStore } from '../models/ScheduledEvent';
import { ExecutionSession, executionStore } from '../models/ExecutionSession';
import { TaskStep } from '../models/TaskPackage';

@CustomDialog
export struct ScheduledEventDetailDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: this.placeholderBuilder });
  event: ScheduledEvent | undefined = undefined;
  onClose?: () => void;
  @State private reminderEnabled: boolean = true;

  @Builder
  placeholderBuilder() {}

  aboutToAppear(): void {
    this.reminderEnabled = this.event?.reminderEnabled !== false;
  }

  private toggleReminder(): void {
    if (!this.event) {
      return;
    }
    this.reminderEnabled = !this.reminderEnabled;
    this.event.reminderEnabled = this.reminderEnabled;
    scheduleStore.updateEvent(this.event);
    promptAction.showToast({
      message: this.reminderEnabled ? '已开启应用内通知' : '已关闭应用内通知',
      duration: 1600
    });
  }

  private startOrContinue(): void {
    if (!this.event) {
      return;
    }
    const previous: ExecutionSession | undefined = executionStore.getLatestSessionByEventId(this.event.id);
    const shouldPrepare: boolean = previous === undefined ||
      previous.status === 'completed' || previous.status === 'abandoned';
    const session: ExecutionSession | undefined = executionStore.startFromScheduledEvent(this.event);
    if (!session) {
      promptAction.showToast({ message: '请先结束或继续当前正在执行的任务', duration: 2200 });
      return;
    }
    if (this.onClose) {
      this.onClose();
    }
    router.pushUrl({
      url: 'pages/ExecutionPage',
      params: { sessionId: session.id, prepare: shouldPrepare ? 'true' : 'false' }
    });
  }

  build() {
    if (this.event) {
      Column() {
        Row() {
          Text(this.event.packageName)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button(this.reminderEnabled ? '🔔 通知' : '🔕 已关闭')
            .fontSize(12)
            .fontColor(this.reminderEnabled ? this.event.color : '#777777')
            .backgroundColor(this.reminderEnabled ? this.event.color + '18' : '#F2F2F2')
            .height(34)
            .padding({ left: 10, right: 10 })
            .onClick(() => { this.toggleReminder(); })
        }
        .width('100%')
        Text(`${this.event.startHour.toString().padStart(2, '0')}:${this.event.startMinute.toString().padStart(2, '0')} · ${getTotalDuration(this.event.steps)} 分钟`)
          .fontSize(14).fontColor('#777777').margin({ top: 8, bottom: 18 })
        ForEach(this.event.steps, (step: TaskStep, index: number) => {
          Row() {
            Text(`${index + 1}`).fontColor(this.event!.color).fontWeight(FontWeight.Bold).width(28)
            Text(step.name).layoutWeight(1).fontSize(16)
            Text(`${step.duration} 分钟`).fontSize(13).fontColor('#777777')
          }.width('100%').padding({ top: 8, bottom: 8 })
        }, (step: TaskStep, index: number) => `scheduled-step-${index}-${step.name}`)
        Button(this.getActionLabel())
          .width('100%').height(46).margin({ top: 18 }).backgroundColor(this.event.color).fontColor('#FFFFFF')
          .onClick(() => { this.startOrContinue(); })
        Button('关闭').width('100%').margin({ top: 10 }).backgroundColor('#F5F5F5').fontColor('#666666')
          .onClick(() => { if (this.onClose) { this.onClose(); } })
      }
      .width('88%').padding(22).backgroundColor('#FFFFFF').borderRadius(16)
    }
  }

  private getActionLabel(): string {
    if (!this.event) {
      return '开始任务';
    }
    const session: ExecutionSession | undefined = executionStore.getLatestSessionByEventId(this.event.id);
    if (!session) {
      return '开始任务';
    }
    return session.status === 'completed' || session.status === 'abandoned' ? '再次开始' : '继续任务';
  }
}
