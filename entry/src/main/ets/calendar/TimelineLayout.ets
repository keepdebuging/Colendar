import { ScheduledEvent } from '../models/ScheduledEvent';
import { getTotalDuration } from '../models/ScheduledEvent';

export interface WeekEventGroup {
  key: string;
  first: ScheduledEvent;
  second?: ScheduledEvent;
  backgroundEvent: ScheduledEvent;
  startMinutes: number;
  endMinutes: number;
}

export interface DayEventLayout {
  event: ScheduledEvent;
  column: number;
  isOverlapping: boolean;
}

function startMinutes(event: ScheduledEvent): number {
  return event.startHour * 60 + event.startMinute;
}

function endMinutes(event: ScheduledEvent): number {
  return event.endHour * 60 + event.endMinute;
}

function overlaps(first: ScheduledEvent, second: ScheduledEvent): boolean {
  return startMinutes(first) < endMinutes(second) && startMinutes(second) < endMinutes(first);
}

function sortedEvents(events: ScheduledEvent[]): ScheduledEvent[] {
  const result: ScheduledEvent[] = [...events];
  result.sort((first: ScheduledEvent, second: ScheduledEvent) => {
    const startDiff: number = startMinutes(first) - startMinutes(second);
    return startDiff !== 0 ? startDiff : endMinutes(second) - endMinutes(first);
  });
  return result;
}

export function buildWeekEventGroups(events: ScheduledEvent[]): WeekEventGroup[] {
  const sorted: ScheduledEvent[] = sortedEvents(events);
  const usedIds: Set<string> = new Set<string>();
  const groups: WeekEventGroup[] = [];
  for (let firstIndex: number = 0; firstIndex < sorted.length; firstIndex++) {
    const first: ScheduledEvent = sorted[firstIndex];
    if (usedIds.has(first.id)) {
      continue;
    }
    let second: ScheduledEvent | undefined = undefined;
    for (let secondIndex: number = firstIndex + 1; secondIndex < sorted.length; secondIndex++) {
      const candidate: ScheduledEvent = sorted[secondIndex];
      if (!usedIds.has(candidate.id) && overlaps(first, candidate)) {
        second = candidate;
        break;
      }
    }
    usedIds.add(first.id);
    if (!second) {
      groups.push({
        key: first.id,
        first,
        backgroundEvent: first,
        startMinutes: startMinutes(first),
        endMinutes: endMinutes(first)
      });
      continue;
    }
    usedIds.add(second.id);
    groups.push({
      key: `${first.id}-${second.id}`,
      first,
      second,
      backgroundEvent: getTotalDuration(first.steps) >= getTotalDuration(second.steps) ? first : second,
      startMinutes: Math.min(startMinutes(first), startMinutes(second)),
      endMinutes: Math.max(endMinutes(first), endMinutes(second))
    });
  }
  return groups;
}

export function buildDayEventLayouts(events: ScheduledEvent[]): DayEventLayout[] {
  const sorted: ScheduledEvent[] = sortedEvents(events);
  const columnEnds: number[] = [-1, -1];
  const result: DayEventLayout[] = [];
  for (let index: number = 0; index < sorted.length; index++) {
    const event: ScheduledEvent = sorted[index];
    const start: number = startMinutes(event);
    const isOverlapping: boolean = sorted.some((other, otherIndex) => otherIndex !== index && overlaps(event, other));
    let column: number = 0;
    if (isOverlapping && start < columnEnds[0]) {
      column = 1;
    }
    columnEnds[column] = endMinutes(event);
    result.push({ event, column, isOverlapping });
  }
  return result;
}
