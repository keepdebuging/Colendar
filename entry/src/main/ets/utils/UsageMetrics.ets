import { ExecutionSession } from '../models/ExecutionSession';
import { ScheduledEvent } from '../models/ScheduledEvent';
import { TaskPackage } from '../models/TaskPackage';

/** Derived locally from existing records; nothing is uploaded or tied to an account. */
export interface LocalUsageSummary {
  packageCount: number;
  scheduledEventCount: number;
  startedEventCount: number;
  completedSessionCount: number;
  startRate: number;
  completionRate: number;
  averageStepCompletionRate: number;
  repeatedPackageCount: number;
  averageScheduleToStartMinutes: number;
}

function scheduledStartMs(event: ScheduledEvent): number {
  const dateParts: string[] = event.date.split('-');
  if (dateParts.length !== 3) {
    return 0;
  }
  const year: number = Number(dateParts[0]);
  const month: number = Number(dateParts[1]);
  const day: number = Number(dateParts[2]);
  if (!Number.isInteger(year) || !Number.isInteger(month) || !Number.isInteger(day)) {
    return 0;
  }
  return new Date(year, month - 1, day, event.startHour, event.startMinute).getTime();
}

export function buildLocalUsageSummary(
  packages: TaskPackage[],
  events: ScheduledEvent[],
  sessions: ExecutionSession[]
): LocalUsageSummary {
  const startedEventIds: string[] = [];
  const packageRunCounts: Map<string, number> = new Map<string, number>();
  let completedSessions: number = 0;
  let totalStepCompletionRate: number = 0;
  let validDelayCount: number = 0;
  let totalDelayMinutes: number = 0;

  sessions.forEach((session: ExecutionSession) => {
    if (startedEventIds.indexOf(session.scheduledEventId) === -1) {
      startedEventIds.push(session.scheduledEventId);
    }
    packageRunCounts.set(
      session.sourcePackageId,
      (packageRunCounts.get(session.sourcePackageId) || 0) + 1
    );
    if (session.status === 'completed') {
      completedSessions++;
    }
    if (session.steps.length > 0) {
      const finishedSteps: number = session.steps.filter((step) =>
        step.status === 'completed' || step.status === 'skipped'
      ).length;
      totalStepCompletionRate += finishedSteps / session.steps.length;
    }
    const event: ScheduledEvent | undefined = events.find((item: ScheduledEvent) =>
      item.id === session.scheduledEventId
    );
    if (event) {
      const scheduledMs: number = scheduledStartMs(event);
      if (scheduledMs > 0) {
        totalDelayMinutes += (session.startedAt - scheduledMs) / 60000;
        validDelayCount++;
      }
    }
  });

  let repeatedPackageCount: number = 0;
  packageRunCounts.forEach((count: number) => {
    if (count > 1) {
      repeatedPackageCount++;
    }
  });

  const summary: LocalUsageSummary = {
    packageCount: packages.length,
    scheduledEventCount: events.length,
    startedEventCount: startedEventIds.length,
    completedSessionCount: completedSessions,
    startRate: events.length > 0 ? startedEventIds.length / events.length : 0,
    completionRate: sessions.length > 0 ? completedSessions / sessions.length : 0,
    averageStepCompletionRate: sessions.length > 0 ? totalStepCompletionRate / sessions.length : 0,
    repeatedPackageCount,
    averageScheduleToStartMinutes: validDelayCount > 0 ? totalDelayMinutes / validDelayCount : 0
  };
  return summary;
}
