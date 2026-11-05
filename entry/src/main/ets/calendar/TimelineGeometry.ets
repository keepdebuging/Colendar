export interface TimeResult {
  hour: number;
  minute: number;
}

export interface TimelinePlacement extends TimeResult {
  minutes: number;
  snappedToMarker: boolean;
}

export function clampTimelineMinutes(minutes: number, maxStartMinutes: number = 1439): number {
  return Math.max(0, Math.min(maxStartMinutes, minutes));
}

export function timelineMinutesToY(
  minutes: number, hourHeight: number, visibleStartMinutes: number = 0,
  gridOffset: number = 0
): number {
  return (minutes - visibleStartMinutes) / 60 * hourHeight + gridOffset;
}

export function timelineYToRawMinutes(
  localY: number, scrollOffset: number, hourHeight: number,
  visibleStartMinutes: number = 0, gridOffset: number = 0
): number {
  if (hourHeight <= 0) {
    return visibleStartMinutes;
  }
  return visibleStartMinutes + (localY + scrollOffset - gridOffset) / hourHeight * 60;
}

export function durationMinutesToHeight(durationMinutes: number, hourHeight: number): number {
  return Math.max(0, durationMinutes) / 60 * hourHeight;
}

/** Place on a five-minute boundary and snap to HH:00/HH:30 only within a visual threshold. */
export function resolveTimelinePlacement(
  localY: number, scrollOffset: number, hourHeight: number,
  visibleStartMinutes: number = 0, gridOffset: number = 0,
  durationMinutes: number = 1, thresholdVp: number = 8
): TimelinePlacement {
  const maxStartMinutes: number = Math.max(0, 1440 - Math.max(1, durationMinutes));
  const rawMinutes: number = timelineYToRawMinutes(
    localY, scrollOffset, hourHeight, visibleStartMinutes, gridOffset
  );
  const fiveMinuteValue: number = Math.round(rawMinutes / 5) * 5;
  const nearestMarker: number = Math.round(rawMinutes / 30) * 30;
  const markerDistanceVp: number = Math.abs(rawMinutes - nearestMarker) / 60 * hourHeight;
  const snappedToMarker: boolean = markerDistanceVp <= thresholdVp;
  const minutes: number = clampTimelineMinutes(
    snappedToMarker ? nearestMarker : fiveMinuteValue, maxStartMinutes
  );
  return {
    minutes,
    hour: Math.floor(minutes / 60),
    minute: minutes % 60,
    snappedToMarker
  };
}

export function snapTimeFromY(
  y: number, scrollOffset: number, hourHeight: number, gridOffset: number,
  durationMinutes: number = 1, thresholdVp: number = 8
): TimeResult {
  const placement: TimelinePlacement = resolveTimelinePlacement(
    y, scrollOffset, hourHeight, 0, gridOffset, durationMinutes, thresholdVp
  );
  return { hour: placement.hour, minute: placement.minute };
}

export function eventBlockTop(startMinutes: number, hourHeight: number,
  visibleStartHour: number, gridOffset: number): number {
  return (startMinutes - visibleStartHour * 60) / 60 * hourHeight + gridOffset;
}

export function eventBlockHeight(durationMinutes: number, hourHeight: number, minimumHeight: number): number {
  return Math.max(durationMinutes / 60 * hourHeight, minimumHeight);
}
