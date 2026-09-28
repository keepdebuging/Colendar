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

    it('does not consume the next step during reconciliation', 0, () => {
      executionStore.sessions = [];
      const session = executionStore.startFromScheduledEvent(sampleEvent, 1000)!;
      executionStore.reconcile(session.id, 62000);
      expect(session.status).assertEqual('waiting-next');
      expect(session.currentStepIndex).assertEqual(0);
      expect(session.steps[1].status).assertEqual('pending');
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
