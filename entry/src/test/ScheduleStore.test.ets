import { describe, it, expect } from '@ohos/hypium';
import { ScheduledEvent, scheduleStore } from '../main/ets/models/ScheduledEvent';
import { TaskPackage, taskStore } from '../main/ets/models/TaskPackage';
import { SnapshotEnvelope } from '../main/ets/types/Models';
import { SnapshotRepository } from '../main/ets/storage/SnapshotRepository';
import { appStore } from '../main/ets/state/AppStore';

class MemorySnapshotRepository extends SnapshotRepository {
  private raw: string = '';

  public readRaw(): string {
    return this.raw;
  }

  public readLegacy(_key: string): string {
    return '';
  }

  public save(envelope: SnapshotEnvelope): void {
    this.raw = JSON.stringify(envelope);
  }
}

function resetStore(): void {
  appStore.configureRepositoryForTesting(new MemorySnapshotRepository());
}

function createPackage(): TaskPackage {
  return {
    id: 'package-1',
    name: '原任务包',
    color: '#007AFF',
    steps: [{ name: '原步骤', duration: 30 }],
    _version: 0
  };
}

function createEvent(id: string, customized: boolean, startHour: number = 9): ScheduledEvent {
  return {
    id,
    date: '2026-10-29',
    packageId: 'package-1',
    packageName: customized ? '单次定制' : '原任务包',
    color: customized ? '#FF9500' : '#007AFF',
    startHour,
    startMinute: 0,
    endHour: startHour,
    endMinute: 30,
    steps: [{ name: customized ? '定制步骤' : '原步骤', duration: 30 }],
    isCustomized: customized,
    sourcePackageVersion: 0
  };
}

export default function scheduleStoreTest() {
  describe('scheduleStoreTest', () => {
    it('keeps scheduled snapshots unchanged when the source package changes', 0, async () => {
      resetStore();
      const originalPackage: TaskPackage = createPackage();
      await taskStore.addPackage(originalPackage);
      await scheduleStore.addEvent(createEvent('event-normal', false));
      await scheduleStore.addEvent(createEvent('event-customized', true));

      const updatedPackage: TaskPackage = {
        id: originalPackage.id,
        name: '母任务包新名称',
        color: '#34C759',
        steps: [{ name: '母模板新步骤', duration: 45 }],
        _version: 0
      };
      await taskStore.updatePackage(originalPackage.id, updatedPackage);

      const normal: ScheduledEvent | undefined = scheduleStore.getEventById('event-normal');
      const customized: ScheduledEvent | undefined = scheduleStore.getEventById('event-customized');
      expect(normal?.packageName).assertEqual('原任务包');
      expect(normal?.steps[0].duration).assertEqual(30);
      expect(customized?.packageName).assertEqual('单次定制');
      expect(customized?.steps[0].name).assertEqual('定制步骤');
      expect(customized?.steps[0].duration).assertEqual(30);
    });

    it('locates repeated schedules by event id', 0, async () => {
      resetStore();
      await scheduleStore.addEvent(createEvent('event-first', false, 9));
      await scheduleStore.addEvent(createEvent('event-second', false, 14));

      expect(scheduleStore.getEventById('event-first')?.startHour).assertEqual(9);
      expect(scheduleStore.getEventById('event-second')?.startHour).assertEqual(14);
    });
  });
}
