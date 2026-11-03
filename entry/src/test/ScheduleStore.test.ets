import { describe, it, expect } from '@ohos/hypium';
import { ScheduledEvent, scheduleStore } from '../main/ets/models/ScheduledEvent';
import { TaskPackage } from '../main/ets/models/TaskPackage';

function createEvent(id: string, customized: boolean): ScheduledEvent {
  return {
    id,
    date: '2026-10-29',
    packageId: 'package-1',
    packageName: customized ? '单次定制' : '原任务包',
    color: customized ? '#FF9500' : '#007AFF',
    startHour: 9,
    startMinute: 0,
    endHour: 9,
    endMinute: 30,
    steps: [{ name: customized ? '定制步骤' : '原步骤', duration: 30 }],
    isCustomized: customized
  };
}

export default function scheduleStoreTest() {
  describe('scheduleStoreTest', () => {
    it('keeps customized event isolated from its source package', 0, () => {
      const normal: ScheduledEvent = createEvent('event-normal', false);
      const customized: ScheduledEvent = createEvent('event-customized', true);
      scheduleStore.events = [normal, customized];
      const updatedPackage: TaskPackage = {
        id: 'package-1',
        name: '母任务包新名称',
        color: '#34C759',
        steps: [{ name: '母模板新步骤', duration: 45 }],
        _version: 1
      };

      scheduleStore.syncPackageFields(updatedPackage);

      expect(normal.packageName).assertEqual('母任务包新名称');
      expect(normal.steps[0].duration).assertEqual(45);
      expect(customized.packageName).assertEqual('单次定制');
      expect(customized.steps[0].name).assertEqual('定制步骤');
      expect(customized.steps[0].duration).assertEqual(30);
    });

    it('locates each repeated schedule by event id', 0, () => {
      const first: ScheduledEvent = createEvent('event-first', false);
      const second: ScheduledEvent = createEvent('event-second', false);
      second.startHour = 14;
      scheduleStore.events = [first, second];

      expect(scheduleStore.getEventById('event-first')?.startHour).assertEqual(9);
      expect(scheduleStore.getEventById('event-second')?.startHour).assertEqual(14);
    });
  });
}
