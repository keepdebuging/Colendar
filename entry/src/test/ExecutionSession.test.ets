import { describe, it, expect } from '@ohos/hypium';
import { executionStore, getStepRemainingMs } from '../main/ets/models/ExecutionSession';
import { ScheduledEvent } from '../main/ets/models/ScheduledEvent';
import { SnapshotEnvelope } from '../main/ets/types/Models';
import { SnapshotRepository } from '../main/ets/storage/SnapshotRepository';
import { appStore } from '../main/ets/state/AppStore';

class MemorySnapshotRepository extends SnapshotRepository {
  private raw: string = '';
  private legacy: Map<string, string> = new Map<string, string>();

  public readRaw(): string {
    return this.raw;
  }

  public readLegacy(key: string): string {
    return this.legacy.get(key) || '';
  }

  public save(envelope: SnapshotEnvelope): void {
    this.raw = JSON.stringify(envelope);
  }
}

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

function resetStore(): void {
  appStore.configureRepositoryForTesting(new MemorySnapshotRepository());
}

export default function executionSessionTest() {
  describe('executionSessionTest', () => {
    it('creates an isolated session snapshot', 0, async () => {
      resetStore();
      const session = await executionStore.startFromScheduledEvent(sampleEvent, 1000);
      expect(session !== undefined).assertEqual(true);
      expect(session!.steps[0].name).assertEqual('阅读');
      sampleEvent.steps[0].name = '已修改来源';
      expect(executionStore.getSessionById(session!.id)!.steps[0].name).assertEqual('阅读');
      sampleEvent.steps[0].name = '阅读';
    });

    it('pauses and resumes using injected timestamps', 0, async () => {
      resetStore();
      const created = await executionStore.startFromScheduledEvent(sampleEvent, 1000);
      const sessionId: string = created!.id;
      await executionStore.pause(sessionId, 11000);
      expect(executionStore.getSessionById(sessionId)!.steps[0].remainingMs).assertEqual(50000);
      await executionStore.resume(sessionId, 101000);
      expect(getStepRemainingMs(executionStore.getSessionById(sessionId)!.steps[0], 111000)).assertEqual(40000);
    });

    it('does not consume the next step during reconciliation', 0, async () => {
      resetStore();
      const created = await executionStore.startFromScheduledEvent(sampleEvent, 1000);
      await executionStore.reconcile(created!.id, 62000);
      const session = executionStore.getSessionById(created!.id)!;
      expect(session.status).assertEqual('waiting-next');
      expect(session.currentStepIndex).assertEqual(0);
      expect(session.steps[0].remainingMs).assertEqual(0);
    });

    it('requires an explicit start for each step and reconciles idempotently', 0, async () => {
      resetStore();
      const created = await executionStore.startFromScheduledEvent(sampleEvent, 1000);
      await executionStore.reconcile(created!.id, 62000);
      await executionStore.reconcile(created!.id, 90000);
      let session = executionStore.getSessionById(created!.id)!;
      expect(session.status).assertEqual('waiting-next');
      expect(session.currentStepIndex).assertEqual(0);
      expect(session.steps[1].status).assertEqual('pending');

      await executionStore.startNextStep(created!.id, 90000);
      await executionStore.reconcile(created!.id, 150000);
      session = executionStore.getSessionById(created!.id)!;
      const completedAt: number = session.completedAt;
      await executionStore.reconcile(created!.id, 999000);
      expect(session.status).assertEqual('completed');
      expect(session.currentStepIndex).assertEqual(1);
      expect(session.steps[0].completedAt).assertEqual(62000);
      expect(session.steps[1].completedAt).assertEqual(150000);
      expect(session.completedAt).assertEqual(completedAt);
    });

    it('creates a new session after the previous run completed', 0, async () => {
      resetStore();
      const first = await executionStore.startFromScheduledEvent(sampleEvent, 1000);
      await executionStore.completeCurrentStep(first!.id, 61000);
      await executionStore.completeCurrentStep(first!.id, 121000);
      expect(executionStore.getSessionById(first!.id)!.status).assertEqual('completed');

      const second = await executionStore.startFromScheduledEvent(sampleEvent, 200000);
      expect(second!.id === first!.id).assertEqual(false);
      expect(second!.status).assertEqual('running');
      expect(second!.currentStepIndex).assertEqual(0);
      expect(second!.steps[0].remainingMs).assertEqual(60000);
      expect(executionStore.sessions.length).assertEqual(2);
    });

    it('holds a new session at full duration during preparation', 0, async () => {
      resetStore();
      const created = await executionStore.startFromScheduledEvent(sampleEvent, 1000);
      expect(await executionStore.prepareNewSession(created!.id, 1500)).assertEqual(true);
      expect(executionStore.getSessionById(created!.id)!.status).assertEqual('paused');
      expect(executionStore.getSessionById(created!.id)!.steps[0].remainingMs).assertEqual(60000);

      await executionStore.resume(created!.id, 5000);
      expect(getStepRemainingMs(executionStore.getSessionById(created!.id)!.steps[0], 6000)).assertEqual(59000);
    });
  });
}
