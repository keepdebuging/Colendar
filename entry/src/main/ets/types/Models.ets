import { TaskAction } from '../models/TaskAction';

export interface TaskStep {
  name: string;
  duration: number;
}

export interface TaskPackage {
  id: string;
  name: string;
  steps: TaskStep[];
  color: string;
  _version: number;
  actions?: TaskAction[];
}

export interface ScheduledEvent {
  id: string;
  date: string;
  packageId: string;
  packageName: string;
  color: string;
  startHour: number;
  startMinute: number;
  /** End hour may be 24 only when endMinute is zero. */
  endHour: number;
  endMinute: number;
  steps: TaskStep[];
  reminderEnabled?: boolean;
  /** True after this scheduled copy's time or steps are edited. */
  isCustomized?: boolean;
  /** Template version copied when this event was created or synchronized. */
  sourcePackageVersion?: number;
  actions?: TaskAction[];
}

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
  actions?: TaskAction[];
  executedActionIds?: string[];
  currentStepIndex: number;
  status: ExecutionStatus;
  startedAt: number;
  completedAt: number;
  updatedAt: number;
}

export interface AppSnapshot {
  schemaVersion: number;
  revision: number;
  packages: TaskPackage[];
  events: ScheduledEvent[];
  sessions: ExecutionSession[];
}

export interface SnapshotEnvelope {
  schemaVersion: number;
  current: AppSnapshot;
  previous: AppSnapshot | null;
}
