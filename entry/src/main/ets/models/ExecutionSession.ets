import {
  ExecutionSession as ExecutionSessionModel,
  ExecutionStepRecord as ExecutionStepRecordModel,
  ExecutionStatus,
  ExecutionStepStatus,
  ScheduledEvent,
  TaskStep
} from '../types/Models';
import { generateId } from './TaskPackage';
import { validateEvent } from '../domain/Validation';
import { appStore } from '../state/AppStore';
import { copyTaskActions } from './TaskAction';

export type { ExecutionStatus, ExecutionStepStatus } from '../types/Models';
export interface ExecutionStepRecord extends ExecutionStepRecordModel {}
export interface ExecutionSession extends ExecutionSessionModel {}

export function getStepRemainingMs(step: ExecutionStepRecord, nowMs: number): number {
  if (step.status !== 'running' || step.runStartedAt === 0) {
    return Math.max(0, step.remainingMs);
  }
  return Math.max(0, step.remainingMs - (nowMs - step.runStartedAt));
}

type SessionChange = (session: ExecutionSession) => boolean;

class ExecutionStore {
  private listeners: Array<() => void> = [];

  public get sessions(): ExecutionSession[] {
    return appStore.snapshot.sessions as ExecutionSession[];
  }

  public restore(): void {
    appStore.restore();
  }

  public getSessionById(sessionId: string): ExecutionSession | undefined {
    return this.sessions.find((session: ExecutionSession) => session.id === sessionId);
  }

  public getActiveSession(): ExecutionSession | undefined {
    return this.sessions.find((session: ExecutionSession) => this.isActive(session));
  }

  /** Reconcile the single active session after the app returns to the foreground. */
  public async reconcileActive(nowMs: number = Date.now()): Promise<void> {
    const active: ExecutionSession | undefined = this.getActiveSession();
    if (active && active.status === 'running') {
      await this.reconcile(active.id, nowMs);
    }
  }

  public getLatestSessionByEventId(eventId: string): ExecutionSession | undefined {
    const matches: ExecutionSession[] = this.sessions.filter(
      (session: ExecutionSession) => session.scheduledEventId === eventId
    );
    return matches.length > 0 ? matches[matches.length - 1] : undefined;
  }

  public async startFromScheduledEvent(
    event: ScheduledEvent,
    nowMs: number = Date.now()
  ): Promise<ExecutionSession | undefined> {
    const latest: ExecutionSession | undefined = this.getLatestSessionByEventId(event.id);
    if (latest && this.isActive(latest)) {
      return latest;
    }
    if (this.getActiveSession()) {
      return undefined;
    }
    const validationError: string = validateEvent(event);
    if (validationError !== '') {
      throw new Error(validationError);
    }
    const steps: ExecutionStepRecord[] = event.steps.map((step: TaskStep, index: number) => {
      const duration: number = step.duration * 60000;
      const record: ExecutionStepRecord = {
        index,
        name: step.name,
        plannedDurationMs: duration,
        status: index === 0 ? 'running' : 'pending',
        elapsedActiveMs: 0,
        runStartedAt: index === 0 ? nowMs : 0,
        remainingMs: duration,
        completedAt: 0
      };
      return record;
    });
    const session: ExecutionSession = {
      id: generateId(),
      scheduledEventId: event.id,
      sourcePackageId: event.packageId,
      packageName: event.packageName,
      color: event.color,
      steps,
      actions: copyTaskActions(event.actions),
      executedActionIds: [],
      currentStepIndex: 0,
      status: 'running',
      startedAt: nowMs,
      completedAt: 0,
      updatedAt: nowMs
    };
    await appStore.mutate((draft) => {
      if (draft.sessions.some((candidate) => this.isActive(candidate))) {
        throw new Error('已有未结束的任务');
      }
      draft.sessions.push(session);
    });
    this.notifyChange();
    return session;
  }

  /** Holds a brand-new session at its full first-step duration during preparation. */
  public async prepareNewSession(sessionId: string, nowMs: number = Date.now()): Promise<boolean> {
    const current: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!current || current.status !== 'running' || current.currentStepIndex !== 0 || !current.steps[0]) {
      return false;
    }
    const expectedStepIndex: number = current.currentStepIndex;
    return this.mutateSession(sessionId, (session) => {
      if (session.status !== 'running' || session.currentStepIndex !== expectedStepIndex) {
        return false;
      }
      const firstStep: ExecutionStepRecord = session.steps[0];
      firstStep.status = 'running';
      firstStep.elapsedActiveMs = 0;
      firstStep.remainingMs = firstStep.plannedDurationMs;
      firstStep.runStartedAt = 0;
      firstStep.completedAt = 0;
      session.status = 'paused';
      session.updatedAt = nowMs;
      return true;
    });
  }

  public async pause(sessionId: string, nowMs: number = Date.now()): Promise<boolean> {
    const current: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!current || current.status !== 'running') {
      return false;
    }
    const expectedStepIndex: number = current.currentStepIndex;
    return this.mutateSession(sessionId, (session) => {
      if (session.status !== 'running' || session.currentStepIndex !== expectedStepIndex) {
        return false;
      }
      this.settleRunningStep(session, nowMs);
      session.status = 'paused';
      session.updatedAt = nowMs;
      return true;
    });
  }

  public async resume(sessionId: string, nowMs: number = Date.now()): Promise<boolean> {
    const current: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!current || current.status !== 'paused') {
      return false;
    }
    const expectedStepIndex: number = current.currentStepIndex;
    const currentStep: ExecutionStepRecord | undefined = current.steps[current.currentStepIndex];
    if (!currentStep || currentStep.remainingMs <= 0) {
      return false;
    }
    return this.mutateSession(sessionId, (session) => {
      if (session.status !== 'paused' || session.currentStepIndex !== expectedStepIndex) {
        return false;
      }
      const step: ExecutionStepRecord = session.steps[expectedStepIndex];
      step.status = 'running';
      step.runStartedAt = nowMs;
      session.status = 'running';
      session.updatedAt = nowMs;
      return true;
    });
  }

  public async completeCurrentStep(sessionId: string, nowMs: number = Date.now()): Promise<boolean> {
    const current: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!current || (current.status !== 'running' && current.status !== 'paused')) {
      return false;
    }
    const expectedStepIndex: number = current.currentStepIndex;
    const expectedStatus: ExecutionStatus = current.status;
    return this.mutateSession(sessionId, (session) => {
      if (session.currentStepIndex !== expectedStepIndex || session.status !== expectedStatus ||
        (session.status !== 'running' && session.status !== 'paused')) {
        return false;
      }
      this.finishCurrentStep(session, nowMs, 'completed');
      this.startFollowingStepOrComplete(session, nowMs);
      return true;
    });
  }

  public async skipCurrentStep(sessionId: string, nowMs: number = Date.now()): Promise<boolean> {
    const current: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!current || (current.status !== 'running' && current.status !== 'paused')) {
      return false;
    }
    const expectedStepIndex: number = current.currentStepIndex;
    const expectedStatus: ExecutionStatus = current.status;
    return this.mutateSession(sessionId, (session) => {
      if (session.currentStepIndex !== expectedStepIndex || session.status !== expectedStatus ||
        (session.status !== 'running' && session.status !== 'paused')) {
        return false;
      }
      this.finishCurrentStep(session, nowMs, 'skipped');
      this.startFollowingStepOrComplete(session, nowMs);
      return true;
    });
  }

  public async startNextStep(sessionId: string, nowMs: number = Date.now()): Promise<boolean> {
    const current: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!current || current.status !== 'waiting-next') {
      return false;
    }
    const expectedStepIndex: number = current.currentStepIndex;
    return this.mutateSession(sessionId, (session) => {
      if (session.status !== 'waiting-next' || session.currentStepIndex !== expectedStepIndex) {
        return false;
      }
      this.startFollowingStepOrComplete(session, nowMs);
      return true;
    });
  }

  public async restartPreviousStep(sessionId: string, nowMs: number = Date.now()): Promise<boolean> {
    const current: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!current || current.currentStepIndex === 0 ||
      (current.status !== 'running' && current.status !== 'paused')) {
      return false;
    }
    const expectedStepIndex: number = current.currentStepIndex;
    const expectedStatus: ExecutionStatus = current.status;
    return this.mutateSession(sessionId, (session) => {
      if (session.currentStepIndex !== expectedStepIndex || session.status !== expectedStatus ||
        (session.status !== 'running' && session.status !== 'paused')) {
        return false;
      }
      if (session.status === 'running') {
        this.settleRunningStep(session, nowMs);
      }
      const active: ExecutionStepRecord = session.steps[session.currentStepIndex];
      active.status = 'pending';
      active.runStartedAt = 0;
      const previous: ExecutionStepRecord = session.steps[session.currentStepIndex - 1];
      previous.status = 'running';
      previous.elapsedActiveMs = 0;
      previous.remainingMs = previous.plannedDurationMs;
      previous.runStartedAt = nowMs;
      previous.completedAt = 0;
      session.currentStepIndex--;
      session.status = 'running';
      session.updatedAt = nowMs;
      return true;
    });
  }

  public async abandon(sessionId: string, nowMs: number = Date.now()): Promise<boolean> {
    const current: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!current || current.status === 'completed' || current.status === 'abandoned') {
      return false;
    }
    return this.mutateSession(sessionId, (session) => {
      if (!this.isActive(session)) {
        return false;
      }
      if (session.status === 'running') {
        this.settleRunningStep(session, nowMs);
      }
      session.status = 'abandoned';
      session.completedAt = nowMs;
      session.updatedAt = nowMs;
      return true;
    });
  }

  /** Settles only the currently expired step; elapsed background time never consumes later steps. */
  public async reconcile(sessionId: string, nowMs: number = Date.now()): Promise<void> {
    const current: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!current || current.status !== 'running') {
      return;
    }
    const step: ExecutionStepRecord | undefined = current.steps[current.currentStepIndex];
    if (!step || getStepRemainingMs(step, nowMs) > 0) {
      return;
    }
    await this.mutateSession(sessionId, (session) => {
      if (session.status !== 'running') {
        return false;
      }
      const activeStep: ExecutionStepRecord | undefined = session.steps[session.currentStepIndex];
      if (!activeStep || getStepRemainingMs(activeStep, nowMs) > 0) {
        return false;
      }
      this.finishCurrentStep(session, nowMs, 'completed');
      if (session.currentStepIndex >= session.steps.length - 1) {
        session.status = 'completed';
        session.completedAt = nowMs;
      } else {
        session.status = 'waiting-next';
      }
      session.updatedAt = nowMs;
      return true;
    });
  }

  public onChange(listener: () => void): void {
    if (this.listeners.indexOf(listener) === -1) {
      this.listeners.push(listener);
    }
  }

  /** 记录动作已经触发；重复记录同一动作保持幂等。 */
  public async markActionExecuted(sessionId: string, actionId: string): Promise<boolean> {
    return this.mutateSession(sessionId, (session) => {
      const executed: string[] = session.executedActionIds || [];
      if (executed.indexOf(actionId) !== -1) {
        return false;
      }
      session.executedActionIds = [...executed, actionId];
      session.updatedAt = Date.now();
      return true;
    });
  }

  public offChange(listener: () => void): void {
    const index: number = this.listeners.indexOf(listener);
    if (index !== -1) {
      this.listeners.splice(index, 1);
    }
  }

  private async mutateSession(sessionId: string, change: SessionChange): Promise<boolean> {
    let changed: boolean = false;
    await appStore.mutate((draft) => {
      const session: ExecutionSession | undefined = draft.sessions.find((candidate) => candidate.id === sessionId) as ExecutionSession | undefined;
      if (session) {
        changed = change(session);
      }
    });
    if (changed) {
      this.notifyChange();
    }
    return changed;
  }

  private isActive(session: ExecutionSession): boolean {
    return session.status === 'running' || session.status === 'paused' || session.status === 'waiting-next';
  }

  private settleRunningStep(session: ExecutionSession, nowMs: number): void {
    const step: ExecutionStepRecord = session.steps[session.currentStepIndex];
    const remaining: number = getStepRemainingMs(step, nowMs);
    const elapsed: number = step.remainingMs - remaining;
    step.remainingMs = remaining;
    step.elapsedActiveMs += Math.max(0, elapsed);
    step.runStartedAt = 0;
  }

  private finishCurrentStep(session: ExecutionSession, nowMs: number, status: ExecutionStepStatus): void {
    if (session.status === 'running') {
      this.settleRunningStep(session, nowMs);
    }
    const step: ExecutionStepRecord = session.steps[session.currentStepIndex];
    step.remainingMs = 0;
    step.runStartedAt = 0;
    step.status = status;
    step.completedAt = nowMs;
    session.updatedAt = nowMs;
  }

  private startFollowingStepOrComplete(session: ExecutionSession, nowMs: number): void {
    const nextIndex: number = session.currentStepIndex + 1;
    if (nextIndex >= session.steps.length) {
      session.status = 'completed';
      session.completedAt = nowMs;
      session.updatedAt = nowMs;
      return;
    }
    session.currentStepIndex = nextIndex;
    const next: ExecutionStepRecord = session.steps[nextIndex];
    next.status = 'running';
    next.runStartedAt = nowMs;
    session.status = 'running';
    session.updatedAt = nowMs;
  }

  private notifyChange(): void {
    for (const listener of this.listeners) {
      try {
        listener();
      } catch (_error) {
        // Keep a failing subscriber from affecting the saved session.
      }
    }
  }
}

export const executionStore: ExecutionStore = new ExecutionStore();
