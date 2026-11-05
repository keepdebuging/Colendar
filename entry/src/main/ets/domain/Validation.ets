import {
  AppSnapshot,
  ExecutionSession,
  ScheduledEvent,
  TaskPackage,
  TaskStep
} from '../types/Models';
import { TaskAction } from '../models/TaskAction';

export const APP_SCHEMA_VERSION: number = 1;
export const MAX_DAY_MINUTES: number = 24 * 60;

function validateActions(actions: TaskAction[] | undefined): string {
  if (actions === undefined) {
    return '';
  }
  if (!Array.isArray(actions) || actions.length > 20) {
    return '关联动作数量无效';
  }
  const ids: Set<string> = new Set<string>();
  for (const action of actions) {
    if (!action || typeof action.id !== 'string' || action.id.trim() === '' || ids.has(action.id) ||
      (action.trigger !== 'session-start' && action.trigger !== 'step-start') ||
      (action.type !== 'open-app' && action.type !== 'open-link' && action.type !== 'open-file') ||
      typeof action.target !== 'string' || action.target.trim() === '' || action.target.length > 2048 ||
      typeof action.enabled !== 'boolean') {
      return '关联动作数据无效';
    }
    ids.add(action.id);
  }
  return '';
}

export function validateSteps(steps: TaskStep[]): string {
  if (!Array.isArray(steps) || steps.length === 0) {
    return '请至少添加一个步骤';
  }
  let total: number = 0;
  for (const step of steps) {
    if (!step || typeof step !== 'object') {
      return '步骤数据格式错误';
    }
    if (typeof step.name !== 'string' || step.name.trim().length === 0) {
      return '步骤名称不能为空';
    }
    if (!Number.isSafeInteger(step.duration) || step.duration <= 0) {
      return '步骤时长必须是正整数分钟';
    }
    total += step.duration;
    if (total > MAX_DAY_MINUTES) {
      return '任务包总时长不能超过 24 小时';
    }
  }
  return '';
}

export function totalStepMinutes(steps: TaskStep[]): number {
  if (!Array.isArray(steps)) {
    return 0;
  }
  return steps.reduce((total: number, step: TaskStep) => total + step.duration, 0);
}

export function validateDate(date: string): string {
  if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return '日期格式无效';
  }
  const parts: string[] = date.split('-');
  const year: number = Number(parts[0]);
  const month: number = Number(parts[1]);
  const day: number = Number(parts[2]);
  const value: Date = new Date(year, month - 1, day);
  if (value.getFullYear() !== year || value.getMonth() !== month - 1 || value.getDate() !== day) {
    return '日期不存在';
  }
  return '';
}

export function validateInterval(startMinutes: number, duration: number): string {
  if (!Number.isSafeInteger(startMinutes) || startMinutes < 0 || startMinutes >= MAX_DAY_MINUTES) {
    return '开始时间无效';
  }
  if (!Number.isSafeInteger(duration) || duration <= 0) {
    return '任务时长无效';
  }
  if (startMinutes + duration > MAX_DAY_MINUTES) {
    return '任务不能跨过当天，请提前开始或缩短时长';
  }
  return '';
}

export function validatePackage(pkg: TaskPackage): string {
  if (!pkg || typeof pkg !== 'object') {
    return '任务包数据格式错误';
  }
  if (typeof pkg.id !== 'string' || pkg.id.trim() === '') {
    return '任务包 ID 无效';
  }
  if (typeof pkg.name !== 'string' || pkg.name.trim() === '') {
    return '任务包名称不能为空';
  }
  if (typeof pkg.color !== 'string' || pkg.color.trim() === '') {
    return '任务包颜色无效';
  }
  if (!Number.isSafeInteger(pkg._version) || pkg._version < 0) {
    return '任务包版本无效';
  }
  const stepsError: string = validateSteps(pkg.steps);
  return stepsError !== '' ? stepsError : validateActions(pkg.actions);
}

export function validateEvent(event: ScheduledEvent): string {
  if (!event || typeof event !== 'object') {
    return '日程数据格式错误';
  }
  if (typeof event.id !== 'string' || event.id.trim() === '' ||
    typeof event.packageId !== 'string' || event.packageId.trim() === '') {
    return '日程 ID 无效';
  }
  if (typeof event.packageName !== 'string' || event.packageName.trim() === '' ||
    typeof event.color !== 'string' || event.color.trim() === '') {
    return '日程内容无效';
  }
  const dateError: string = validateDate(event.date);
  if (dateError !== '') {
    return dateError;
  }
  if (!Number.isSafeInteger(event.startHour) || event.startHour < 0 || event.startHour > 23 ||
    !Number.isSafeInteger(event.startMinute) || event.startMinute < 0 || event.startMinute > 59 ||
    !Number.isSafeInteger(event.endHour) || event.endHour < 0 || event.endHour > 24 ||
    !Number.isSafeInteger(event.endMinute) || event.endMinute < 0 || event.endMinute > 59 ||
    (event.endHour === 24 && event.endMinute !== 0)) {
    return '日程时间无效';
  }
  const stepsError: string = validateSteps(event.steps);
  if (stepsError !== '') {
    return stepsError;
  }
  const start: number = event.startHour * 60 + event.startMinute;
  const duration: number = totalStepMinutes(event.steps);
  const intervalError: string = validateInterval(start, duration);
  if (intervalError !== '') {
    return intervalError;
  }
  const end: number = event.endHour * 60 + event.endMinute;
  if (end !== start + duration) {
    return '日程结束时间与步骤总时长不一致';
  }
  if (event.reminderEnabled !== undefined && typeof event.reminderEnabled !== 'boolean') {
    return '提醒设置无效';
  }
  if (event.isCustomized !== undefined && typeof event.isCustomized !== 'boolean') {
    return '日程定制标记无效';
  }
  if (event.sourcePackageVersion !== undefined &&
    (!Number.isSafeInteger(event.sourcePackageVersion) || event.sourcePackageVersion < 0)) {
    return '日程模板版本无效';
  }
  return validateActions(event.actions);
}

function isActive(session: ExecutionSession): boolean {
  return session.status === 'running' || session.status === 'paused' || session.status === 'waiting-next';
}

export function validateSession(session: ExecutionSession): string {
  if (!session || typeof session !== 'object' || typeof session.id !== 'string' || session.id.trim() === '') {
    return '执行记录 ID 无效';
  }
  if (typeof session.scheduledEventId !== 'string' || typeof session.sourcePackageId !== 'string' ||
    typeof session.packageName !== 'string' || typeof session.color !== 'string') {
    return '执行记录内容无效';
  }
  const validStatuses: string[] = ['running', 'paused', 'waiting-next', 'completed', 'abandoned'];
  if (validStatuses.indexOf(session.status) < 0 || !Array.isArray(session.steps) || session.steps.length === 0) {
    return '执行记录状态无效';
  }
  if (!Number.isSafeInteger(session.currentStepIndex) || session.currentStepIndex < 0 ||
    session.currentStepIndex >= session.steps.length) {
    return '执行记录步骤索引无效';
  }
  const timestamps: number[] = [session.startedAt, session.completedAt, session.updatedAt];
  if (timestamps.some((value: number) => !Number.isFinite(value) || value < 0)) {
    return '执行记录时间无效';
  }
  const validStepStatuses: string[] = ['pending', 'running', 'completed', 'skipped'];
  for (const step of session.steps) {
    if (!step || !Number.isSafeInteger(step.index) || typeof step.name !== 'string' ||
      validStepStatuses.indexOf(step.status) < 0 ||
      !Number.isFinite(step.plannedDurationMs) || step.plannedDurationMs <= 0 ||
      !Number.isFinite(step.elapsedActiveMs) || step.elapsedActiveMs < 0 ||
      !Number.isFinite(step.runStartedAt) || step.runStartedAt < 0 ||
      !Number.isFinite(step.remainingMs) || step.remainingMs < 0 ||
      !Number.isFinite(step.completedAt) || step.completedAt < 0) {
      return '执行记录步骤数据无效';
    }
  }
  const actionError: string = validateActions(session.actions);
  if (actionError !== '') {
    return actionError;
  }
  if (session.executedActionIds !== undefined) {
    if (!Array.isArray(session.executedActionIds) ||
      session.executedActionIds.some((id: string) => typeof id !== 'string' || id.trim() === '')) {
      return '执行记录动作状态无效';
    }
  }
  return '';
}

export function validateSnapshot(snapshot: AppSnapshot): string {
  if (!snapshot || snapshot.schemaVersion !== APP_SCHEMA_VERSION ||
    !Number.isSafeInteger(snapshot.revision) || snapshot.revision < 0 ||
    !Array.isArray(snapshot.packages) || !Array.isArray(snapshot.events) || !Array.isArray(snapshot.sessions)) {
    return '快照结构不兼容';
  }
  const packageIds: Set<string> = new Set<string>();
  for (const pkg of snapshot.packages) {
    const error: string = validatePackage(pkg);
    if (error !== '' || packageIds.has(pkg.id)) {
      return error || '任务包 ID 重复';
    }
    packageIds.add(pkg.id);
  }
  const eventIds: Set<string> = new Set<string>();
  const byDate: Map<string, ScheduledEvent[]> = new Map<string, ScheduledEvent[]>();
  for (const event of snapshot.events) {
    const error: string = validateEvent(event);
    if (error !== '' || eventIds.has(event.id)) {
      return error || '日程 ID 重复';
    }
    eventIds.add(event.id);
    if (!packageIds.has(event.packageId)) {
      return '日程关联的任务包不存在';
    }
    const sameDate: ScheduledEvent[] = byDate.get(event.date) || [];
    sameDate.push(event);
    byDate.set(event.date, sameDate);
  }
  for (const events of byDate.values()) {
    const boundaries: Array<{ minute: number; delta: number }> = [];
    for (const event of events) {
      boundaries.push({ minute: event.startHour * 60 + event.startMinute, delta: 1 });
      boundaries.push({ minute: event.endHour * 60 + event.endMinute, delta: -1 });
    }
    boundaries.sort((left, right) => left.minute === right.minute ? left.delta - right.delta : left.minute - right.minute);
    let concurrent: number = 0;
    for (const boundary of boundaries) {
      concurrent += boundary.delta;
      if (concurrent > 2) {
        return '同一时段最多安排两个重叠日程';
      }
    }
  }
  const sessionIds: Set<string> = new Set<string>();
  let activeCount: number = 0;
  for (const session of snapshot.sessions) {
    const error: string = validateSession(session);
    if (error !== '' || sessionIds.has(session.id)) {
      return error || '执行记录 ID 重复';
    }
    if (isActive(session)) {
      activeCount++;
    }
    sessionIds.add(session.id);
  }
  return activeCount > 1 ? '存在多个未结束的执行任务' : '';
}
