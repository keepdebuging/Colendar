import { describe, it, expect } from '@ohos/hypium';
import { ExecutionSession } from '../main/ets/models/ExecutionSession';
import { ScheduledEvent } from '../main/ets/models/ScheduledEvent';
import { TaskPackage } from '../main/ets/models/TaskPackage';
import { buildLocalUsageSummary } from '../main/ets/utils/UsageMetrics';

export default function usageMetricsTest() {
  describe('usageMetricsTest', () => {
    it('derives anonymous funnel metrics from local records', 0, () => {
      const pkg: TaskPackage = {
        id: 'p1', name: '学习', color: '#007AFF', steps: [{ name: '读书', duration: 1 }], _version: 0
      };
      const event: ScheduledEvent = {
        id: 'e1', date: '2026-10-29', packageId: 'p1', packageName: '学习', color: '#007AFF',
        startHour: 9, startMinute: 0, endHour: 9, endMinute: 1, steps: [{ name: '读书', duration: 1 }]
      };
      const session: ExecutionSession = {
        id: 's1', scheduledEventId: 'e1', sourcePackageId: 'p1', packageName: '学习', color: '#007AFF',
        steps: [{
          index: 0, name: '读书', plannedDurationMs: 60000, status: 'completed', elapsedActiveMs: 60000,
          runStartedAt: 0, remainingMs: 0, completedAt: new Date(2026, 9, 29, 9, 1).getTime()
        }],
        actions: [], executedActionIds: [], currentStepIndex: 0, status: 'completed',
        startedAt: new Date(2026, 9, 29, 9, 0).getTime(),
        completedAt: new Date(2026, 9, 29, 9, 1).getTime(),
        updatedAt: new Date(2026, 9, 29, 9, 1).getTime()
      };
      const summary = buildLocalUsageSummary([pkg], [event], [session, session]);
      expect(summary.startRate).assertEqual(1);
      expect(summary.completionRate).assertEqual(1);
      expect(summary.averageStepCompletionRate).assertEqual(1);
      expect(summary.repeatedPackageCount).assertEqual(1);
    });
  });
}
