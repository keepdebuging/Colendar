import { describe, it, expect } from '@ohos/hypium';
import {
  durationMinutesToHeight,
  resolveTimelinePlacement,
  timelineMinutesToY,
  timelineYToRawMinutes
} from '../main/ets/utils/TimelineGeometry';

export default function timelineGeometryTest() {
  describe('timelineGeometryTest', () => {
    it('round trips minutes and y with scroll and grid offsets', 0, () => {
      const y: number = timelineMinutesToY(615, 120, 0, 4);
      const minutes: number = timelineYToRawMinutes(y - 80, 80, 120, 0, 4);
      expect(Math.round(minutes)).assertEqual(615);
    });

    it('snaps only near half-hour markers', 0, () => {
      const nearMarker = resolveTimelinePlacement(119, 0, 120, 0, 0, 30, 8);
      const freePlacement = resolveTimelinePlacement(100, 0, 120, 0, 0, 30, 8);
      expect(nearMarker.minutes).assertEqual(60);
      expect(nearMarker.snappedToMarker).assertTrue();
      expect(freePlacement.minutes).assertEqual(50);
      expect(freePlacement.snappedToMarker).assertFalse();
    });

    it('clips placement so the event remains inside the day', 0, () => {
      const placement = resolveTimelinePlacement(2000, 0, 60, 0, 0, 90, 8);
      expect(placement.minutes).assertEqual(1350);
      expect(durationMinutesToHeight(90, 60)).assertEqual(90);
    });
  });
}
