import { describe, it, expect } from '@ohos/hypium';
import { executionStore, getStepRemainingMs } from '../main/ets/models/ExecutionSession';
import { ScheduledEvent } from '../main/ets/models/ScheduledEvent';

const sampleEvent: ScheduledEvent = {
  id: 'event-1',
  date: '2026-09-12',
  packageId: 'package-1',
  packageName: '专注学习',
  color: '#007AFF',
  startHour: 9,
  startMinute: 0,
  endHour: 9,
  endMinute: 2,
  steps: [
    { name: '阅读', duration: 1 },
    { name: '整理笔记', duration: 1 }
  ]
};

export default function executionSessionTest() {
  describe('executionSessionTest', () => {
    it('creates an isolated session snapshot', 0, () => {
      executionStore.sessions = [];
      const session = executionStore.startFromScheduledEvent(sampleEvent, 1000)!;
      expect(session.steps[0].name).assertEqual('阅读');
      sampleEvent.steps[0].name = '已修改来源';
      expect(session.steps[0].name).assertEqual('阅读');
      sampleEvent.steps[0].name = '阅读';
    });

    it('pauses and resumes using injected timestamps', 0, () => {
      executionStore.sessions = [];
      const session = executionStore.startFromScheduledEvent(sampleEvent, 1000)!;
      executionStore.pause(session.id, 11000);
      expect(session.steps[0].remainingMs).assertEqual(50000);
      executionStore.resume(session.id, 101000);
      expect(getStepRemainingMs(session.steps[0], 111000)).assertEqual(40000);
    });

    it('advances across every elapsed step during reconciliation', 0, () => {
      executionStore.sessions = [];
      const session = executionStore.startFromScheduledEvent(sampleEvent, 1000)!;
      executionStore.reconcile(session.id, 122000);
      expect(session.status).assertEqual('completed');
      expect(session.currentStepIndex).assertEqual(1);
      expect(session.steps[0].completedAt).assertEqual(61000);
      expect(session.steps[1].completedAt).assertEqual(121000);
      expect(session.completedAt).assertEqual(121000);
    });

    it('keeps a paused session unchanged during reconciliation', 0, () => {
      executionStore.sessions = [];
      const session = executionStore.startFromScheduledEvent(sampleEvent, 1000)!;
      executionStore.pause(session.id, 11000);
      executionStore.reconcile(session.id, 611000);
      expect(session.status).assertEqual('paused');
      expect(session.currentStepIndex).assertEqual(0);
      expect(session.steps[0].remainingMs).assertEqual(50000);
    });

    it('is idempotent after a session has caught up', 0, () => {
      executionStore.sessions = [];
      const session = executionStore.startFromScheduledEvent(sampleEvent, 1000)!;
      executionStore.reconcile(session.id, 122000);
      const completedAt: number = session.completedAt;
      executionStore.reconcile(session.id, 999000);
      expect(session.status).assertEqual('completed');
      expect(session.completedAt).assertEqual(completedAt);
      expect(session.steps[1].completedAt).assertEqual(121000);
    });

    it('automatically resumes a legacy waiting-next session', 0, () => {
      executionStore.sessions = [];
      const session = executionStore.startFromScheduledEvent(sampleEvent, 1000)!;
      session.steps[0].status = 'completed';
      session.steps[0].remainingMs = 0;
      session.steps[0].runStartedAt = 0;
      session.steps[0].completedAt = 61000;
      session.status = 'waiting-next';
      session.updatedAt = 61000;

      executionStore.reconcile(session.id, 90000);
      expect(session.status).assertEqual('running');
      expect(session.currentStepIndex).assertEqual(1);
      expect(session.steps[1].runStartedAt).assertEqual(61000);
      expect(getStepRemainingMs(session.steps[1], 90000)).assertEqual(31000);
    });

    it('creates a new session after the previous run completed', 0, () => {
      executionStore.sessions = [];
      const first = executionStore.startFromScheduledEvent(sampleEvent, 1000)!;
      executionStore.completeCurrentStep(first.id, 61000);
      executionStore.completeCurrentStep(first.id, 121000);
      expect(first.status).assertEqual('completed');

      const second = executionStore.startFromScheduledEvent(sampleEvent, 200000)!;
      expect(second.id === first.id).assertEqual(false);
      expect(second.status).assertEqual('running');
      expect(second.currentStepIndex).assertEqual(0);
      expect(second.steps[0].remainingMs).assertEqual(60000);
      expect(executionStore.sessions.length).assertEqual(2);
    });

    it('holds a new session at full duration during preparation', 0, () => {
      executionStore.sessions = [];
      const session = executionStore.startFromScheduledEvent(sampleEvent, 1000)!;
      expect(executionStore.prepareNewSession(session.id, 1500)).assertEqual(true);
      expect(session.status).assertEqual('paused');
      expect(session.steps[0].remainingMs).assertEqual(60000);

      executionStore.resume(session.id, 5000);
      expect(getStepRemainingMs(session.steps[0], 6000)).assertEqual(59000);
    });
  });
}
