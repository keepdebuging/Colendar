export interface CalendarCell {
  date: number;
  dateStr: string;
  isToday: boolean;
  isCurrentMonth: boolean;
}

export interface WeekDayInfo {
  dateStr: string;
  dayOfWeek: number;
  dayNumber: number;
  monthNumber: number;
  isToday: boolean;
  dayName: string;
}

export function formatDateStr(year: number, month: number, day: number): string {
  return `${year}-${(month + 1).toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}`;
}

export function formatDateDisplay(dateStr: string): string {
  if (!dateStr) {
    return '';
  }
  const parts: string[] = dateStr.split('-');
  if (parts.length !== 3) {
    return dateStr;
  }
  return `${Number(parts[0])}年${Number(parts[1])}月${Number(parts[2])}日`;
}

export function getMondayOf(date: Date): Date {
  const monday: Date = new Date(date);
  const day: number = monday.getDay();
  monday.setDate(monday.getDate() + (day === 0 ? -6 : 1 - day));
  monday.setHours(0, 0, 0, 0);
  return monday;
}

export function buildMonthCells(year: number, month: number, todayStr: string): CalendarCell[] {
  const firstDay: Date = new Date(year, month, 1);
  const weekday: number = firstDay.getDay();
  const startOffset: number = weekday === 0 ? 6 : weekday - 1;
  const daysInMonth: number = new Date(year, month + 1, 0).getDate();
  const previousMonthDate: Date = new Date(year, month, 0);
  const previousMonthDays: number = previousMonthDate.getDate();
  const cells: CalendarCell[] = [];
  for (let index: number = 0; index < 42; index++) {
    const dayNumber: number = index - startOffset + 1;
    if (dayNumber >= 1 && dayNumber <= daysInMonth) {
      const dateStr: string = formatDateStr(year, month, dayNumber);
      cells.push({ date: dayNumber, dateStr, isToday: dateStr === todayStr, isCurrentMonth: true });
    } else if (dayNumber < 1) {
      const date: Date = new Date(year, month - 1, previousMonthDays + dayNumber);
      const dateStr: string = formatDateStr(date.getFullYear(), date.getMonth(), date.getDate());
      cells.push({ date: date.getDate(), dateStr, isToday: dateStr === todayStr, isCurrentMonth: false });
    } else {
      const date: Date = new Date(year, month + 1, dayNumber - daysInMonth);
      const dateStr: string = formatDateStr(date.getFullYear(), date.getMonth(), date.getDate());
      cells.push({ date: date.getDate(), dateStr, isToday: dateStr === todayStr, isCurrentMonth: false });
    }
  }
  return cells;
}

export function buildWeekDays(weekStart: Date, todayStr: string): WeekDayInfo[] {
  const dayNames: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  const days: WeekDayInfo[] = [];
  for (let index: number = 0; index < 7; index++) {
    const date: Date = new Date(weekStart);
    date.setDate(date.getDate() + index);
    const dateStr: string = formatDateStr(date.getFullYear(), date.getMonth(), date.getDate());
    days.push({
      dateStr,
      dayOfWeek: index,
      dayNumber: date.getDate(),
      monthNumber: date.getMonth() + 1,
      isToday: dateStr === todayStr,
      dayName: dayNames[index]
    });
  }
  return days;
}
