export type TaskActionTrigger = 'session-start' | 'step-start';
export type TaskActionType = 'open-app' | 'open-link' | 'open-file';

/** A user-authored, low-risk action. Imported actions remain disabled by default. */
export interface TaskAction {
  id: string;
  trigger: TaskActionTrigger;
  type: TaskActionType;
  target: string;
  enabled: boolean;
}

export function copyTaskActions(actions: TaskAction[] | undefined): TaskAction[] {
  if (!actions) {
    return [];
  }
  return actions.map((action: TaskAction): TaskAction => ({
    id: action.id,
    trigger: action.trigger,
    type: action.type,
    target: action.target,
    enabled: action.enabled
  }));
}
