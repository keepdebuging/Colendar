/**
 * ScheduledEvent.ets —— 日程安排数据模型
 *
 * Week 2 新增。当一个任务包被拖放到日历的某个日期上时，
 * 就会创建一个 ScheduledEvent，记录"哪个任务包被安排到了哪一天"。
 */

// 导入任务包模型（用于关联查找）
import { TaskPackage, TaskStep } from './TaskPackage';
import { generateId } from './TaskPackage';
import { persistence } from './Persistence';

/**
 * ScheduledEvent 接口 —— 一次日程安排
 */
export interface ScheduledEvent {
  /** 唯一标识 */
  id: string;
  /** 日期字符串，格式 "YYYY-MM-DD"，例如 "2026-06-29" */
  date: string;
  /** 关联的任务包 ID */
  packageId: string;
  /** 关联的任务包名称（冗余存储，方便显示时不需要再查 TaskStore） */
  packageName: string;
  /** 与该任务包对应的颜色（冗余存储） */
  color: string;
  /** 在日视图中的开始小时（0-23），默认 9 点 */
  startHour: number;
  /** 在日视图中的开始分钟（0-59），默认 0 分 */
  startMinute: number;
  /** 结束小时（0-23），根据 startTime + 步骤总时长自动计算 */
  endHour: number;
  /** 结束分钟（0-59） */
  endMinute: number;
  /** 关联的步骤列表（冗余存储，方便在日视图中展示步骤摘要） */
  steps: TaskStep[];
  /** 是否启用应用内开始提醒；旧数据缺少该字段时按启用处理 */
  reminderEnabled?: boolean;
}

/**
 * 计算任务包步骤总时长（分钟）
 */
export function getTotalDuration(steps: TaskStep[]): number {
  if (!steps || steps.length === 0) {
    return 60;
  }
  return steps.reduce((sum: number, s: TaskStep) => sum + s.duration, 0);
}

/** 日程安排列表在 Preferences 中的存储键 */
const SCHEDULE_EVENTS_KEY: string = 'scheduled_events';

/**
 * ScheduleStore —— 日程安排全局数据仓库（单例模式）
 *
 * 用于存储和管理所有日程安排记录。
 * 与 TaskStore 独立，但通过 packageId 建立关联。
 */
class ScheduleStore {
  private static instance: ScheduleStore;

  /** 所有日程安排的数组 */
  public events: ScheduledEvent[] = [];

  /**
   * 数据变更监听器集合。
   * UI 层（如 CalendarTab）订阅后，数据因级联同步（编辑/删除任务包）而变化时，
   * 主动收到通知并刷新界面，不依赖页面生命周期（onPageShow）的可靠性。
   */
  private listeners: Array<() => void> = [];

  static getInstance(): ScheduleStore {
    if (!ScheduleStore.instance) {
      ScheduleStore.instance = new ScheduleStore();
    }
    return ScheduleStore.instance;
  }

  /**
   * 添加一个日程安排
   */
  public addEvent(event: ScheduledEvent): void {
    this.events.push(event);
    this.persist();
  }

  /**
   * 获取指定日期的所有日程
   * @param dateStr 日期字符串 "YYYY-MM-DD"
   */
  public getEventsByDate(dateStr: string): ScheduledEvent[] {
    return this.events.filter((e: ScheduledEvent) => e.date === dateStr);
  }

  /**
   * 检查某个任务包是否已经被安排在某个日期
   * 用于防止重复安排
   */
  public isPackageScheduledOnDate(packageId: string, dateStr: string): boolean {
    return this.events.some(
      (e: ScheduledEvent) => e.packageId === packageId && e.date === dateStr
    );
  }

  /** 校验候选时间段，保证同一重叠组最多同时存在两个日程。 */
  public canPlaceInterval(
    dateStr: string, startMinutes: number, duration: number, excludedEventId: string = ''
  ): boolean {
    const endMinutes: number = startMinutes + Math.max(1, duration);
    const events: ScheduledEvent[] = this.events.filter(
      (event: ScheduledEvent) => event.date === dateStr && event.id !== excludedEventId
    );
    const directlyOverlapping: ScheduledEvent[] = [];
    for (const event of events) {
      const eventStart: number = event.startHour * 60 + event.startMinute;
      const eventEnd: number = eventStart + getTotalDuration(event.steps);
      if (startMinutes < eventEnd && eventStart < endMinutes) {
        directlyOverlapping.push(event);
      }
    }
    if (directlyOverlapping.length === 0) {
      return true;
    }
    if (directlyOverlapping.length >= 2) {
      return false;
    }
    const partner: ScheduledEvent = directlyOverlapping[0];
    const partnerStart: number = partner.startHour * 60 + partner.startMinute;
    const partnerEnd: number = partnerStart + getTotalDuration(partner.steps);
    return !events.some((event: ScheduledEvent) => {
      if (event.id === partner.id) {
        return false;
      }
      const eventStart: number = event.startHour * 60 + event.startMinute;
      const eventEnd: number = eventStart + getTotalDuration(event.steps);
      return partnerStart < eventEnd && eventStart < partnerEnd;
    });
  }

  /**
   * 删除指定 ID 的日程安排
   */
  public removeEvent(eventId: string): void {
    const initialLength: number = this.events.length;
    this.events = this.events.filter((e: ScheduledEvent) => e.id !== eventId);
    if (this.events.length < initialLength) {
      this.persist();
      this.notifyChange();
    }
  }

  /**
   * 更新一条日程并立即持久化。
   * 用于剪切后移动日程，以及时间轴拉伸调整。
   */
  public updateEvent(updatedEvent: ScheduledEvent): void {
    const index: number = this.events.findIndex(
      (event: ScheduledEvent) => event.id === updatedEvent.id
    );
    if (index !== -1) {
      this.events[index] = updatedEvent;
      this.persist();
      this.notifyChange();
    }
  }

  /**
   * 获取有日程安排的所有日期（用于月视图标记）
   * @param year 年份
   * @param month 月份 (0-11)
   */
  public getDatesWithEvents(year: number, month: number): Set<string> {
    const result: Set<string> = new Set();
    for (const event of this.events) {
      // 解析日期字符串
      const parts: string[] = event.date.split('-');
      if (parts.length === 3) {
        const eventYear: number = parseInt(parts[0]);
        const eventMonth: number = parseInt(parts[1]) - 1; // 转为 0-11
        if (eventYear === year && eventMonth === month) {
          result.add(event.date);
        }
      }
    }
    return result;
  }

  /**
   * 将当前日程安排列表序列化并写入 Preferences。
   * 在所有会改变 events 的方法（add / remove）末尾调用。
   */
  public persist(): void {
    persistence.writeString(SCHEDULE_EVENTS_KEY, JSON.stringify(this.events));
  }

  /**
   * 从 Preferences 读取日程安排列表并恢复内存数据。
   * 仅在应用启动时由 EntryAbility 调用一次，键不存在时保持空数组。
   */
  public restore(): void {
    const raw: string = persistence.readString(SCHEDULE_EVENTS_KEY);
    if (raw !== '') {
      this.events = JSON.parse(raw) as ScheduledEvent[];
    }
  }

  /**
   * 编辑任务包后，级联同步所有关联日程的冗余字段。
   *
   * 日程里冗余存储了 packageName / color / steps，任务包被编辑后这些字段会
   * 变成旧数据，导致日历上显示旧名称、旧颜色、旧步骤。本方法在任务包更新时
   * 同步这些字段，并基于新的步骤总时长重算结束时间（endHour / endMinute）。
   *
   * @param pkg 更新后的任务包数据
   */
  public syncPackageFields(pkg: TaskPackage): void {
    let changed: boolean = false;
    for (const event of this.events) {
      if (event.packageId === pkg.id) {
        event.packageName = pkg.name;
        event.color = pkg.color;
        event.steps = pkg.steps;
        // 基于新的步骤总时长重算结束时间
        const totalMin: number = getTotalDuration(pkg.steps);
        const endTotalMin: number = event.startHour * 60 + event.startMinute + totalMin;
        event.endHour = Math.floor(endTotalMin / 60) % 24;
        event.endMinute = endTotalMin % 60;
        changed = true;
      }
    }
    if (changed) {
      this.persist();
      this.notifyChange();
    }
  }

  /**
   * 删除任务包后，级联删除所有关联日程，避免产生"幽灵日程"。
   *
   * @param packageId 被删除的任务包 ID
   */
  public removeEventsByPackageId(packageId: string): void {
    const initialLength: number = this.events.length;
    this.events = this.events.filter((e: ScheduledEvent) => e.packageId !== packageId);
    if (this.events.length < initialLength) {
      this.persist();
      this.notifyChange();
    }
  }

  /**
   * 订阅数据变更。重复订阅同一函数会被去重。
   *
   * @param listener 数据变化时被调用的回调
   */
  public onChange(listener: () => void): void {
    if (this.listeners.indexOf(listener) === -1) {
      this.listeners.push(listener);
    }
  }

  /**
   * 取消订阅。
   *
   * @param listener 之前通过 onChange 注册的回调
   */
  public offChange(listener: () => void): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx !== -1) {
      this.listeners.splice(idx, 1);
    }
  }

  /**
   * 通知所有订阅者数据已变化。
   *
   * 数据在 CalendarTab 外被更新或删除时主动通知 UI 刷新。
   * addEvent 仍由拖拽调用方自行刷新，避免同一次安排重复重建。
   */
  private notifyChange(): void {
    for (const listener of this.listeners) {
      listener();
    }
  }
}

/** 导出全局唯一的日程仓库实例 */
export const scheduleStore: ScheduleStore = ScheduleStore.getInstance();
