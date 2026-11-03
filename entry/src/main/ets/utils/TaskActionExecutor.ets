import { common, Want } from '@kit.AbilityKit';
import { TaskAction, TaskActionTrigger } from '../models/TaskAction';
import { ExecutionSession, executionStore } from '../models/ExecutionSession';

export interface ActionRunResult {
  actionId: string;
  succeeded: boolean;
}

function executionKey(action: TaskAction, stepIndex: number): string {
  return action.trigger === 'step-start' ? `${action.id}:step:${stepIndex}` : action.id;
}

async function executeAction(context: common.UIAbilityContext, action: TaskAction): Promise<void> {
  if (action.type === 'open-link') {
    await context.openLink(action.target);
    return;
  }
  if (action.type === 'open-app') {
    const appWant: Want = { bundleName: action.target };
    await context.startAbility(appWant);
    return;
  }
  const fileWant: Want = {
    uri: action.target,
    action: 'ohos.want.action.viewData'
  };
  await context.startAbility(fileWant);
}

/** Execute each enabled action at most once for its trigger key. */
export async function runTaskActions(
  context: common.UIAbilityContext, session: ExecutionSession,
  trigger: TaskActionTrigger, stepIndex: number
): Promise<ActionRunResult[]> {
  const results: ActionRunResult[] = [];
  const executed: string[] = session.executedActionIds || [];
  for (const action of session.actions || []) {
    if (!action.enabled || action.trigger !== trigger || action.target.trim().length === 0) {
      continue;
    }
    const key: string = executionKey(action, stepIndex);
    if (executed.indexOf(key) !== -1) {
      continue;
    }
    executionStore.markActionExecuted(session.id, key);
    let succeeded: boolean = true;
    try {
      await executeAction(context, action);
    } catch (_err) {
      succeeded = false;
    }
    const result: ActionRunResult = { actionId: action.id, succeeded };
    results.push(result);
  }
  return results;
}
