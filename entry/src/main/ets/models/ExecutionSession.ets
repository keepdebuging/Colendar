import { TaskStep } from './TaskPackage';
import { ScheduledEvent } from './ScheduledEvent';
import { generateId } from './TaskPackage';
import { persistence } from './Persistence';
import { TaskAction, copyTaskActions } from './TaskAction';

export type ExecutionStatus = 'running' | 'paused' | 'waiting-next' | 'completed' | 'abandoned';
export type ExecutionStepStatus = 'pending' | 'running' | 'completed' | 'skipped';

export interface ExecutionStepRecord {
  index: number;
  name: string;
  plannedDurationMs: number;
  status: ExecutionStepStatus;
  elapsedActiveMs: number;
  runStartedAt: number;
  remainingMs: number;
  completedAt: number;
}

export interface ExecutionSession {
  id: string;
  scheduledEventId: string;
  sourcePackageId: string;
  packageName: string;
  color: string;
  steps: ExecutionStepRecord[];
  actions: TaskAction[];
  executedActionIds: string[];
  currentStepIndex: number;
  status: ExecutionStatus;
  startedAt: number;
  completedAt: number;
  updatedAt: number;
}

interface ExecutionStorePayload {
  schemaVersion: number;
  sessions: ExecutionSession[];
}

const EXECUTION_SESSIONS_KEY: string = 'execution_sessions_v1';
const EXECUTION_SCHEMA_VERSION: number = 1;

export function getStepRemainingMs(step: ExecutionStepRecord, nowMs: number): number {
  if (step.status !== 'running' || step.runStartedAt === 0) {
    return Math.max(0, step.remainingMs);
  }
  return Math.max(0, step.remainingMs - (nowMs - step.runStartedAt));
}

class ExecutionStore {
  public sessions: ExecutionSession[] = [];
  private listeners: Array<() => void> = [];

  public restore(): void {
    const raw: string = persistence.readString(EXECUTION_SESSIONS_KEY);
    if (raw === '') {
      return;
    }
    try {
      const payload: ExecutionStorePayload = JSON.parse(raw) as ExecutionStorePayload;
      if (payload.schemaVersion === EXECUTION_SCHEMA_VERSION && Array.isArray(payload.sessions)) {
        this.sessions = payload.sessions;
      }
    } catch (_err) {
      persistence.writeString(`${EXECUTION_SESSIONS_KEY}_invalid`, raw);
      this.sessions = [];
      return;
    }
    this.reconcileActive();
  }

  public getSessionById(sessionId: string): ExecutionSession | undefined {
    return this.sessions.find((session: ExecutionSession) => session.id === sessionId);
  }

  public getActiveSession(): ExecutionSession | undefined {
    return this.sessions.find((session: ExecutionSession) =>
      session.status === 'running' || session.status === 'paused' || session.status === 'waiting-next'
    );
  }

  public getLatestSessionByEventId(eventId: string): ExecutionSession | undefined {
    const matches: ExecutionSession[] = this.sessions.filter(
      (session: ExecutionSession) => session.scheduledEventId === eventId
    );
    return matches.length > 0 ? matches[matches.length - 1] : undefined;
  }

  /** 将当前唯一活跃会话按真实时间追赶到 nowMs。 */
  public reconcileActive(nowMs: number = Date.now()): void {
    const activeSession: ExecutionSession | undefined = this.getActiveSession();
    if (activeSession) {
      this.reconcile(activeSession.id, nowMs);
    }
  }

  public startFromScheduledEvent(event: ScheduledEvent, nowMs: number = Date.now()): ExecutionSession | undefined {
    const latest: ExecutionSession | undefined = this.getLatestSessionByEventId(event.id);
    if (latest && (latest.status === 'running' || latest.status === 'paused' ||
      latest.status === 'waiting-next')) {
      return latest;
    }
    if (this.getActiveSession()) {
      return undefined;
    }
    const steps: ExecutionStepRecord[] = event.steps.map((step: TaskStep, index: number) => {
      const duration: number = Math.max(1, step.duration) * 60000;
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
    if (steps.length === 0) {
      return undefined;
    }
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
    this.sessions.push(session);
    this.commit();
    return session;
  }

  /** Holds a brand-new session at its full first-step duration during the 3-2-1 preparation. */
  public prepareNewSession(sessionId: string, nowMs: number = Date.now()): boolean {
    const session: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!session || session.status !== 'running' || session.currentStepIndex !== 0) {
      return false;
    }
    const firstStep: ExecutionStepRecord | undefined = session.steps[0];
    if (!firstStep) {
      return false;
    }
    firstStep.status = 'running';
    firstStep.elapsedActiveMs = 0;
    firstStep.remainingMs = firstStep.plannedDurationMs;
    firstStep.runStartedAt = 0;
    firstStep.completedAt = 0;
    session.status = 'paused';
    session.updatedAt = nowMs;
    this.commit();
    return true;
  }

  public pause(sessionId: string, nowMs: number = Date.now()): boolean {
    const session: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!session || session.status !== 'running') {
      return false;
    }
    this.settleRunningStep(session, nowMs);
    session.status = 'paused';
    session.updatedAt = nowMs;
    this.commit();
    return true;
  }

  public resume(sessionId: string, nowMs: number = Date.now()): boolean {
    const session: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!session || session.status !== 'paused') {
      return false;
    }
    const step: ExecutionStepRecord | undefined = session.steps[session.currentStepIndex];
    if (!step || step.remainingMs <= 0) {
      return false;
    }
    step.status = 'running';
    step.runStartedAt = nowMs;
    session.status = 'running';
    session.updatedAt = nowMs;
    this.commit();
    return true;
  }

  public completeCurrentStep(sessionId: string, nowMs: number = Date.now()): boolean {
    const session: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!session || (session.status !== 'running' && session.status !== 'paused')) {
      return false;
    }
    this.finishCurrentStep(session, nowMs, 'completed');
    this.startFollowingStepOrComplete(session, nowMs);
    this.commit();
    return true;
  }

  public skipCurrentStep(sessionId: string, nowMs: number = Date.now()): boolean {
    const session: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!session || (session.status !== 'running' && session.status !== 'paused')) {
      return false;
    }
    this.finishCurrentStep(session, nowMs, 'skipped');
    this.startFollowingStepOrComplete(session, nowMs);
    this.commit();
    return true;
  }

  public startNextStep(sessionId: string, nowMs: number = Date.now()): boolean {
    const session: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!session || session.status !== 'waiting-next') {
      return false;
    }
    this.startFollowingStepOrComplete(session, nowMs);
    this.commit();
    return true;
  }

  /** Reopens the immediately preceding chapter and makes it the active timer. */
  public restartPreviousStep(sessionId: string, nowMs: number = Date.now()): boolean {
    const session: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!session || session.currentStepIndex === 0 ||
      (session.status !== 'running' && session.status !== 'paused')) {
      return false;
    }
    if (session.status === 'running') {
      this.settleRunningStep(session, nowMs);
    }
    const current: ExecutionStepRecord = session.steps[session.currentStepIndex];
    current.status = 'pending';
    current.runStartedAt = 0;
    const previous: ExecutionStepRecord = session.steps[session.currentStepIndex - 1];
    previous.status = 'running';
    previous.elapsedActiveMs = 0;
    previous.remainingMs = previous.plannedDurationMs;
    previous.runStartedAt = nowMs;
    previous.completedAt = 0;
    session.currentStepIndex--;
    session.status = 'running';
    session.updatedAt = nowMs;
    this.commit();
    return true;
  }

  public abandon(sessionId: string, nowMs: number = Date.now()): boolean {
    const session: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!session || session.status === 'completed' || session.status === 'abandoned') {
      return false;
    }
    if (session.status === 'running') {
      this.settleRunningStep(session, nowMs);
    }
    session.status = 'abandoned';
    session.completedAt = nowMs;
    session.updatedAt = nowMs;
    this.commit();
    return true;
  }

  /**
   * 按真实时间把运行会话追赶到 nowMs。
   * 后台期间跨过多个步骤时逐项结算，并以每一步的理论结束时间启动下一步。
   */
  public reconcile(sessionId: string, nowMs: number = Date.now()): void {
    const session: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!session || session.status === 'paused' || session.status === 'completed' ||
      session.status === 'abandoned') {
      return;
    }

    let changed: boolean = false;

    // 兼容旧版本留下的 waiting-next：从当时记录的更新时间自动进入下一步。
    if (session.status === 'waiting-next') {
      const nextStartedAt: number = session.updatedAt > 0 ? session.updatedAt : nowMs;
      this.startFollowingStepOrComplete(session, nextStartedAt);
      changed = true;
    }

    while (session.status === 'running') {
      const step: ExecutionStepRecord | undefined = session.steps[session.currentStepIndex];
      if (!step || getStepRemainingMs(step, nowMs) > 0) {
        break;
      }
      const completedAt: number = step.runStartedAt > 0 ?
        step.runStartedAt + Math.max(0, step.remainingMs) : nowMs;
      this.finishCurrentStep(session, completedAt, 'completed');
      this.startFollowingStepOrComplete(session, completedAt);
      changed = true;
    }

    if (changed) {
      session.updatedAt = nowMs;
      this.commit();
    }
  }

  public onChange(listener: () => void): void {
    if (this.listeners.indexOf(listener) === -1) {
      this.listeners.push(listener);
    }
  }

  /** 记录动作已经触发；重复记录同一动作保持幂等。 */
  public markActionExecuted(sessionId: string, actionId: string): boolean {
    const session: ExecutionSession | undefined = this.getSessionById(sessionId);
    if (!session) {
      return false;
    }
    if (!session.executedActionIds) {
      session.executedActionIds = [];
    }
    if (session.executedActionIds.indexOf(actionId) !== -1) {
      return false;
    }
    session.executedActionIds.push(actionId);
    session.updatedAt = Date.now();
    this.commit();
    return true;
  }

  public offChange(listener: () => void): void {
    const index: number = this.listeners.indexOf(listener);
    if (index !== -1) {
      this.listeners.splice(index, 1);
    }
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
      return;
    }
    session.currentStepIndex = nextIndex;
    const next: ExecutionStepRecord = session.steps[nextIndex];
    next.status = 'running';
    next.runStartedAt = nowMs;
    session.status = 'running';
  }

  private commit(): void {
    const payload: ExecutionStorePayload = {
      schemaVersion: EXECUTION_SCHEMA_VERSION,
      sessions: this.sessions
    };
    persistence.writeString(EXECUTION_SESSIONS_KEY, JSON.stringify(payload));
    this.listeners.forEach((listener: () => void) => listener());
  }
}

export const executionStore: ExecutionStore = new ExecutionStore();
