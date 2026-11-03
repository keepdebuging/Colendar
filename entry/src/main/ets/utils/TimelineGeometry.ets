/** Shared, side-effect-free timeline coordinate calculations. */

export interface TimelinePlacement {
  minutes: number;
  hour: number;
  minute: number;
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

/**
 * Default to five-minute placement. Only points within thresholdVp of an HH:00/HH:30
 * marker snap to that marker.
 */
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
  const resolvedMinutes: number = clampTimelineMinutes(
    snappedToMarker ? nearestMarker : fiveMinuteValue,
    maxStartMinutes
  );
  const result: TimelinePlacement = {
    minutes: resolvedMinutes,
    hour: Math.floor(resolvedMinutes / 60),
    minute: resolvedMinutes % 60,
    snappedToMarker
  };
  return result;
}
