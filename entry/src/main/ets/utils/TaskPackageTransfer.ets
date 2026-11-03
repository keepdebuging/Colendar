import { generateId, getNextColor, TaskPackage, TaskStep } from '../models/TaskPackage';
import { TaskAction } from '../models/TaskAction';

export interface SharedTaskPackageV1 {
  schemaVersion: number;
  name: string;
  steps: TaskStep[];
  actions?: TaskAction[];
}

export interface TaskPackageImportResult {
  package: TaskPackage | undefined;
  error: string;
}

const MAX_TEXT_LENGTH: number = 16384;
const MAX_NAME_LENGTH: number = 80;
const MAX_STEP_COUNT: number = 50;
const MAX_ACTION_COUNT: number = 20;

export function exportTaskPackage(pkg: TaskPackage): string {
  const payload: SharedTaskPackageV1 = {
    schemaVersion: 1,
    name: pkg.name,
    steps: pkg.steps.map((step: TaskStep): TaskStep => {
      const copied: TaskStep = { name: step.name, duration: step.duration };
      return copied;
    }),
    actions: (pkg.actions || []).map((action: TaskAction): TaskAction => {
      const copied: TaskAction = {
        id: '',
        trigger: action.trigger,
        type: action.type,
        target: action.type === 'open-file' ? '' : action.target,
        enabled: false
      };
      return copied;
    }).filter((action: TaskAction) => action.target.length > 0)
  };
  return JSON.stringify(payload);
}

export function importTaskPackage(text: string, existingCount: number): TaskPackageImportResult {
  const trimmed: string = text.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_TEXT_LENGTH) {
    return { package: undefined, error: '导入内容为空或超过 16KB' };
  }
  let payload: SharedTaskPackageV1;
  try {
    payload = JSON.parse(trimmed) as SharedTaskPackageV1;
  } catch (_err) {
    return { package: undefined, error: '导入内容不是有效 JSON' };
  }
  if (payload.schemaVersion !== 1) {
    return { package: undefined, error: '不支持的模板版本' };
  }
  if (typeof payload.name !== 'string' || payload.name.trim().length === 0 ||
    payload.name.trim().length > MAX_NAME_LENGTH) {
    return { package: undefined, error: '模板名称必须为 1～80 个字符' };
  }
  if (!Array.isArray(payload.steps) || payload.steps.length === 0 ||
    payload.steps.length > MAX_STEP_COUNT) {
    return { package: undefined, error: '步骤数量必须为 1～50 个' };
  }
  const steps: TaskStep[] = [];
  for (const sourceStep of payload.steps) {
    if (!sourceStep || typeof sourceStep.name !== 'string' ||
      sourceStep.name.trim().length === 0 || sourceStep.name.trim().length > 80 ||
      typeof sourceStep.duration !== 'number' || !Number.isInteger(sourceStep.duration) ||
      sourceStep.duration < 1 || sourceStep.duration > 1440) {
      return { package: undefined, error: '步骤名称或时长不合法' };
    }
    const step: TaskStep = { name: sourceStep.name.trim(), duration: sourceStep.duration };
    steps.push(step);
  }
  const actions: TaskAction[] = [];
  const sourceActions: TaskAction[] = Array.isArray(payload.actions) ? payload.actions : [];
  if (sourceActions.length > MAX_ACTION_COUNT) {
    return { package: undefined, error: '关联动作不能超过 20 个' };
  }
  for (const sourceAction of sourceActions) {
    if (!sourceAction || sourceAction.type === 'open-file' ||
      (sourceAction.type !== 'open-app' && sourceAction.type !== 'open-link') ||
      (sourceAction.trigger !== 'session-start' && sourceAction.trigger !== 'step-start') ||
      typeof sourceAction.target !== 'string' || sourceAction.target.length === 0 ||
      sourceAction.target.length > 2048) {
      continue;
    }
    const action: TaskAction = {
      id: generateId(),
      trigger: sourceAction.trigger,
      type: sourceAction.type,
      target: sourceAction.target,
      enabled: false
    };
    actions.push(action);
  }
  const imported: TaskPackage = {
    id: generateId(),
    name: payload.name.trim(),
    steps,
    color: getNextColor(existingCount),
    actions,
    _version: 0
  };
  return { package: imported, error: '' };
}
