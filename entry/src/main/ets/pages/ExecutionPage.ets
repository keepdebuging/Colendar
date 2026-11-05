import { promptAction, router, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ExecutionSession, ExecutionStepRecord, executionStore, getStepRemainingMs } from '../models/ExecutionSession';
import { reportError } from '../diagnostics/AppLogger';
import { ActionRunResult, runTaskActions } from '../utils/TaskActionExecutor';

@Entry
@Component
struct ExecutionPage {
  @State nowMs: number = Date.now();
  @State session: ExecutionSession | undefined = undefined;
  @State presentationReady: boolean = false;
  @State backgroundReady: boolean = false;
  @State preparing: boolean = false;
  @State countdownVisible: boolean = false;
  @State preparationNumber: number = 3;
  @State confirmedDirection: string = '';
  private tickTimer: number = -1;
  private confirmTimer: number = -1;
  private backgroundTimer: number = -1;
  private preparationDelayTimer: number = -1;
  private preparationTimer: number = -1;
  private sessionId: string = '';
  private reconciling: boolean = false;

  aboutToAppear(): void {
    const params: Record<string, string> = router.getParams() as Record<string, string>;
    this.sessionId = params.sessionId || '';
    const prepare: boolean = params.prepare === 'true';
    this.preparing = prepare;
    void this.initializeSession(prepare);
    this.setLandscape(true);
    this.tickTimer = setInterval(() => {
      this.nowMs = Date.now();
      this.reconcileIfNeeded();
    }, 250);
    this.backgroundTimer = setTimeout(() => {
      animateTo({ duration: 550, curve: Curve.EaseInOut }, () => {
        this.backgroundReady = true;
        if (!this.preparing) {
          this.presentationReady = true;
        }
      });
    }, 80);
  }

  private async initializeSession(prepare: boolean): Promise<void> {
    try {
      await executionStore.reconcile(this.sessionId, Date.now());
      this.refreshSession();
      if (prepare) {
        await this.prepareNewSession();
      } else {
        this.runCurrentActions();
      }
    } catch (_error) {
      this.refreshSession();
      this.preparing = false;
      promptAction.showToast({ message: '恢复任务失败，已保留原执行记录' });
    }
  }

  private async prepareNewSession(): Promise<void> {
    if (!this.session || this.session.status !== 'running') {
      this.preparing = false;
      return;
    }
    try {
      this.preparing = await executionStore.prepareNewSession(this.session.id);
      this.refreshSession();
      if (this.preparing) {
        this.preparationDelayTimer = setTimeout(() => this.startPreparationCountdown(), 650);
      }
    } catch (_error) {
      this.preparing = false;
      promptAction.showToast({ message: '无法保存准备状态，请重试' });
    }
  }

  aboutToDisappear(): void {
    if (this.tickTimer !== -1) {
      clearInterval(this.tickTimer);
    }
    if (this.confirmTimer !== -1) {
      clearTimeout(this.confirmTimer);
    }
    if (this.backgroundTimer !== -1) {
      clearTimeout(this.backgroundTimer);
    }
    if (this.preparationDelayTimer !== -1) {
      clearTimeout(this.preparationDelayTimer);
    }
    if (this.preparationTimer !== -1) {
      clearInterval(this.preparationTimer);
    }
    this.setLandscape(false);
  }

  private startPreparationCountdown(): void {
    this.preparationNumber = 3;
    this.countdownVisible = true;
    this.preparationTimer = setInterval(() => {
      if (this.preparationNumber > 1) {
        this.preparationNumber--;
        return;
      }
      clearInterval(this.preparationTimer);
      this.preparationTimer = -1;
      this.countdownVisible = false;
      if (this.session) {
        void this.resumeAfterPreparation(this.session.id);
      } else {
        this.preparing = false;
      }
    }, 1000);
  }

  private async resumeAfterPreparation(sessionId: string): Promise<void> {
    try {
      await executionStore.resume(sessionId);
      this.refreshSession();
      this.runCurrentActions();
      this.preparing = false;
      animateTo({ duration: 420, curve: Curve.EaseInOut }, () => {
        this.presentationReady = true;
      });
    } catch (_error) {
      this.preparing = false;
      promptAction.showToast({ message: '无法继续执行，请检查保存状态' });
    }
  }

  private setLandscape(landscape: boolean): void {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(context).then((lastWindow: window.Window) => {
        lastWindow.setPreferredOrientation(
          landscape ? window.Orientation.LANDSCAPE : window.Orientation.PORTRAIT
        ).catch((_error: Error) => reportError('execution.orientation', 'WINDOW_ORIENTATION_FAILED'));
        // 组件级安全区扩展无法改变窗口本身的可用布局范围；执行页进入沉浸式布局。
        lastWindow.setWindowLayoutFullScreen(landscape)
          .catch((_error: Error) => reportError('execution.layout', 'WINDOW_FULLSCREEN_FAILED'));
      }).catch((_error: Error) => reportError('execution.window', 'GET_LAST_WINDOW_FAILED'));
    } catch (_error) {
      reportError('execution.window', 'GET_LAST_WINDOW_FAILED');
    }
  }

  private refreshSession(): void {
    this.session = executionStore.getSessionById(this.sessionId);
    this.nowMs = Date.now();
  }

  private reconcileIfNeeded(): void {
    if (!this.session || this.session.status !== 'running') {
      return;
    }
    const step: ExecutionStepRecord | undefined = this.session.steps[this.session.currentStepIndex];
    if (step && getStepRemainingMs(step, this.nowMs) === 0) {
      void this.completeExpiredStep(this.session.id, this.nowMs);
    }
  }

  private async completeExpiredStep(sessionId: string, nowMs: number): Promise<void> {
    if (this.reconciling) {
      return;
    }
    this.reconciling = true;
    try {
      await executionStore.completeCurrentStep(sessionId, nowMs);
      this.refreshSession();
      this.runCurrentActions();
      this.leaveIfFinished();
    } catch (_error) {
      promptAction.showToast({ message: '步骤状态保存失败，当前任务已保留' });
    } finally {
      this.reconciling = false;
    }
  }

  private currentStep(): ExecutionStepRecord | undefined {
    return this.session?.steps[this.session.currentStepIndex];
  }

  /** 外部动作失败只提示，不改变执行会话或倒计时。 */
  private runCurrentActions(): void {
    if (!this.session || this.session.status !== 'running') {
      return;
    }
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    runTaskActions(context, this.session, 'session-start', this.session.currentStepIndex)
      .then((results: ActionRunResult[]) => { this.showActionFailures(results); })
      .catch((_error: Error) => { promptAction.showToast({ message: '关联动作状态保存失败，任务仍在继续' }); });
    runTaskActions(context, this.session, 'step-start', this.session.currentStepIndex)
      .then((results: ActionRunResult[]) => { this.showActionFailures(results); })
      .catch((_error: Error) => { promptAction.showToast({ message: '关联动作状态保存失败，任务仍在继续' }); });
  }

  private showActionFailures(results: ActionRunResult[]): void {
    if (results.some((result: ActionRunResult) => !result.succeeded)) {
      promptAction.showToast({ message: '部分关联动作无法打开，计时已继续', duration: 1800 });
    }
  }

  private formatTime(milliseconds: number): string {
    const seconds: number = Math.ceil(Math.max(0, milliseconds) / 1000);
    return `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${(seconds % 60).toString().padStart(2, '0')}`;
  }

  private previousName(): string {
    if (!this.session || this.session.currentStepIndex === 0) {
      return '无';
    }
    return this.session.steps[this.session.currentStepIndex - 1].name;
  }

  private nextName(): string {
    if (!this.session || this.session.currentStepIndex >= this.session.steps.length - 1) {
      return '完成！';
    }
    return this.session.steps[this.session.currentStepIndex + 1].name;
  }

  private confirm(direction: string): void {
    if (!this.session) {
      return;
    }
    if (direction === 'previous' && this.session.currentStepIndex === 0) {
      this.confirmedDirection = 'first-step';
      promptAction.showToast({ message: '现在已经是第一个步骤', duration: 2200 });
      if (this.confirmTimer !== -1) {
        clearTimeout(this.confirmTimer);
      }
      this.confirmTimer = setTimeout(() => { this.confirmedDirection = ''; }, 2200);
      return;
    }
    if (this.confirmedDirection === direction) {
      this.confirmedDirection = '';
      void this.applyStepAction(this.session.id, direction);
      return;
    }
    this.confirmedDirection = direction;
    promptAction.showToast({
      message: `再次点击快速切换${direction === 'next' ? '下一个' : '上一个'}步骤`,
      duration: 2200
    });
    if (this.confirmTimer !== -1) {
      clearTimeout(this.confirmTimer);
    }
    this.confirmTimer = setTimeout(() => { this.confirmedDirection = ''; }, 2200);
  }

  private async applyStepAction(sessionId: string, direction: string): Promise<void> {
    try {
      if (direction === 'next') {
        await executionStore.skipCurrentStep(sessionId);
      } else {
        await executionStore.restartPreviousStep(sessionId);
      }
      this.refreshSession();
      this.runCurrentActions();
      this.leaveIfFinished();
    } catch (_error) {
      promptAction.showToast({ message: '步骤状态保存失败' });
    }
  }

  private togglePause(): void {
    if (!this.session) {
      return;
    }
    void this.togglePauseAsync(this.session.id, this.session.status);
  }

  private async startNextStep(sessionId: string): Promise<void> {
    try {
      await executionStore.startNextStep(sessionId);
      this.refreshSession();
      this.runCurrentActions();
      promptAction.showToast({ message: '倒计时已开始', duration: 1800 });
    } catch (_error) {
      promptAction.showToast({ message: '保存失败，任务仍保留在当前步骤' });
    }
  }

  private async togglePauseAsync(sessionId: string, status: string): Promise<void> {
    try {
      if (status === 'running') {
        await executionStore.pause(sessionId);
        promptAction.showToast({ message: '倒计时已暂停', duration: 1800 });
      } else if (status === 'paused') {
        await executionStore.resume(sessionId);
        promptAction.showToast({ message: '倒计时已开始', duration: 1800 });
      }
      this.refreshSession();
      this.runCurrentActions();
    } catch (_error) {
      promptAction.showToast({ message: '保存失败，任务状态未更改' });
    }
  }

  private finishTask(): void {
    if (!this.session) {
      return;
    }
    void this.finishTaskAsync(this.session.id);
  }

  private async finishTaskAsync(sessionId: string): Promise<void> {
    try {
      await executionStore.abandon(sessionId);
      router.back();
    } catch (_error) {
      promptAction.showToast({ message: '结束任务失败，原任务已保留' });
    }
  }

  private leaveIfFinished(): void {
    if (this.session && this.session.status === 'completed') {
      setTimeout(() => { router.back(); }, 450);
    }
  }

  /** Returns total elapsed chapter time, including the current step's live countdown. */
  private overallProgressPercent(session: ExecutionSession): number {
    let totalMs: number = 0;
    let elapsedMs: number = 0;
    for (const step of session.steps) {
      totalMs += step.plannedDurationMs;
      if (step.status === 'completed' || step.status === 'skipped') {
        elapsedMs += step.plannedDurationMs;
      } else if (step.status === 'running') {
        elapsedMs += step.plannedDurationMs - getStepRemainingMs(step, this.nowMs);
      }
    }
    if (totalMs === 0) {
      return 0;
    }
    return Math.min(100, Math.max(0, elapsedMs / totalMs * 100));
  }

  @Builder
  buildTimeline(session: ExecutionSession): void {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Row() {
          ForEach(session.steps, (step: ExecutionStepRecord) => {
            Row()
              .height(4)
              .backgroundColor('#FFFFFF55')
              .layoutWeight(Math.max(1, Math.floor(step.plannedDurationMs / 60000)))
          }, (step: ExecutionStepRecord) => `timeline-track-${step.index}`)
        }
        .width('100%')
        Row()
          .height(4)
          .width(`${this.overallProgressPercent(session)}%`)
          .backgroundColor('#FFFFFF')
          .animation({ duration: 250, curve: Curve.Linear })

        // 置于累计填充层之上的章节边界，已完成章节仍能清晰分辨。
        Row() {
          ForEach(session.steps, (step: ExecutionStepRecord, index: number) => {
            Column()
              .height(8)
              .border({
                width: { right: index < session.steps.length - 1 ? 1 : 0 },
                color: '#FFFFFFDD'
              })
              .layoutWeight(Math.max(1, Math.floor(step.plannedDurationMs / 60000)))
          }, (step: ExecutionStepRecord) => `timeline-divider-${step.index}`)
        }
        .width('100%')
      }
      .width('100%')
      .height(8)

      Row() {
        ForEach(session.steps, (step: ExecutionStepRecord, index: number) => {
          Text(step.name)
            .fontSize(10)
            .fontColor('#FFFFFF')
            .opacity(index === session.currentStepIndex ? 1 : 0.75)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
            .layoutWeight(Math.max(1, Math.floor(step.plannedDurationMs / 60000)))
        }, (step: ExecutionStepRecord) => `timeline-label-${step.index}`)
      }
      .width('100%')
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ top: 22 })
    .id('execution-progress')
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        if (this.session && !this.preparing) {
          this.buildTimeline(this.session)
          Blank().layoutWeight(1)
          Text(this.formatTime(getStepRemainingMs(this.currentStep()!, this.nowMs)))
            .fontSize(76)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .opacity(this.presentationReady ? 1 : 0)
            .scale({ x: this.presentationReady ? 1 : 0.9, y: this.presentationReady ? 1 : 0.9 })
            .animation({ duration: 350, curve: Curve.EaseInOut })
            .id('execution-timer')
          Text(this.currentStep()!.name)
            .fontSize(28)
            .fontWeight(FontWeight.Medium)
            .fontColor('#FFFFFF')
            .margin({ top: 12 })
            .transition({ type: TransitionType.All, opacity: 0, scale: { x: 0.86, y: 0.86 } })
            .id('execution-step-name')
          Text(`${this.session.currentStepIndex + 1} / ${this.session.steps.length} · ${this.session.packageName}`)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .opacity(0.78)
            .margin({ top: 8 })
            .id('execution-title')
          Blank().layoutWeight(1)
          Row({ space: 14 }) {
            if (this.session.status === 'waiting-next') {
              Button('开始下一步')
                .id('execution-start-next')
                .onClick(() => {
                  void this.startNextStep(this.session!.id);
                })
            } else {
              Button(this.session.status === 'paused' ? '继续' : '暂停')
                .id('execution-pause-resume')
                .onClick(() => { this.togglePause(); })
            }
            Button('结束任务')
              .id('execution-abandon')
              .fontColor('#FFFFFF')
              .backgroundColor('#FFFFFF33')
              .onClick(() => { this.finishTask(); })
          }
          .margin({ bottom: 24 })
        } else if (!this.session) {
          Text('找不到执行会话').fontColor('#333333')
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.backgroundReady && this.session ? this.session.color : '#FFFFFF')

      if (this.session && this.preparing && this.countdownVisible) {
        Text(this.preparationNumber.toString())
          .fontSize(112)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .textAlign(TextAlign.Center)
          .transition({ type: TransitionType.All, opacity: 0, scale: { x: 0.72, y: 0.72 } })
          .animation({ duration: 260, curve: Curve.EaseInOut })
      }

      if (this.session && !this.preparing) {
        Row() {
          Column() {
            Text('←').fontSize(30).fontColor('#FFFFFF')
            Text(this.previousName())
              .fontSize(17).fontColor('#FFFFFF').opacity(0.75).maxLines(2).textAlign(TextAlign.Center)
            if (this.confirmedDirection === 'first-step') {
              Text('现在已经是第一个步骤')
                .fontSize(11).fontColor('#FFFFFF').margin({ top: 8 })
            } else if (this.confirmedDirection === 'previous') {
              Text('再次点击快速切换上一步骤')
                .fontSize(11).fontColor('#FFFFFF').margin({ top: 8 })
            }
          }
          .width(150)
          .alignItems(HorizontalAlign.Center)
          .id('execution-previous-step')
          .onClick(() => { this.confirm('previous'); })

          Blank().layoutWeight(1)

          Column() {
            Text('→').fontSize(30).fontColor('#FFFFFF')
            Text(this.nextName())
              .fontSize(17).fontColor('#FFFFFF').opacity(0.75).maxLines(2).textAlign(TextAlign.Center)
            if (this.confirmedDirection === 'next') {
              Text('再次点击快速切换下一个步骤')
                .fontSize(11).fontColor('#FFFFFF').margin({ top: 8 })
            }
          }
          .width(150)
          .alignItems(HorizontalAlign.Center)
          .id('execution-next-step')
          .onClick(() => { this.confirm('next'); })
        }
        .width('100%')
        .height(140)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 24, right: 24 })
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea(
      [SafeAreaType.SYSTEM],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END]
    )
    .id('execution-page')
  }
}

