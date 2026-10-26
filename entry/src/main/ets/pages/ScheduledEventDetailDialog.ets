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
  @State private timePickerVisible: boolean = false;
  @State private durationMenuVisible: boolean = false;
  @State private startHour: number = 0;
  @State private startMinute: number = 0;
  @State private selectedTime: Date = new Date(2000, 0, 1, 0, 0);
  @State private editedSteps: TaskStep[] = [];
  /** 打开详情时的基线；调整总时长时按此比例重算，以覆盖此前的单步调整。 */
  private originalSteps: TaskStep[] = [];

  @Builder
  placeholderBuilder() {}

  aboutToAppear(): void {
    if (!this.event) {
      return;
    }
    this.reminderEnabled = this.event.reminderEnabled !== false;
    this.startHour = this.event.startHour;
    this.startMinute = this.event.startMinute;
    this.selectedTime = new Date(2000, 0, 1, this.startHour, this.startMinute);
    this.originalSteps = this.copySteps(this.event.steps);
    this.editedSteps = this.copySteps(this.event.steps);
  }

  private copySteps(steps: TaskStep[]): TaskStep[] {
    return steps.map((step: TaskStep): TaskStep => {
      const copiedStep: TaskStep = { name: step.name, duration: step.duration };
      return copiedStep;
    });
  }

  private copyEvent(source: ScheduledEvent): ScheduledEvent {
    const copiedEvent: ScheduledEvent = {
      id: source.id,
      date: source.date,
      packageId: source.packageId,
      packageName: source.packageName,
      color: source.color,
      startHour: source.startHour,
      startMinute: source.startMinute,
      endHour: source.endHour,
      endMinute: source.endMinute,
      steps: this.copySteps(source.steps),
      reminderEnabled: source.reminderEnabled
    };
    return copiedEvent;
  }

  /** 保存当前日程副本；不会修改任务包模板。 */
  private saveSchedule(hour: number, minute: number, steps: TaskStep[]): boolean {
    if (!this.event) {
      return false;
    }
    const updated: ScheduledEvent = this.copyEvent(this.event);
    const copiedSteps: TaskStep[] = this.copySteps(steps);
    const totalDuration: number = getTotalDuration(copiedSteps);
    const startTotal: number = hour * 60 + minute;
    const endTotal: number = startTotal + totalDuration;
    if (!scheduleStore.canPlaceInterval(
      this.event.date, startTotal, totalDuration, this.event.id
    )) {
      promptAction.showToast({ message: '该时段已有两个任务包，无法应用调整', duration: 1800 });
      return false;
    }
    updated.startHour = hour;
    updated.startMinute = minute;
    updated.endHour = Math.floor(endTotal / 60) % 24;
    updated.endMinute = endTotal % 60;
    updated.steps = copiedSteps;
    this.event = updated;
    this.startHour = hour;
    this.startMinute = minute;
    this.editedSteps = copiedSteps;
    scheduleStore.updateEvent(updated);
    return true;
  }

  private toggleReminder(): void {
    if (!this.event) {
      return;
    }
    const updated: ScheduledEvent = this.copyEvent(this.event);
    this.reminderEnabled = !this.reminderEnabled;
    updated.reminderEnabled = this.reminderEnabled;
    this.event = updated;
    scheduleStore.updateEvent(updated);
    promptAction.showToast({
      message: this.reminderEnabled ? '已开启应用内通知' : '已关闭应用内通知',
      duration: 1600
    });
  }

  private deleteSchedule(): void {
    if (!this.event) {
      return;
    }
    const packageName: string = this.event.packageName;
    scheduleStore.removeEvent(this.event.id);
    if (this.onClose) {
      this.onClose();
    }
    promptAction.showToast({ message: `已删除“${packageName}”的本次安排`, duration: 1800 });
  }

  /** TimePicker 两列分别滑动；若任务会跨过当天末尾，则吸附到当天最晚可开始时间。 */
  private changeStartTime(value: TimePickerResult): void {
    const duration: number = getTotalDuration(this.editedSteps);
    const latestStart: number = Math.max(0, 1440 - duration);
    const requestedStart: number = value.hour * 60 + value.minute;
    const actualStart: number = Math.min(requestedStart, latestStart);
    const actualHour: number = Math.floor(actualStart / 60);
    const actualMinute: number = actualStart % 60;
    if (!this.saveSchedule(actualHour, actualMinute, this.editedSteps)) {
      this.selectedTime = new Date(2000, 0, 1, this.startHour, this.startMinute);
      return;
    }
    this.selectedTime = new Date(2000, 0, 1, actualHour, actualMinute);
    if (actualStart !== requestedStart) {
      promptAction.showToast({ message: '任务不能跨过当天，已调整到最晚开始时间', duration: 1800 });
    }
  }

  private changeStepDuration(index: number, delta: number): void {
    if (index < 0 || index >= this.editedSteps.length) {
      return;
    }
    const nextSteps: TaskStep[] = this.copySteps(this.editedSteps);
    const current: TaskStep = nextSteps[index];
    const nextDuration: number = Math.max(1, current.duration + delta);
    const nextTotal: number = getTotalDuration(nextSteps) - current.duration + nextDuration;
    const availableMinutes: number = 1440 - (this.startHour * 60 + this.startMinute);
    if (nextTotal > availableMinutes) {
      promptAction.showToast({ message: '调整后会跨过当天，无法继续增加', duration: 1600 });
      return;
    }
    current.duration = nextDuration;
    this.saveSchedule(this.startHour, this.startMinute, nextSteps);
  }

  /** 按打开详情时的原始比例缩放；最后一步补齐取整误差。 */
  private scaleOriginalSteps(targetDuration: number): TaskStep[] {
    if (this.originalSteps.length === 0) {
      return [];
    }
    const originalTotal: number = Math.max(1, getTotalDuration(this.originalSteps));
    const result: TaskStep[] = [];
    let assigned: number = 0;
    for (let index: number = 0; index < this.originalSteps.length - 1; index++) {
      const remainingSteps: number = this.originalSteps.length - index - 1;
      const proportional: number = Math.max(
        1,
        Math.round(this.originalSteps[index].duration * targetDuration / originalTotal)
      );
      const available: number = targetDuration - assigned - remainingSteps;
      const duration: number = Math.min(proportional, available);
      const scaledStep: TaskStep = {
        name: this.originalSteps[index].name,
        duration: duration
      };
      result.push(scaledStep);
      assigned += duration;
    }
    const lastStep: TaskStep = {
      name: this.originalSteps[this.originalSteps.length - 1].name,
      duration: targetDuration - assigned
    };
    result.push(lastStep);
    return result;
  }

  private changeTotalDuration(delta: number): void {
    if (this.originalSteps.length === 0) {
      return;
    }
    const currentTotal: number = getTotalDuration(this.editedSteps);
    const minimumTotal: number = this.originalSteps.length;
    const maximumTotal: number = 1440 - (this.startHour * 60 + this.startMinute);
    const targetTotal: number = Math.max(
      minimumTotal,
      Math.min(maximumTotal, currentTotal + delta)
    );
    if (targetTotal === currentTotal) {
      return;
    }
    const scaledSteps: TaskStep[] = this.scaleOriginalSteps(targetTotal);
    this.saveSchedule(this.startHour, this.startMinute, scaledSteps);
  }

  private originalStepDuration(index: number): number {
    if (index < 0 || index >= this.originalSteps.length) {
      return 0;
    }
    return this.originalSteps[index].duration;
  }

  private startTimeLabel(): string {
    return `${this.startHour.toString().padStart(2, '0')}:` +
      `${this.startMinute.toString().padStart(2, '0')}`;
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

  @Builder
  durationAdjustButton(label: string, onTap: () => void): void {
    Button(label)
      .width(28)
      .height(28)
      .fontSize(16)
      .fontColor(this.event?.color ?? '#007AFF')
      .backgroundColor('#F2F2F2')
      .padding(0)
      .onClick(onTap)
  }

  build() {
    if (this.event) {
      Column() {
        Row({ space: 6 }) {
          Text(this.event.packageName)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1A1A')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Button(this.reminderEnabled ? '🔔 通知' : '🔕 已关闭')
            .fontSize(11)
            .fontColor(this.reminderEnabled ? this.event.color : '#777777')
            .backgroundColor(this.reminderEnabled ? this.event.color + '18' : '#F2F2F2')
            .height(34)
            .padding({ left: 8, right: 8 })
            .onClick(() => { this.toggleReminder(); })
          Button('删除')
            .fontSize(11)
            .fontColor('#D83B3B')
            .backgroundColor('#FFF0F0')
            .height(34)
            .padding({ left: 9, right: 9 })
            .onClick(() => { this.deleteSchedule(); })
        }
        .width('100%')

        Row({ space: 8 }) {
          Button(this.startTimeLabel())
            .fontSize(13)
            .fontColor(this.timePickerVisible ? '#FFFFFF' : this.event.color)
            .backgroundColor(this.timePickerVisible ? this.event.color : '#F3F3F3')
            .height(34)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              this.timePickerVisible = !this.timePickerVisible;
              this.durationMenuVisible = false;
            })
          Button(`${getTotalDuration(this.editedSteps)} 分钟`)
            .fontSize(13)
            .fontColor(this.durationMenuVisible ? '#FFFFFF' : this.event.color)
            .backgroundColor(this.durationMenuVisible ? this.event.color : '#F3F3F3')
            .height(34)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              this.durationMenuVisible = !this.durationMenuVisible;
              this.timePickerVisible = false;
            })
          Blank()
        }
        .width('100%')
        .margin({ top: 10, bottom: 10 })

        if (this.timePickerVisible) {
          TimePicker({ selected: this.selectedTime })
            .useMilitaryTime(true)
            .height(170)
            .onChange((value: TimePickerResult) => { this.changeStartTime(value); })
        }

        if (this.durationMenuVisible) {
          Scroll() {
            Column() {
              ForEach(this.editedSteps, (step: TaskStep, index: number) => {
                Row({ space: 5 }) {
                  Text(`步骤${index + 1}：${step.name}`)
                    .fontSize(12)
                    .fontColor('#333333')
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${this.originalStepDuration(index)}分钟 →`)
                    .fontSize(11)
                    .fontColor('#888888')
                  this.durationAdjustButton('−', () => { this.changeStepDuration(index, -5); })
                  Text(`${step.duration}分钟`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.event!.color)
                    .width(48)
                    .textAlign(TextAlign.Center)
                  this.durationAdjustButton('+', () => { this.changeStepDuration(index, 5); })
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
              }, (step: TaskStep, index: number) =>
                `duration-step-${index}-${step.name}-${step.duration}`)

              Divider().color('#E8E8E8').margin({ top: 4, bottom: 4 })

              Row({ space: 5 }) {
                Text('总时长')
                  .fontSize(13)
                  .fontWeight(FontWeight.Bold)
                  .layoutWeight(1)
                Text(`${getTotalDuration(this.originalSteps)}分钟 →`)
                  .fontSize(11)
                  .fontColor('#888888')
                this.durationAdjustButton('−', () => { this.changeTotalDuration(-5); })
                Text(`${getTotalDuration(this.editedSteps)}分钟`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.event!.color)
                  .width(48)
                  .textAlign(TextAlign.Center)
                this.durationAdjustButton('+', () => { this.changeTotalDuration(5); })
              }
              .width('100%')
              .padding({ top: 8, bottom: 8 })
            }
            .width('100%')
          }
          .width('100%')
          .height(Math.min(260, 52 * (this.editedSteps.length + 1)))
          .padding({ left: 8, right: 8 })
          .backgroundColor('#FAFAFA')
          .borderRadius(10)
          .margin({ bottom: 8 })
        } else if (!this.timePickerVisible) {
          ForEach(this.editedSteps, (step: TaskStep, index: number) => {
            Row() {
              Text(`${index + 1}`).fontColor(this.event!.color).fontWeight(FontWeight.Bold).width(28)
              Text(step.name).layoutWeight(1).fontSize(16)
              Text(`${step.duration} 分钟`).fontSize(13).fontColor('#777777')
            }.width('100%').padding({ top: 8, bottom: 8 })
          }, (step: TaskStep, index: number) =>
            `scheduled-step-${index}-${step.name}-${step.duration}`)
        }

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
