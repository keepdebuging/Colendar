import { ScheduledEvent as ScheduledEventModel, TaskStep as TaskStepModel } from '../types/Models';
import { cloneScheduledEvent } from '../domain/EventCopies';
import { totalStepMinutes, validateEvent, validateInterval } from '../domain/Validation';
import { appStore } from '../state/AppStore';

export interface ScheduledEvent extends ScheduledEventModel {}
export interface TaskStep extends TaskStepModel {}

export function getTotalDuration(steps: TaskStep[]): number {
  return totalStepMinutes(steps);
}

class ScheduleStore {
  private listeners: Array<() => void> = [];

  public get events(): ScheduledEvent[] {
    return appStore.snapshot.events as ScheduledEvent[];
  }

  public restore(): void {
    appStore.restore();
  }

  public async addEvent(event: ScheduledEvent): Promise<void> {
    const copy: ScheduledEvent = cloneScheduledEvent(event);
    if (copy.reminderEnabled === undefined) {
      copy.reminderEnabled = true;
    }
    if (copy.isCustomized === undefined) {
      copy.isCustomized = false;
    }
    const validationError: string = validateEvent(copy);
    if (validationError !== '') {
      throw new Error(validationError);
    }
    await appStore.mutate((draft) => {
      if (draft.events.some((existing) => existing.id === copy.id)) {
        throw new Error('日程 ID 重复');
      }
      const start: number = copy.startHour * 60 + copy.startMinute;
      const duration: number = getTotalDuration(copy.steps);
      if (!this.canPlaceInterval(copy.date, start, duration)) {
        throw new Error('该时段已有两个任务包，不能继续安排');
      }
      draft.events.push(copy);
    });
  }

  public getEventsByDate(dateStr: string): ScheduledEvent[] {
    return this.events.filter((event: ScheduledEvent) => event.date === dateStr);
  }

  public getEventById(eventId: string): ScheduledEvent | undefined {
    return this.events.find((event: ScheduledEvent) => event.id === eventId);
  }

  public isPackageScheduledOnDate(packageId: string, dateStr: string): boolean {
    return this.events.some((event: ScheduledEvent) => event.packageId === packageId && event.date === dateStr);
  }

  public canPlaceInterval(
    dateStr: string,
    startMinutes: number,
    duration: number,
    excludedEventId: string = ''
  ): boolean {
    if (validateInterval(startMinutes, duration) !== '') {
      return false;
    }
    const endMinutes: number = startMinutes + duration;
    const events: ScheduledEvent[] = this.events.filter(
      (event: ScheduledEvent) => event.date === dateStr && event.id !== excludedEventId
    );
    const boundaries: Array<{ minute: number; delta: number }> = [];
    for (const event of events) {
      const eventStart: number = event.startHour * 60 + event.startMinute;
      const eventEnd: number = event.endHour * 60 + event.endMinute;
      boundaries.push({ minute: eventStart, delta: 1 });
      boundaries.push({ minute: eventEnd, delta: -1 });
    }
    boundaries.push({ minute: startMinutes, delta: 1 });
    boundaries.push({ minute: endMinutes, delta: -1 });
    boundaries.sort((left, right) => left.minute === right.minute ? left.delta - right.delta : left.minute - right.minute);
    let concurrent: number = 0;
    for (const boundary of boundaries) {
      concurrent += boundary.delta;
      if (concurrent > 2) {
        return false;
      }
    }
    return true;
  }

  public async removeEvent(eventId: string): Promise<void> {
    if (!this.events.some((event: ScheduledEvent) => event.id === eventId)) {
      return;
    }
    await appStore.mutate((draft) => {
      draft.events = draft.events.filter((event) => event.id !== eventId);
    });
    this.notifyChange();
  }

  public async updateEvent(updatedEvent: ScheduledEvent): Promise<boolean> {
    const index: number = this.events.findIndex((event: ScheduledEvent) => event.id === updatedEvent.id);
    if (index < 0) {
      return false;
    }
    const copy: ScheduledEvent = cloneScheduledEvent(updatedEvent);
    const validationError: string = validateEvent(copy);
    if (validationError !== '') {
      throw new Error(validationError);
    }
    await appStore.mutate((draft) => {
      const targetIndex: number = draft.events.findIndex((event) => event.id === copy.id);
      if (targetIndex < 0) {
        throw new Error('日程不存在');
      }
      const start: number = copy.startHour * 60 + copy.startMinute;
      const duration: number = getTotalDuration(copy.steps);
      if (!this.canPlaceInterval(copy.date, start, duration, copy.id)) {
        throw new Error('该时段已有两个任务包，无法应用调整');
      }
      draft.events[targetIndex] = copy;
    });
    this.notifyChange();
    return true;
  }

  public getDatesWithEvents(year: number, month: number): Set<string> {
    const result: Set<string> = new Set<string>();
    for (const event of this.events) {
      const parts: string[] = event.date.split('-');
      if (parts.length === 3 && Number(parts[0]) === year && Number(parts[1]) - 1 === month) {
        result.add(event.date);
      }
    }
    return result;
  }

  public async removeEventsByPackageId(packageId: string): Promise<void> {
    if (!this.events.some((event: ScheduledEvent) => event.packageId === packageId)) {
      return;
    }
    await appStore.mutate((draft) => {
      draft.events = draft.events.filter((event) => event.packageId !== packageId);
    });
    this.notifyChange();
  }

  public onChange(listener: () => void): void {
    if (this.listeners.indexOf(listener) === -1) {
      this.listeners.push(listener);
    }
  }

  public offChange(listener: () => void): void {
    const index: number = this.listeners.indexOf(listener);
    if (index !== -1) {
      this.listeners.splice(index, 1);
    }
  }

  private notifyChange(): void {
    for (const listener of this.listeners) {
      try {
        listener();
      } catch (_error) {
        // One view must not prevent other subscribers from refreshing.
      }
    }
  }
}

export const scheduleStore: ScheduleStore = new ScheduleStore();
