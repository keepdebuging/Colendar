import { ScheduledEvent } from '../models/ScheduledEvent';

@CustomDialog
export struct UpcomingTaskDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: this.placeholderBuilder });
  event: ScheduledEvent | undefined = undefined;
  targetStartMs: number = 0;
  onStart?: () => void;
  onLater?: () => void;

  @State private secondsRemaining: number = 20;
  @State private confirmed: boolean = false;
  private countdownTimer: number = -1;
  private hasStarted: boolean = false;

  @Builder
  placeholderBuilder() {}

  aboutToAppear(): void {
    this.updateCountdown();
    this.countdownTimer = setInterval(() => {
      this.updateCountdown();
    }, 250);
  }

  aboutToDisappear(): void {
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
  }

  private updateCountdown(): void {
    this.secondsRemaining = Math.max(0, Math.ceil((this.targetStartMs - Date.now()) / 1000));
    if (this.secondsRemaining === 0) {
      this.startAtScheduledTime();
    }
  }

  private startAtScheduledTime(): void {
    if (this.hasStarted) {
      return;
    }
    this.hasStarted = true;
    if (this.onStart) {
      this.onStart();
    }
  }

  build() {
    if (this.event) {
      Column() {
        Text('即将开始')
          .fontSize(14)
          .fontColor(this.event.color)
          .fontWeight(FontWeight.Medium)
        Text(`“${this.event.packageName}”任务即将开始，确认开始吗？`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .textAlign(TextAlign.Center)
          .margin({ top: 12, bottom: 22 })

        Row({ space: 12 }) {
          Button(this.confirmed ? `已确认（${this.secondsRemaining}秒）` : `确认（${this.secondsRemaining}秒）`)
            .layoutWeight(1)
            .height(44)
            .fontColor('#FFFFFF')
            .backgroundColor(this.event.color)
            .enabled(!this.confirmed)
            .onClick(() => { this.confirmed = true; })
          Button('稍后')
            .layoutWeight(1)
            .height(44)
            .fontColor('#555555')
            .backgroundColor('#F2F2F2')
            .onClick(() => {
              if (this.onLater) {
                this.onLater();
              }
            })
        }
        .width('100%')
      }
      .width('88%')
      .padding(24)
      .backgroundColor('#FFFFFF')
      .borderRadius(18)
    }
  }
}

