import { AppSnapshot, ExecutionSession, ScheduledEvent, SnapshotEnvelope, TaskPackage } from '../types/Models';
import { APP_SCHEMA_VERSION, validateSnapshot } from '../domain/Validation';
import { cloneScheduledEvent, cloneTaskPackage } from '../domain/EventCopies';
import { SnapshotRepository } from '../storage/SnapshotRepository';
import { reportError } from '../diagnostics/AppLogger';

const EXECUTION_KEY: string = 'execution_sessions_v1';

function emptySnapshot(): AppSnapshot {
  return { schemaVersion: APP_SCHEMA_VERSION, revision: 0, packages: [], events: [], sessions: [] };
}

function cloneSession(session: ExecutionSession): ExecutionSession {
  return JSON.parse(JSON.stringify(session)) as ExecutionSession;
}

function cloneSnapshot(source: AppSnapshot): AppSnapshot {
  return {
    schemaVersion: source.schemaVersion,
    revision: source.revision,
    packages: source.packages.map((pkg: TaskPackage) => cloneTaskPackage(pkg)),
    events: source.events.map((event: ScheduledEvent) => cloneScheduledEvent(event)),
    sessions: source.sessions.map((session: ExecutionSession) => cloneSession(session))
  };
}

function parseJson(raw: string, code: string): Object {
  try {
    return JSON.parse(raw) as Object;
  } catch (_error) {
    throw new Error(code);
  }
}

export class AppStore {
  private static instance: AppStore;
  private repository: SnapshotRepository = new SnapshotRepository();
  private current: AppSnapshot = emptySnapshot();
  private listeners: Array<() => void> = [];
  private mutationQueue: Promise<void> = Promise.resolve();
  private restored: boolean = false;
  public recoveryRequired: boolean = false;
  public recoveryReason: string = '';
  public originalData: string = '';

  public static getInstance(): AppStore {
    if (!AppStore.instance) {
      AppStore.instance = new AppStore();
    }
    return AppStore.instance;
  }

  public get snapshot(): AppSnapshot {
    return this.current;
  }

  /** Allows business tests to use an isolated in-memory repository per case. */
  public configureRepositoryForTesting(repository: SnapshotRepository): void {
    this.repository = repository;
    this.current = emptySnapshot();
    this.mutationQueue = Promise.resolve();
    this.restored = true;
    this.recoveryRequired = false;
    this.recoveryReason = '';
    this.originalData = '';
  }

  public restore(): void {
    if (this.restored && !this.recoveryRequired) {
      return;
    }
    this.restored = true;
    try {
      const raw: string = this.repository.readRaw();
      if (raw !== '') {
        this.restoreEnvelope(raw);
        return;
      }
      this.restoreLegacy();
    } catch (error) {
      this.recoveryRequired = true;
      this.recoveryReason = error instanceof Error ? error.message : 'STORAGE_READ_FAILED';
      this.current = emptySnapshot();
      reportError('storage.snapshot', 'STORAGE_READ_FAILED');
    }
  }

  private restoreEnvelope(raw: string): void {
    this.originalData = raw;
    try {
      const envelope: SnapshotEnvelope = JSON.parse(raw) as SnapshotEnvelope;
      if (!envelope || envelope.schemaVersion !== APP_SCHEMA_VERSION || !envelope.current) {
        throw new Error('SNAPSHOT_VERSION_UNSUPPORTED');
      }
      this.normalizeSnapshot(envelope.current);
      if (envelope.previous) {
        this.normalizeSnapshot(envelope.previous);
      }
      const currentError: string = validateSnapshot(envelope.current);
      if (currentError === '') {
        this.current = cloneSnapshot(envelope.current);
        this.recoveryRequired = false;
        return;
      }
      if (envelope.previous) {
        const previousError: string = validateSnapshot(envelope.previous);
        if (previousError === '') {
          this.current = cloneSnapshot(envelope.previous);
          this.recoveryReason = '当前数据损坏，可从上一份有效快照恢复';
          this.recoveryRequired = true;
          return;
        }
      }
      throw new Error(currentError);
    } catch (error) {
      this.recoveryRequired = true;
      this.recoveryReason = error instanceof Error ? error.message : 'SNAPSHOT_INVALID';
      this.current = emptySnapshot();
      reportError('storage.snapshot', 'CURRENT_SNAPSHOT_INVALID');
    }
  }

  private restoreLegacy(): void {
    const packagesRaw: string = this.repository.readLegacy('task_packages');
    const eventsRaw: string = this.repository.readLegacy('scheduled_events');
    const sessionsRaw: string = this.repository.readLegacy(EXECUTION_KEY);
    const hasLegacy: boolean = packagesRaw !== '' || eventsRaw !== '' || sessionsRaw !== '';
    if (!hasLegacy) {
      this.current = emptySnapshot();
      this.recoveryRequired = false;
      return;
    }
    this.originalData = JSON.stringify({ packagesRaw, eventsRaw, sessionsRaw });
    try {
      const packages: TaskPackage[] = packagesRaw === '' ? [] : this.decodePackages(packagesRaw);
      const events: ScheduledEvent[] = eventsRaw === '' ? [] : this.decodeEvents(eventsRaw);
      const sessions: ExecutionSession[] = sessionsRaw === '' ? [] : this.decodeSessions(sessionsRaw);
      const migrated: AppSnapshot = {
        schemaVersion: APP_SCHEMA_VERSION,
        revision: 0,
        packages,
        events,
        sessions
      };
      const validationError: string = validateSnapshot(migrated);
      if (validationError !== '') {
        throw new Error(validationError);
      }
      this.repository.save({ schemaVersion: APP_SCHEMA_VERSION, current: migrated, previous: null });
      if (this.repository.readRaw() === '') {
        throw new Error('MIGRATION_SAVE_FAILED');
      }
      this.current = cloneSnapshot(migrated);
      this.recoveryRequired = false;
    } catch (error) {
      this.recoveryRequired = true;
      this.recoveryReason = error instanceof Error ? error.message : 'LEGACY_DATA_INVALID';
      this.current = emptySnapshot();
      reportError('storage.migration', 'LEGACY_DATA_INVALID');
    }
  }

  private decodePackages(raw: string): TaskPackage[] {
    const value: Object = parseJson(raw, 'TASK_PACKAGES_JSON_INVALID');
    if (!Array.isArray(value)) {
      throw new Error('TASK_PACKAGES_NOT_ARRAY');
    }
    const packages: TaskPackage[] = value as TaskPackage[];
    for (const pkg of packages) {
      if (pkg.actions === undefined) {
        pkg.actions = [];
      }
    }
    return packages;
  }

  private decodeEvents(raw: string): ScheduledEvent[] {
    const value: Object = parseJson(raw, 'SCHEDULED_EVENTS_JSON_INVALID');
    if (!Array.isArray(value)) {
      throw new Error('SCHEDULED_EVENTS_NOT_ARRAY');
    }
    const events: ScheduledEvent[] = value as ScheduledEvent[];
    for (const event of events) {
      if (event.reminderEnabled === undefined) {
        event.reminderEnabled = true;
      }
      if (event.isCustomized === undefined) {
        event.isCustomized = false;
      }
      if (event.actions === undefined) {
        event.actions = [];
      }
      const start: number = event.startHour * 60 + event.startMinute;
      const duration: number = event.steps && Array.isArray(event.steps) ?
        event.steps.reduce((total: number, step) => total + step.duration, 0) : 0;
      if (event.endHour === 0 && event.endMinute === 0 && start + duration === 24 * 60) {
        event.endHour = 24;
      }
    }
    return events;
  }

  private decodeSessions(raw: string): ExecutionSession[] {
    const payload: Object = parseJson(raw, 'EXECUTION_SESSIONS_JSON_INVALID');
    const value: Record<string, Object> = payload as Record<string, Object>;
    if (value['schemaVersion'] !== 1 || !Array.isArray(value['sessions'])) {
      throw new Error('EXECUTION_SESSIONS_VERSION_INVALID');
    }
    const sessions: ExecutionSession[] = value['sessions'] as ExecutionSession[];
    for (const session of sessions) {
      if (session.actions === undefined) {
        session.actions = [];
      }
      if (session.executedActionIds === undefined) {
        session.executedActionIds = [];
      }
    }
    return sessions;
  }

  public mutate(change: (draft: AppSnapshot) => void): Promise<void> {
    const operation: Promise<void> = this.mutationQueue.then(() => {
      if (this.recoveryRequired) {
        throw new Error('RECOVERY_REQUIRED');
      }
      const previous: AppSnapshot = cloneSnapshot(this.current);
      const next: AppSnapshot = cloneSnapshot(this.current);
      change(next);
      next.revision = previous.revision + 1;
      const validationError: string = validateSnapshot(next);
      if (validationError !== '') {
        throw new Error(validationError);
      }
      try {
        this.repository.save({ schemaVersion: APP_SCHEMA_VERSION, current: next, previous });
        this.current = next;
        this.notifySafely();
      } catch (error) {
        this.recoveryRequired = true;
        this.recoveryReason = 'STORAGE_STATE_UNKNOWN';
        reportError('storage.snapshot', 'STORAGE_STATE_UNKNOWN');
        throw error;
      }
    });
    this.mutationQueue = operation.then(() => undefined, () => undefined);
    return operation;
  }

  private normalizeSnapshot(snapshot: AppSnapshot): void {
    for (const pkg of snapshot.packages) {
      if (pkg.actions === undefined) {
        pkg.actions = [];
      }
    }
    for (const event of snapshot.events) {
      if (event.actions === undefined) {
        event.actions = [];
      }
    }
    for (const session of snapshot.sessions) {
      if (session.actions === undefined) {
        session.actions = [];
      }
      if (session.executedActionIds === undefined) {
        session.executedActionIds = [];
      }
    }
  }

  public restorePrevious(): Promise<void> {
    const raw: string = this.repository.readRaw();
    try {
      const envelope: SnapshotEnvelope = JSON.parse(raw) as SnapshotEnvelope;
      if (!envelope.previous || validateSnapshot(envelope.previous) !== '') {
        return Promise.reject(new Error('PREVIOUS_SNAPSHOT_UNAVAILABLE'));
      }
      const restored: AppSnapshot = cloneSnapshot(envelope.previous);
      this.repository.saveRecoveryBackup(raw);
      this.repository.save({ schemaVersion: APP_SCHEMA_VERSION, current: restored, previous: envelope.current });
      this.current = restored;
      this.recoveryRequired = false;
      this.recoveryReason = '';
      this.notifySafely();
      return Promise.resolve();
    } catch (error) {
      return Promise.reject(error);
    }
  }

  public resetAfterConfirmation(): Promise<void> {
    const previous: AppSnapshot = cloneSnapshot(this.current);
    const next: AppSnapshot = emptySnapshot();
    next.revision = previous.revision + 1;
    try {
      if (this.originalData !== '') {
        this.repository.saveRecoveryBackup(this.originalData);
      }
      this.repository.save({ schemaVersion: APP_SCHEMA_VERSION, current: next, previous });
      this.current = next;
      this.recoveryRequired = false;
      this.recoveryReason = '';
      this.notifySafely();
      return Promise.resolve();
    } catch (error) {
      return Promise.reject(error);
    }
  }

  public exportRawData(): string {
    const snapshotRaw: string = this.repository.readRaw();
    const packagesRaw: string = this.repository.readLegacy('task_packages');
    const eventsRaw: string = this.repository.readLegacy('scheduled_events');
    const sessionsRaw: string = this.repository.readLegacy(EXECUTION_KEY);
    const recoveryBackup: string = this.repository.readRecoveryBackup();
    return JSON.stringify({ snapshotRaw, recoveryBackup, packagesRaw, eventsRaw, sessionsRaw }, null, 2);
  }

  public onChange(listener: () => void): void {
    if (this.listeners.indexOf(listener) === -1) {
      this.listeners.push(listener);
    }
  }

  public offChange(listener: () => void): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  private notifySafely(): void {
    for (const listener of this.listeners) {
      try {
        listener();
      } catch (_error) {
        // Listener failures must not turn a committed write into a failed save.
      }
    }
  }
}

export const appStore: AppStore = AppStore.getInstance();
