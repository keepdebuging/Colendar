/**
 * CalendarTab.ets —— Tab 2 日历总览页（核心功能）
 *
 * Week 2: 双列布局 + 拖拽排程 + 月/日视图切换。
 * Week 3: 代码结构重组、今天按钮、填充格区分、性能优化、拖拽数据通道完善。
 * Week 4: 视图切换（月/周/日）+ 平滑动画 + 非本月日期显示 + 导航扩展。
 *
 * 布局（所有视图统一）：
 * ┌──────────┬─────────────────────────────────────┐
 * │ 左侧 30% │ 右侧 70%（日历区域）                   │
 * │          │ [导航栏]  〈 标题  [月|周|日]  〉      │
 * │ 任务包   │ [日历内容区]                           │
 * │ 卡片列表 │   月视图：网格                         │
 * │ (拖拽源) │   周视图：7列时间轴                     │
 * │          │   日视图：24小时时间轴                   │
 * └──────────┴─────────────────────────────────────┘
 */

import { promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { TaskPackage, taskStore, TaskStep } from '../models/TaskPackage';
import { ScheduledEvent, scheduleStore, getTotalDuration } from '../models/ScheduledEvent';
import { ExecutionSession, executionStore } from '../models/ExecutionSession';
import { generateId } from '../models/TaskPackage';
import { PackageDetailDialog } from './PackageDetailDialog';
import { ScheduledEventDetailDialog } from './ScheduledEventDetailDialog';
import { UpcomingTaskDialog } from './UpcomingTaskDialog';

// ==================== 接口定义 ====================

/** 日历网格中每个格子的数据（月视图） */
interface CalendarCell {
  /** 日期数字（1-31，或上月/下月的实际日期） */
  date: number;
  /** 完整日期字符串 "YYYY-MM-DD"，非当月格子也有有效值 */
  dateStr: string;
  /** 是否是今天 */
  isToday: boolean;
  /** 是否属于当前月份 */
  isCurrentMonth: boolean;
}

/** 周视图中每一天的信息 */
interface WeekDayInfo {
  /** 完整日期字符串 "YYYY-MM-DD" */
  dateStr: string;
  /** 星期几（0=周一, 6=周日） */
  dayOfWeek: number;
  /** 日期数字 (1-31) */
  dayNumber: number;
  /** 月份数字 (1-12) */
  monthNumber: number;
  /** 是否是今天 */
  isToday: boolean;
  /** 星期名称缩写 */
  dayName: string;
}

/** 时间吸附结果 */
interface TimeResult {
  /** 小时 (0-23) */
  hour: number;
  /** 分钟 (0-59) */
  minute: number;
}

/** 周视图中的一个显示单元：单个日程，或由两个重叠日程合成的卡片。 */
interface WeekEventGroup {
  key: string;
  first: ScheduledEvent;
  second?: ScheduledEvent;
  backgroundEvent: ScheduledEvent;
  startMinutes: number;
  endMinutes: number;
}

/** 日视图事件的横向布局结果。 */
interface DayEventLayout {
  event: ScheduledEvent;
  column: number;
  isOverlapping: boolean;
}

// ==================== 布局常量 ====================

/** 周视图：显示的起始小时（0点） */
const WEEK_START_HOUR: number = 0;

/** 周视图：显示的结束小时（含 24:00） */
const WEEK_END_HOUR: number = 25;

/** 日视图：每小时对应的高度（vp） */
const DAY_HOUR_HEIGHT: number = 60;

/** 周/日时间轴双指缩放范围（vp/小时） */
const MIN_HOUR_HEIGHT: number = 45;
const MAX_HOUR_HEIGHT: number = 150;

/**
 * 时间轴分割线相对每个小时槽位顶部的下移量（vp）。
 * 用于抵消 fontSize=9 标签字形的 ascender 偏移，使分割线与标签文字、
 * 以及事件块上边界精确对齐（log_09 的「分割线下移」方案即此值）。
 */
const GRID_LINE_OFFSET: number = 3;

/** 时间轴网格线颜色；需在彩色事件块上保持足够对比度 */
const GRID_LINE_COLOR: string = '#B8B8B8';

// ==================== 组件 ====================

@Component
export struct CalendarTab {
  // ==================== @Prop 声明 ====================

  /** 从 Index 的 @Provide 直连获取，值变化时 @Watch 自动调用 loadData() */
  @Consume @Watch('loadData') refreshTrigger: number = 0;

  // ==================== @State 声明 ====================

  /** 左侧面板的任务包列表 */
  @State packages: TaskPackage[] = [];
  /** 所有日程安排 */
  @State schedules: ScheduledEvent[] = [];
  /** 当前日历年份 */
  @State currentYear: number = new Date().getFullYear();
  /** 当前日历月份（0=1月, 11=12月） */
  @State currentMonth: number = new Date().getMonth();
  /**
   * 视图模式：'month' 月视图 | 'week' 周视图 | 'day' 日视图
   * Week 4 新增 'week' 模式
   */
  @State viewMode: string = 'month';
  /**
   * 当前选中的日期字符串 "YYYY-MM-DD"
   * 在三个视图间保持一致：切换视图时沿用此日期定位
   */
  @State selectedDateStr: string = '';
  /** 选中日期的人类可读形式，如 "2026年6月30日" */
  @State selectedDateDisplay: string = '';
  /**
   * 当前周视图的起始日期（周一），作为 Date 对象
   * 用于周视图的导航和日期范围显示
   */
  @State currentWeekStart: Date = CalendarTab.getMondayOf(new Date());
  /** 拖拽过程中高亮的日期 */
  @State dropHighlightDate: string = '';
  /** 当前正在被拖拽的 packageId（拖拽数据传递的后备通道） */
  @State private activeDragPkgId: string = '';
  /** 日历网格中的日期格子（由 buildCalendar 计算） */
  @State calendarCells: CalendarCell[] = [];
  /** 周视图的 7 天信息（由 buildWeekData 计算） */
  @State weekDays: WeekDayInfo[] = [];
  /**
   * 日视图缩放比例，1 = 正常大小。
   * 从周/月视图点击某天进入日视图时，从 <1 动画过渡到 1，
   * 模拟"从那天放大展开"的视觉效果。
   */
  @State dayViewScale: number = 1;
  /**
   * 左侧任务包面板是否展开。
   * false = 折叠到 10%（灰色窄条），true = 展开到 30%（完整面板）。
   * 点击折叠态灰色条展开，点击展开态"←"按钮收起。
   */
  @State isLeftPanelExpanded: boolean = false;

  // ==================== 拖拽预览状态 ====================

  /** 拖拽预览条是否可见 */
  @State dragPreviewVisible: boolean = false;
  /** 预览：目标日期 "YYYY-MM-DD" */
  @State dragPreviewDate: string = '';
  /** 预览：吸附后的小时 */
  @State dragPreviewHour: number = 0;
  /** 预览：吸附后的分钟 */
  @State dragPreviewMinute: number = 0;
  /** 预览：结束小时 */
  @State dragPreviewEndHour: number = 1;
  /** 预览：结束分钟 */
  @State dragPreviewEndMinute: number = 0;
  /** 预览：任务包名称 */
  @State dragPreviewPkgName: string = '';
  /** 预览：任务包颜色 */
  @State dragPreviewColor: string = '#007AFF';
  /** 预览是否包含已吸附的时间（true=显示时间范围，false=仅显示日期+名称） */
  @State dragPreviewHasTime: boolean = false;
  /** 周视图当前每小时高度（双指缩放范围 45~150vp） */
  @State private weekHourHeight: number = MIN_HOUR_HEIGHT;
  /** 日视图当前每小时高度（双指缩放范围 45~150vp） */
  @State private dayHourHeight: number = DAY_HOUR_HEIGHT;
  /** 待粘贴日程的操作类型：'' | 'copy' | 'cut' */
  @State private transferMode: string = '';
  /** 待粘贴提示中显示的任务包名称 */
  @State private transferEventName: string = '';
  /** 当前进入拉伸模式的日程 ID */
  @State private stretchEventId: string = '';
  /** 由自定义长按手势控制显示的日程菜单 ID */
  @State private contextMenuEventId: string = '';
  /** 拉伸中的预览开始分钟、总时长与步骤副本 */
  @State private stretchPreviewStartMinutes: number = 0;
  @State private stretchPreviewDuration: number = 0;
  @State private stretchPreviewSteps: TaskStep[] = [];
  /** 当前被拖拽任务包的总时长（分钟），用于计算结束时间 */
  private dragPkgTotalMin: number = 60;
  /** 周/日视图的滚动控制器；用于缩放锚定与拖拽坐标换算 */
  private weekScroller: Scroller = new Scroller();
  private dayScroller: Scroller = new Scroller();
  /** 时间轴可视区域顶部在窗口坐标系中的 Y；拖拽点也是窗口坐标，二者相减后才是局部坐标。 */
  private weekTimelineWindowY: number = 0;
  private dayTimelineWindowY: number = 0;
  /** 本轮捏合开始时的小时高度、滚动偏移和中心对应时间 */
  private pinchStartHourHeight: number = DAY_HOUR_HEIGHT;
  private pinchStartScrollOffset: number = 0;
  private pinchAnchorMinutes: number = 0;
  /** 复制/剪切时保存的日程快照；粘贴前不修改原日程 */
  private pendingTransferEvent: ScheduledEvent | null = null;
  /** 拉伸手势开始时的日程快照，确保 offset 始终基于同一基准计算 */
  private stretchOriginalEvent: ScheduledEvent | null = null;

  // ==================== 当前时间指示线状态 ====================

  /** 当前小时 (0-23)，每秒刷新 */
  @State nowHour: number = new Date().getHours();
  /** 当前分钟 (0-59) */
  @State nowMinute: number = new Date().getMinutes();
  /** 当前秒 (0-59)，用于让“现在”指示线连续移动 */
  @State nowSecond: number = new Date().getSeconds();

  /**
   * 日程数据版本号：每次 loadData() 自增，改变时间轴 ForEach 的 key，
   * 强制事件块重建，确保编辑任务包后时间轴立即刷新。
   * 与 TaskPackage._version 同理——ForEach 会复用「key 未变」的旧 Item、不重建。
   */
  @State private schedulesVersion: number = 0;

  // ==================== 私有字段 ====================

  /**
   * 当前月份中有日程安排的日期集合（Set 实现 O(1) 查找）。
   * 每次 loadData / 拖拽放下 / 导航变化后由 scheduleStore 预计算。
   */
  private eventsDateSet: Set<string> = new Set();

  /** 当前时间刷新定时器 ID，aboutToDisappear 时清除 */
  private timeTimer: number = -1;
  /** 等待小时高度布局完成后执行的缩放锚点校正任务 */
  private weekPinchScrollTimer: number = -1;
  private dayPinchScrollTimer: number = -1;
  /** 每一帧最新的缩放锚点偏移，供布局完成后的二次校正读取 */
  private weekPendingPinchOffset: number = 0;
  private dayPendingPinchOffset: number = 0;

  /**
   * ScheduleStore 数据变更监听器。
   * 编辑任务包会级联更新日程（syncPackageFields），此时 onPageShow→refreshTrigger
   * 链路在 router.back 返回时不可靠，改用数据层主动通知，确保时间轴立即刷新。
   */
  private scheduleStoreListener: (() => void) | null = null;
  /** 执行状态变化监听器，用于在任务完成后立即刷新日历卡片样式。 */
  private executionStoreListener: (() => void) | null = null;
  /** 本次前台生命周期中已经给过一分钟弱提示的日程。 */
  private oneMinuteNotifiedEventIds: Set<string> = new Set();
  /** 已经弹出过开始确认框的日程，避免每秒重复弹窗。 */
  private promptedEventIds: Set<string> = new Set();
  /** “稍后”后的临时开始时间；第一版固定延后 5 分钟，仅在当前前台会话有效。 */
  private snoozedStartTimes: Map<string, number> = new Map();
  private upcomingDialogOpen: boolean = false;

  // ==================== 计算属性 ====================

  /** 获取当前选中日期的所有日程 */
  get dayEvents(): ScheduledEvent[] {
    if (!this.selectedDateStr) {
      return [];
    }
    return scheduleStore.getEventsByDate(this.selectedDateStr);
  }

  /** 月视图标题 */
  get monthLabel(): string {
    return `${this.currentYear}年 ${this.currentMonth + 1}月`;
  }

  /**
   * 周视图标题：显示本周的日期范围
   * 例如："6月22日 - 6月28日"
   */
  get weekLabel(): string {
    const end: Date = new Date(this.currentWeekStart);
    end.setDate(end.getDate() + 6); // 周日
    const startStr: string =
      `${this.currentWeekStart.getMonth() + 1}月${this.currentWeekStart.getDate()}日`;
    const endStr: string =
      `${end.getMonth() + 1}月${end.getDate()}日`;
    return `${startStr} - ${endStr}`;
  }

  /**
   * 周数标签，例如 "27周"。
   * 基于 currentWeekStart（周一）计算 ISO 周数。
   */
  get weekNumberLabel(): string {
    const monday: Date = new Date(this.currentWeekStart);
    const thursday: Date = new Date(monday);
    thursday.setDate(monday.getDate() + 3);
    const jan1: Date = new Date(thursday.getFullYear(), 0, 1);
    const days: number = Math.round((thursday.getTime() - jan1.getTime()) / 86400000);
    const weekNum: number = Math.floor(days / 7) + 1;
    return `${weekNum}周`;
  }

  /** 日视图标题：显示完整日期和星期 */
  get dayLabel(): string {
    if (!this.selectedDateStr) {
      return '';
    }
    const parts: string[] = this.selectedDateStr.split('-');
    if (parts.length !== 3) {
      return this.selectedDateStr;
    }
    const d: Date = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
    const weekNames: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
    const weekDay: string = weekNames[d.getDay()];
    return `${parseInt(parts[0])}年${parseInt(parts[1])}月${parseInt(parts[2])}日 ${weekDay}`;
  }

  // ==================== 生命周期 ====================

  aboutToAppear(): void {
    // 初始化选中的日期为今天
    const today: Date = new Date();
    this.selectedDateStr = this.formatDateStr(
      today.getFullYear(), today.getMonth(), today.getDate()
    );
    this.selectedDateDisplay = this.dayLabel;
    this.loadData();
    this.buildCalendar();
    this.buildWeekData();

    // 每秒推进一次；单次位移远小于 1vp，不使用会与缩放位置竞争的显式动画。
    this.updateNowTime();
    this.timeTimer = setInterval(() => {
      this.updateNowTime();
    }, 1000);

    // 订阅日程数据变更：编辑任务包级联更新日程后，主动刷新时间轴，
    // 不依赖 onPageShow（其在 router.back 返回时对 @Consume @Watch 不可靠）。
    this.scheduleStoreListener = (): void => {
      this.loadData();
    };
    scheduleStore.onChange(this.scheduleStoreListener);

    this.executionStoreListener = (): void => {
      this.schedulesVersion++;
    };
    executionStore.onChange(this.executionStoreListener);
  }

  aboutToDisappear(): void {
    if (this.timeTimer !== -1) {
      clearInterval(this.timeTimer);
      this.timeTimer = -1;
    }
    if (this.weekPinchScrollTimer !== -1) {
      clearTimeout(this.weekPinchScrollTimer);
      this.weekPinchScrollTimer = -1;
    }
    if (this.dayPinchScrollTimer !== -1) {
      clearTimeout(this.dayPinchScrollTimer);
      this.dayPinchScrollTimer = -1;
    }
    // 取消日程数据订阅，避免组件销毁后监听器仍持有 this 造成泄漏
    if (this.scheduleStoreListener !== null) {
      scheduleStore.offChange(this.scheduleStoreListener);
      this.scheduleStoreListener = null;
    }
    if (this.executionStoreListener !== null) {
      executionStore.offChange(this.executionStoreListener);
      this.executionStoreListener = null;
    }
  }

  /** 刷新当前时间（驱动指示线位置更新） */
  updateNowTime(): void {
    const now: Date = new Date();
    this.nowHour = now.getHours();
    this.nowMinute = now.getMinutes();
    this.nowSecond = now.getSeconds();
    this.checkUpcomingEvents(now.getTime());
  }

  /** 把日程的本地日期和开始时间转换成时间戳。 */
  private getScheduledStartMs(evt: ScheduledEvent): number {
    const parts: string[] = evt.date.split('-');
    if (parts.length !== 3) {
      return 0;
    }
    return new Date(
      parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]),
      evt.startHour, evt.startMinute, 0, 0
    ).getTime();
  }

  /** 前台应用内提醒：一分钟弱提示，开始前 20 秒显示确认框。 */
  private checkUpcomingEvents(nowMs: number): void {
    if (this.upcomingDialogOpen) {
      return;
    }
    for (const evt of scheduleStore.events) {
      if (evt.reminderEnabled === false || executionStore.getLatestSessionByEventId(evt.id)) {
        continue;
      }
      const snoozedStart: number | undefined = this.snoozedStartTimes.get(evt.id);
      const targetStartMs: number = snoozedStart !== undefined ?
        snoozedStart : this.getScheduledStartMs(evt);
      const remainingMs: number = targetStartMs - nowMs;
      if (remainingMs <= 60000 && remainingMs > 20000 &&
        !this.oneMinuteNotifiedEventIds.has(evt.id)) {
        this.oneMinuteNotifiedEventIds.add(evt.id);
        promptAction.showToast({
          message: `“${evt.packageName}”将在 1 分钟内开始`,
          duration: 2200
        });
      }
      if (remainingMs <= 20000 && remainingMs > 0 && !this.promptedEventIds.has(evt.id)) {
        this.showUpcomingTaskDialog(evt, targetStartMs);
        return;
      }
      if (remainingMs <= 0) {
        this.promptedEventIds.add(evt.id);
      }
    }
  }

  private showUpcomingTaskDialog(evt: ScheduledEvent, targetStartMs: number): void {
    this.upcomingDialogOpen = true;
    this.promptedEventIds.add(evt.id);
    const dialogController: CustomDialogController = new CustomDialogController({
      builder: UpcomingTaskDialog({
        event: evt,
        targetStartMs: targetStartMs,
        onStart: () => {
          dialogController.close();
          this.upcomingDialogOpen = false;
          this.snoozedStartTimes.delete(evt.id);
          this.startScheduledEventFromReminder(evt);
        },
        onLater: () => {
          dialogController.close();
          this.upcomingDialogOpen = false;
          this.promptedEventIds.delete(evt.id);
          this.oneMinuteNotifiedEventIds.delete(evt.id);
          this.snoozedStartTimes.set(evt.id, Date.now() + 5 * 60 * 1000);
          promptAction.showToast({ message: '已稍后 5 分钟提醒', duration: 1800 });
        }
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center,
      customStyle: true,
      cornerRadius: 18
    });
    dialogController.open();
  }

  private startScheduledEventFromReminder(evt: ScheduledEvent): void {
    const session: ExecutionSession | undefined = executionStore.startFromScheduledEvent(evt);
    if (!session) {
      promptAction.showToast({ message: '请先结束或继续当前正在执行的任务', duration: 2200 });
      return;
    }
    router.pushUrl({
      url: 'pages/ExecutionPage',
      params: { sessionId: session.id, prepare: 'true' }
    });
  }

  // ==================== 数据加载 ====================

  /**
   * 从全局仓库同步最新数据。
   * 同时预计算当月日程日期集合，供 hasEventsOnDate O(1) 查询。
   */
  loadData(): void {
    this.packages = [...taskStore.packages];
    this.schedules = [...scheduleStore.events];
    this.refreshEventsDateSet();
    this.buildCalendar();
    this.buildWeekData();
    // 数据已重载：自增版本号，改变时间轴 ForEach 的 key，强制事件块重建
    this.schedulesVersion++;
  }

  /** 刷新当月有日程的日期 Set */
  private refreshEventsDateSet(): void {
    this.eventsDateSet = scheduleStore.getDatesWithEvents(
      this.currentYear, this.currentMonth
    );
  }

  /** 只有正常完成的执行记录才把对应日程标记为已完成。 */
  private isEventCompleted(evt: ScheduledEvent): boolean {
    return this.getEventCompletionCount(evt) > 0;
  }

  /** 返回同一日程实例历史上正常完成的次数。 */
  private getEventCompletionCount(evt: ScheduledEvent): number {
    return executionStore.sessions.filter((session: ExecutionSession) =>
      session.scheduledEventId === evt.id && session.status === 'completed'
    ).length;
  }

  /** 已完成的日程在标题后展示累计完成次数。 */
  private getEventDisplayTitle(evt: ScheduledEvent): string {
    const completedCount: number = this.getEventCompletionCount(evt);
    return completedCount > 0 ? `${evt.packageName} · 已完成${completedCount}次` : evt.packageName;
  }

  // ==================== 日历计算 ====================

  /**
   * 将日期格式化为 "YYYY-MM-DD" 字符串
   */
  formatDateStr(year: number, month: number, day: number): string {
    const m: string = (month + 1).toString().padStart(2, '0');
    const d: string = day.toString().padStart(2, '0');
    return `${year}-${m}-${d}`;
  }

  /**
   * 格式化日期为人类可读形式："YYYY年M月D日"
   */
  formatDateDisplay(dateStr: string): string {
    if (!dateStr) {
      return '';
    }
    const parts: string[] = dateStr.split('-');
    if (parts.length !== 3) {
      return dateStr;
    }
    return `${parseInt(parts[0])}年${parseInt(parts[1])}月${parseInt(parts[2])}日`;
  }

  /**
   * 构建月视图的日历网格数据
   *
   * Week 4 改进：非当月格子不再显示 date=-1，而是显示上月/下月的实际日期，
   * 并用灰色字体区分。
   *
   * 算法：
   * 1. 计算当月第一天是周几（周一=0, 周日=6）
   * 2. 计算当月有多少天
   * 3. 生成 6 行 × 7 列 = 42 个格子
   * 4. 首尾空白格填入上月/下月的实际日期
   */
  buildCalendar(): void {
    const today: Date = new Date();
    const todayStr: string = this.formatDateStr(
      today.getFullYear(), today.getMonth(), today.getDate()
    );

    // 当月第一天
    const firstDay: Date = new Date(this.currentYear, this.currentMonth, 1);
    // getDay(): 0=周日, 1=周一, ..., 6=周六
    let startDayOfWeek: number = firstDay.getDay();
    // 转换为周一=0, 周日=6
    startDayOfWeek = startDayOfWeek === 0 ? 6 : startDayOfWeek - 1;

    // 当月天数
    const daysInMonth: number = new Date(
      this.currentYear, this.currentMonth + 1, 0
    ).getDate();

    // 上月信息（用于计算首部填充格的实际日期）
    let prevMonth: number = this.currentMonth - 1;
    let prevYear: number = this.currentYear;
    if (prevMonth < 0) {
      prevMonth = 11;
      prevYear -= 1;
    }
    const prevMonthDays: number = new Date(prevYear, prevMonth + 1, 0).getDate();

    // 下月信息（用于计算尾部填充格的实际日期）
    let nextMonth: number = this.currentMonth + 1;
    let nextYear: number = this.currentYear;
    if (nextMonth > 11) {
      nextMonth = 0;
      nextYear += 1;
    }

    // 构建网格（固定 6 行 × 7 列 = 42 格）
    const cells: CalendarCell[] = [];
    const totalCells: number = 42;

    for (let i: number = 0; i < totalCells; i++) {
      const dayNum: number = i - startDayOfWeek + 1; // 从 1 开始

      if (dayNum >= 1 && dayNum <= daysInMonth) {
        // ===== 当月日期 =====
        const dateStr: string = this.formatDateStr(
          this.currentYear, this.currentMonth, dayNum
        );
        cells.push({
          date: dayNum,
          dateStr: dateStr,
          isToday: dateStr === todayStr,
          isCurrentMonth: true
        });
      } else if (dayNum < 1) {
        // ===== 上月末尾填充格（Week 4 改进：显示实际日期） =====
        // dayNum 为 0, -1, -2... 表示上月倒数第1、第2、第3...天
        const prevDay: number = prevMonthDays + dayNum;
        const dateStr: string = this.formatDateStr(prevYear, prevMonth, prevDay);
        cells.push({
          date: prevDay,
          dateStr: dateStr,
          isToday: dateStr === todayStr,
          isCurrentMonth: false
        });
      } else {
        // ===== 下月开头填充格（Week 4 改进：显示实际日期） =====
        const nextDay: number = dayNum - daysInMonth;
        const dateStr: string = this.formatDateStr(nextYear, nextMonth, nextDay);
        cells.push({
          date: nextDay,
          dateStr: dateStr,
          isToday: dateStr === todayStr,
          isCurrentMonth: false
        });
      }
    }

    this.calendarCells = cells;
  }

  /**
   * 构建周视图的 7 天数据
   *
   * 以 currentWeekStart（周一）为基准，生成周一到周日的 7 天信息。
   */
  buildWeekData(): void {
    const today: Date = new Date();
    const todayStr: string = this.formatDateStr(
      today.getFullYear(), today.getMonth(), today.getDate()
    );
    const dayNames: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    const weekDays: WeekDayInfo[] = [];

    for (let i: number = 0; i < 7; i++) {
      const day: Date = new Date(this.currentWeekStart);
      day.setDate(day.getDate() + i);
      const dateStr: string = this.formatDateStr(
        day.getFullYear(), day.getMonth(), day.getDate()
      );
      weekDays.push({
        dateStr: dateStr,
        dayOfWeek: i, // 0=周一
        dayNumber: day.getDate(),
        monthNumber: day.getMonth() + 1,
        isToday: dateStr === todayStr,
        dayName: dayNames[i]
      });
    }

    this.weekDays = weekDays;
  }

  // ==================== 视图切换（Week 4 新增） ====================

  /**
   * 切换视图模式，带平滑过渡动画。
   *
   * 切换逻辑：
   * - 如果 selectedDateStr 为空，取今天
   * - 切换到月视图：用 selectedDateStr 的年份和月份
   * - 切换到周视图：用 selectedDateStr 所在周的周一
   * - 切换到日视图：直接使用 selectedDateStr
   *
   * @param mode 目标视图模式 'month' | 'week' | 'day'
   */
  switchToView(mode: string): void {
    if (mode === this.viewMode) {
      return; // 已经在目标视图，不重复切换
    }

    // 确保 selectedDateStr 有效（为空时取今天）
    if (!this.selectedDateStr) {
      const today: Date = new Date();
      this.selectedDateStr = this.formatDateStr(
        today.getFullYear(), today.getMonth(), today.getDate()
      );
    }

    // 解析 selectedDateStr
    const parts: string[] = this.selectedDateStr.split('-');
    if (parts.length !== 3) {
      return;
    }
    const selYear: number = parseInt(parts[0]);
    const selMonth: number = parseInt(parts[1]) - 1;
    const selDay: number = parseInt(parts[2]);
    const selDate: Date = new Date(selYear, selMonth, selDay);

    /**
     * animateTo：鸿蒙声明式 UI 的显式动画 API。
     * 在闭包内修改的状态会触发过渡动画，而非立即跳变。
     *
     * 日视图特殊处理：从月/周切换到日时，先缩小（0.7）再在 animateTo
     * 中放大到 1，模拟"聚焦到那天"的视觉效果。
     */
    if (mode === 'day') {
      this.dayViewScale = 0.7;
    }

    animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
      this.viewMode = mode;

      // 根据目标视图更新对应的导航状态
      if (mode === 'month') {
        this.currentYear = selYear;
        this.currentMonth = selMonth;
        this.refreshEventsDateSet();
        this.buildCalendar();
      } else if (mode === 'week') {
        this.currentWeekStart = CalendarTab.getMondayOf(selDate);
        this.buildWeekData();
      } else if (mode === 'day') {
        // 从缩小状态放大到正常大小
        this.dayViewScale = 1;
      }
    });
  }

  /**
   * 从月视图或周视图点击某个日期后，切换到该日期的日视图。
   *
   * 动画设计：先将日视图设置为缩小状态（scale=0.6）再切换到日视图，
   * 然后用 animateTo 放大到正常大小，模拟"从那天放大展开"的效果。
   * Curve.FastOutSlowIn 让动画启动快、收尾慢，更自然。
   */
  private goToDayView(dateStr: string): void {
    if (!dateStr) {
      return;
    }
    this.selectedDateStr = dateStr;
    this.selectedDateDisplay = this.formatDateDisplay(dateStr);

    // 先以缩小状态切换到日视图
    this.dayViewScale = 0.6;
    this.viewMode = 'day';

    // 然后用动画放大到正常尺寸
    animateTo({ duration: 350, curve: Curve.FastOutSlowIn }, () => {
      this.dayViewScale = 1;
    });
  }

  // ==================== 月份导航 ====================

  /** 切换到上一个月 */
  goToPrevMonth(): void {
    if (this.currentMonth === 0) {
      this.currentMonth = 11;
      this.currentYear -= 1;
    } else {
      this.currentMonth -= 1;
    }
    // 同步 selectedDateStr 到上个月（取 1 号，确保在当月中）
    this.selectedDateStr = this.formatDateStr(this.currentYear, this.currentMonth, 1);
    this.selectedDateDisplay = this.formatDateDisplay(this.selectedDateStr);
    this.refreshEventsDateSet();
    this.buildCalendar();
  }

  /** 切换到下一个月 */
  goToNextMonth(): void {
    if (this.currentMonth === 11) {
      this.currentMonth = 0;
      this.currentYear += 1;
    } else {
      this.currentMonth += 1;
    }
    this.selectedDateStr = this.formatDateStr(this.currentYear, this.currentMonth, 1);
    this.selectedDateDisplay = this.formatDateDisplay(this.selectedDateStr);
    this.refreshEventsDateSet();
    this.buildCalendar();
  }

  /** 跳转到今天所在的月份 */
  goToToday(): void {
    const today: Date = new Date();
    this.currentYear = today.getFullYear();
    this.currentMonth = today.getMonth();
    this.selectedDateStr = this.formatDateStr(
      today.getFullYear(), today.getMonth(), today.getDate()
    );
    this.selectedDateDisplay = this.formatDateDisplay(this.selectedDateStr);
    this.currentWeekStart = CalendarTab.getMondayOf(today);
    this.refreshEventsDateSet();
    this.buildCalendar();
    this.buildWeekData();
  }

  // ==================== 周视图导航（Week 4 新增） ====================

  /** 切换到上一周 */
  goToPrevWeek(): void {
    const newStart: Date = new Date(this.currentWeekStart);
    newStart.setDate(newStart.getDate() - 7);
    this.currentWeekStart = newStart;
    // 同步 selectedDateStr 到上周的周一
    this.selectedDateStr = this.formatDateStr(
      newStart.getFullYear(), newStart.getMonth(), newStart.getDate()
    );
    this.selectedDateDisplay = this.formatDateDisplay(this.selectedDateStr);
    this.buildWeekData();
  }

  /** 切换到下一周 */
  goToNextWeek(): void {
    const newStart: Date = new Date(this.currentWeekStart);
    newStart.setDate(newStart.getDate() + 7);
    this.currentWeekStart = newStart;
    this.selectedDateStr = this.formatDateStr(
      newStart.getFullYear(), newStart.getMonth(), newStart.getDate()
    );
    this.selectedDateDisplay = this.formatDateDisplay(this.selectedDateStr);
    this.buildWeekData();
  }

  // ==================== 日视图导航（Week 4 新增） ====================

  /** 切换到前一天 */
  goToPrevDay(): void {
    const parts: string[] = this.selectedDateStr.split('-');
    if (parts.length !== 3) {
      return;
    }
    const d: Date = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
    d.setDate(d.getDate() - 1);
    this.selectedDateStr = this.formatDateStr(
      d.getFullYear(), d.getMonth(), d.getDate()
    );
    this.selectedDateDisplay = this.formatDateDisplay(this.selectedDateStr);
  }

  /** 切换到后一天 */
  goToNextDay(): void {
    const parts: string[] = this.selectedDateStr.split('-');
    if (parts.length !== 3) {
      return;
    }
    const d: Date = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
    d.setDate(d.getDate() + 1);
    this.selectedDateStr = this.formatDateStr(
      d.getFullYear(), d.getMonth(), d.getDate()
    );
    this.selectedDateDisplay = this.formatDateDisplay(this.selectedDateStr);
  }

  // ==================== 日程标记 ====================

  /**
   * 检查某个日期是否有日程安排。
   * 使用预计算的 Set 实现 O(1) 查找。
   */
  hasEventsOnDate(dateStr: string): boolean {
    if (!dateStr) {
      return false;
    }
    return this.eventsDateSet.has(dateStr);
  }

  /**
   * 获取某日期的所有日程（用于显示标记颜色）。
   * 仅在 hasEventsOnDate 返回 true 时调用，所以此处遍历开销可控。
   */
  getEventsForDate(dateStr: string): ScheduledEvent[] {
    if (!dateStr) {
      return [];
    }
    return this.schedules.filter((e: ScheduledEvent) => e.date === dateStr);
  }

  /** 日程在当天时间轴上的开始分钟。 */
  private eventStartMinutes(evt: ScheduledEvent): number {
    return evt.startHour * 60 + evt.startMinute;
  }

  /** 日程在当天时间轴上的结束分钟，以步骤总时长为准。 */
  private eventEndMinutes(evt: ScheduledEvent): number {
    return this.eventStartMinutes(evt) + getTotalDuration(evt.steps);
  }

  /** 使用半开区间 [start, end) 判断重叠，首尾相接不算重叠。 */
  private intervalsOverlap(
    firstStart: number, firstEnd: number, secondStart: number, secondEnd: number
  ): boolean {
    return firstStart < secondEnd && secondStart < firstEnd;
  }

  /** 判断两个既有日程是否重叠。 */
  private eventsOverlap(first: ScheduledEvent, second: ScheduledEvent): boolean {
    return this.intervalsOverlap(
      this.eventStartMinutes(first), this.eventEndMinutes(first),
      this.eventStartMinutes(second), this.eventEndMinutes(second)
    );
  }

  /**
   * 校验一个候选日程能否放入目标日期。
   *
   * 每个重叠组最多容纳两个日程。候选日程若同时碰到两个既有日程，或碰到一个
   * 已经与其他日程重叠的成员，都会成为该组的第三项，因此拒绝。
   */
  private canPlaceScheduledInterval(
    dateStr: string, startMinutes: number, duration: number, excludedEventId: string = ''
  ): boolean {
    const endMinutes: number = startMinutes + Math.max(1, duration);
    const events: ScheduledEvent[] = this.getEventsForDate(dateStr).filter(
      (evt: ScheduledEvent) => evt.id !== excludedEventId
    );
    const directlyOverlapping: ScheduledEvent[] = [];

    for (const evt of events) {
      if (this.intervalsOverlap(
        startMinutes, endMinutes, this.eventStartMinutes(evt), this.eventEndMinutes(evt)
      )) {
        directlyOverlapping.push(evt);
      }
    }

    if (directlyOverlapping.length === 0) {
      return true;
    }
    if (directlyOverlapping.length >= 2) {
      return false;
    }

    const partner: ScheduledEvent = directlyOverlapping[0];
    for (const evt of events) {
      if (evt.id !== partner.id && this.eventsOverlap(partner, evt)) {
        return false;
      }
    }
    return true;
  }

  /** 周视图把互相重叠的两个日程整理成一个显示单元。 */
  private getWeekEventGroups(dateStr: string): WeekEventGroup[] {
    const sorted: ScheduledEvent[] = [...this.getEventsForDate(dateStr)];
    sorted.sort((first: ScheduledEvent, second: ScheduledEvent): number => {
      const startDiff: number = this.eventStartMinutes(first) - this.eventStartMinutes(second);
      if (startDiff !== 0) {
        return startDiff;
      }
      return this.eventEndMinutes(second) - this.eventEndMinutes(first);
    });

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
        if (!usedIds.has(candidate.id) && this.eventsOverlap(first, candidate)) {
          second = candidate;
          break;
        }
      }

      usedIds.add(first.id);
      if (second === undefined) {
        groups.push({
          key: first.id,
          first: first,
          backgroundEvent: first,
          startMinutes: this.eventStartMinutes(first),
          endMinutes: this.eventEndMinutes(first)
        });
        continue;
      }

      usedIds.add(second.id);
      const firstDuration: number = getTotalDuration(first.steps);
      const secondDuration: number = getTotalDuration(second.steps);
      groups.push({
        key: `${first.id}-${second.id}`,
        first: first,
        second: second,
        backgroundEvent: firstDuration >= secondDuration ? first : second,
        startMinutes: Math.min(this.eventStartMinutes(first), this.eventStartMinutes(second)),
        endMinutes: Math.max(this.eventEndMinutes(first), this.eventEndMinutes(second))
      });
    }
    return groups;
  }

  /** 日视图为重叠日程分配左右两列，未重叠日程继续占满可用宽度。 */
  private getDayEventLayouts(dateStr: string): DayEventLayout[] {
    const sorted: ScheduledEvent[] = [...this.getEventsForDate(dateStr)];
    sorted.sort((first: ScheduledEvent, second: ScheduledEvent): number => {
      const startDiff: number = this.eventStartMinutes(first) - this.eventStartMinutes(second);
      if (startDiff !== 0) {
        return startDiff;
      }
      return this.eventEndMinutes(second) - this.eventEndMinutes(first);
    });

    const columnEnds: number[] = [-1, -1];
    const result: DayEventLayout[] = [];
    for (let index: number = 0; index < sorted.length; index++) {
      const evt: ScheduledEvent = sorted[index];
      const startMinutes: number = this.eventStartMinutes(evt);
      let isOverlapping: boolean = false;
      for (let otherIndex: number = 0; otherIndex < sorted.length; otherIndex++) {
        if (otherIndex !== index && this.eventsOverlap(evt, sorted[otherIndex])) {
          isOverlapping = true;
          break;
        }
      }

      let column: number = 0;
      if (isOverlapping && startMinutes < columnEnds[0]) {
        column = 1;
      }
      columnEnds[column] = this.eventEndMinutes(evt);
      result.push({ event: evt, column: column, isOverlapping: isOverlapping });
    }
    return result;
  }

  // ==================== 拖拽处理 ====================

  /**
   * 拖拽开始时调用（由左侧卡片触发）
   * 记录被拖拽任务包信息，初始化预览所需数据。
   */
  handleDragStart(pkg: TaskPackage): void {
    this.activeDragPkgId = pkg.id;
    this.dropHighlightDate = '__dragging__';
    // 记录任务包总时长和名称，供预览和吸附计算使用
    this.dragPkgTotalMin = getTotalDuration(pkg.steps);
    this.dragPreviewPkgName = pkg.name;
    this.dragPreviewColor = pkg.color;
    this.dragPreviewVisible = false;
    this.dragPreviewHasTime = false;
    this.dragPreviewDate = '';
  }

  /**
   * 点击左侧面板任务包卡片时调用：弹出详情弹窗。
   * 与 TaskPackageTab 中的 showPackageDetail 逻辑完全一致。
   */
  showPackageDetail(pkg: TaskPackage): void {
    const dialogController: CustomDialogController = new CustomDialogController({
      builder: PackageDetailDialog({
        package: pkg,
        onClose: () => {
          dialogController.close();
        },
        onEdit: (pkgId: string) => {
          router.pushUrl({
            url: 'pages/CreatePackage',
            params: { packageId: pkgId }
          });
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      cornerRadius: 16,
    });
    dialogController.open();
  }

  /**
   * 点击日历视图中的事件块（已安排的日程）时调用：弹出任务包详情。
   * 通过 event.packageId 反查 TaskPackage；找不到时忽略（级联删除已保证正常情况下不会发生）。
   */
  showPackageDetailByEvent(evt: ScheduledEvent): void {
    const dialogController: CustomDialogController = new CustomDialogController({
      builder: ScheduledEventDetailDialog({
        event: evt,
        onClose: () => { dialogController.close(); }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true,
      cornerRadius: 16
    });
    dialogController.open();
  }

  /** 拖拽进入某个日期格子时调用 */
  handleDragEnter(dateStr: string): void {
    if (dateStr) {
      this.dropHighlightDate = dateStr;
    }
  }

  /** 拖拽离开某个日期格子时调用 */
  handleDragLeave(dateStr: string): void {
    if (this.dropHighlightDate === dateStr) {
      this.dropHighlightDate = '';
    }
  }

  /**
   * 拖拽放下时调用 —— 核心排程逻辑。
   *
   * 月视图调用时不传 startHour/startMinute（使用当前时间自动吸附）。
   * 周/日视图调用时传入吸附后的时间。
   *
   * @param dateStr  目标日期字符串
   * @param pkgId    被拖拽的任务包 ID
   * @param startHour   开始小时 (0-23)，可选
   * @param startMinute 开始分钟 (0/30)，可选
   */
  handleDrop(dateStr: string, pkgId: string, startHour?: number, startMinute?: number): void {
    // 清除高亮与预览
    this.dropHighlightDate = '';
    this.dragPreviewVisible = false;

    if (!dateStr || !pkgId) {
      return;
    }

    // 查找任务包
    const pkg: TaskPackage | undefined = taskStore.getPackageById(pkgId);
    if (!pkg) {
      promptAction.showToast({ message: '任务包不存在', duration: 2000 });
      return;
    }

    // 防止同一任务包在同一天重复安排
    if (scheduleStore.isPackageScheduledOnDate(pkgId, dateStr)) {
      promptAction.showToast({
        message: `"${pkg.name}" 已安排在此日期`,
        duration: 2000
      });
      return;
    }

    // ---- 计算开始时间 ----
    let sHour: number;
    let sMin: number;
    if (startHour !== undefined && startMinute !== undefined) {
      // 周/日视图：使用吸附后的时间
      sHour = startHour;
      sMin = startMinute;
    } else {
      // 月视图：默认安排到当前时间 1 分钟后，方便快速验证应用内提醒。
      const now: Date = new Date();
      const defaultStartMinutes: number =
        (now.getHours() * 60 + now.getMinutes() + 1) % (24 * 60);
      sHour = Math.floor(defaultStartMinutes / 60);
      sMin = defaultStartMinutes % 60;
    }

    // ---- 计算结束时间（开始时间 + 任务包总时长） ----
    const totalMin: number = getTotalDuration(pkg.steps);
    const startTotalMin: number = sHour * 60 + sMin;
    if (!this.canPlaceScheduledInterval(dateStr, startTotalMin, totalMin)) {
      promptAction.showToast({
        message: '该时段已有两个任务包，不能继续安排',
        duration: 2000
      });
      return;
    }
    const endTotalMin: number = startTotalMin + totalMin;
    const eHour: number = Math.floor(endTotalMin / 60) % 24;
    const eMin: number = endTotalMin % 60;

    // ---- 创建日程安排 ----
    const newEvent: ScheduledEvent = {
      id: generateId(),
      date: dateStr,
      packageId: pkg.id,
      packageName: pkg.name,
      color: pkg.color,
      startHour: sHour,
      startMinute: sMin,
      endHour: eHour,
      endMinute: eMin,
      steps: pkg.steps.map((s: TaskStep): TaskStep => ({ name: s.name, duration: s.duration })),
      reminderEnabled: true
    };

    scheduleStore.addEvent(newEvent);

    // 刷新本地数据与日期集合
    this.schedules = [...scheduleStore.events];
    this.refreshEventsDateSet();
    this.buildCalendar();

    // ---- 选中该日期并显示给用户 ----
    this.selectedDateStr = dateStr;
    this.selectedDateDisplay = this.formatDateDisplay(dateStr);

    const timeLabel: string = `${sHour.toString().padStart(2, '0')}:${sMin.toString().padStart(2, '0')}`;
    promptAction.showToast({
      message: `已安排"${pkg.name}"到 ${this.selectedDateDisplay} ${timeLabel}`,
      duration: 2000
    });
  }

  /**
   * 处理拖拽放下（日历格子 onDrop 回调入口）。
   *
   * 优先通过系统拖拽数据通道（event.getData）提取 packageId，
   * 后备方案使用 @State activeDragPkgId。
   */
  handleDropByEvent(dateStr: string, event: DragEvent): void {
    if (!dateStr) {
      return;
    }

    // 使用 @State 中记录的 activeDragPkgId
    let pkgId: string = this.activeDragPkgId;

    if (pkgId) {
      this.handleDrop(dateStr, pkgId);
      this.activeDragPkgId = '';
    }
  }

  // ==================== 周/日视图拖拽 + 吸附 + 预览 ====================

  /**
   * 根据手指 Y 坐标和滚动偏移量，计算对应时间并吸附到最近的半小时。
   *
   * @param y            事件相对于目标组件的 Y 坐标
   * @param scrollOffset 当前 Scroll 的垂直滚动偏移量
   * @param hourHeight   每小时对应的高度（vp），周视图 42 / 日视图 60
   * @returns {hour, minute} 吸附后的时间
   */
  private snapTimeFromY(y: number, scrollOffset: number, hourHeight: number): TimeResult {
    // 网格线和事件块统一下移 GRID_LINE_OFFSET，换算时间时扣回该绘制偏移。
    const effectiveY: number = y + scrollOffset - GRID_LINE_OFFSET;
    if (effectiveY < 0) {
      return { hour: 0, minute: 0 };
    }
    // 转换为小时浮点数
    const hourFloat: number = effectiveY / hourHeight;
    if (hourFloat >= 24) {
      return { hour: 23, minute: 30 };
    }
    // 吸附到最近的半小时
    const totalMinutes: number = hourFloat * 60;
    const snappedMinutes: number = Math.round(totalMinutes / 30) * 30;
    let hour: number = Math.floor(snappedMinutes / 60);
    const minute: number = snappedMinutes % 60;
    if (hour >= 24) {
      hour = 23;
    }
    if (hour < 0) {
      hour = 0;
    }
    return { hour: hour, minute: minute };
  }

  /** 把 DragEvent 的窗口坐标换算为时间轴可视区域内坐标。 */
  private dragLocalY(event: DragEvent, timelineWindowY: number): number {
    return event.getWindowY() - timelineWindowY;
  }

  /**
   * 周/日视图中拖拽移动时的回调。
   * 实时计算吸附时间并更新预览条。
   *
   * @param event        DragEvent
   * @param dateStr      目标日期字符串
   * @param hourHeight   每小时高度（vp）
   * @param scrollOffset 当前滚动偏移量
   */
  private handleDragMoveInTimeAxis(
    event: DragEvent, dateStr: string, hourHeight: number,
    scrollOffset: number, timelineWindowY: number
  ): void {
    if (!dateStr || !this.activeDragPkgId) {
      return;
    }
    const y: number = this.dragLocalY(event, timelineWindowY);
    const snapped: TimeResult =
      this.snapTimeFromY(y, scrollOffset, hourHeight);

    // 计算结束时间
    const endTotalMin: number = snapped.hour * 60 + snapped.minute + this.dragPkgTotalMin;
    const endHour: number = Math.floor(endTotalMin / 60) % 24;
    const endMin: number = endTotalMin % 60;

    // 更新预览状态
    this.dragPreviewVisible = true;
    this.dragPreviewHasTime = true;
    this.dragPreviewDate = dateStr;
    this.dragPreviewHour = snapped.hour;
    this.dragPreviewMinute = snapped.minute;
    this.dragPreviewEndHour = endHour;
    this.dragPreviewEndMinute = endMin;
  }

  /**
   * 处理周/日视图中的拖拽放下（带时间吸附）。
   * 由内容区的 onDrop 回调调用。
   */
  private handleDropInTimeAxis(
    event: DragEvent, dateStr: string, hourHeight: number,
    scrollOffset: number, timelineWindowY: number
  ): void {
    if (!dateStr) {
      return;
    }
    const pkgId: string = this.activeDragPkgId;
    if (!pkgId) {
      return;
    }

    const y: number = this.dragLocalY(event, timelineWindowY);
    const snapped: TimeResult =
      this.snapTimeFromY(y, scrollOffset, hourHeight);

    this.handleDrop(dateStr, pkgId, snapped.hour, snapped.minute);
    this.activeDragPkgId = '';
  }

  /** 拖拽占位框顶部与事件块使用完全相同的时间到像素换算。 */
  private dragPreviewTop(hourHeight: number, startHour: number): number {
    const startMinutes: number = this.dragPreviewHour * 60 + this.dragPreviewMinute;
    return (startMinutes - startHour * 60) / 60 * hourHeight + GRID_LINE_OFFSET;
  }

  /** 拖拽占位框高度按任务包总时长计算，并保留最低可见高度。 */
  private dragPreviewHeight(hourHeight: number): number {
    return Math.max(this.dragPkgTotalMin / 60 * hourHeight, 18);
  }

  // ==================== 周/日视图双指缩放 ====================

  /** 开始捏合时记录中心点对应的时间，后续缩放始终围绕该时间点进行。 */
  private beginTimelinePinch(view: string, event: GestureEvent): void {
    const hourHeight: number = view === 'week' ? this.weekHourHeight : this.dayHourHeight;
    const scroller: Scroller = view === 'week' ? this.weekScroller : this.dayScroller;
    this.pinchStartHourHeight = hourHeight;
    this.pinchStartScrollOffset = scroller.currentOffset().yOffset;
    this.pinchAnchorMinutes =
      (this.pinchStartScrollOffset + event.pinchCenterY - GRID_LINE_OFFSET) / hourHeight * 60;
  }

  /** 按 PinchGesture 的累计 scale 更新小时高度，并保持捏合中心对应时间不跳动。 */
  private updateTimelinePinch(view: string, event: GestureEvent): void {
    const scaled: number = this.pinchStartHourHeight * event.scale;
    const nextHeight: number = Math.max(MIN_HOUR_HEIGHT, Math.min(MAX_HOUR_HEIGHT, scaled));
    if (view === 'week') {
      this.weekHourHeight = nextHeight;
    } else {
      this.dayHourHeight = nextHeight;
    }
    const nextOffset: number =
      this.pinchAnchorMinutes / 60 * nextHeight + GRID_LINE_OFFSET - event.pinchCenterY;
    this.scheduleTimelinePinchOffset(view, Math.max(0, nextOffset));
  }

  /** 状态布局在下一轮生效后再校正滚动位置，避免按旧内容高度计算而产生漂移。 */
  private scheduleTimelinePinchOffset(view: string, nextOffset: number): void {
    if (view === 'week') {
      this.weekPendingPinchOffset = nextOffset;
      this.weekScroller.scrollTo({ xOffset: 0, yOffset: nextOffset, animation: false });
      if (this.weekPinchScrollTimer !== -1) {
        return;
      }
      this.weekPinchScrollTimer = setTimeout(() => {
        this.weekScroller.scrollTo({
          xOffset: 0,
          yOffset: this.weekPendingPinchOffset,
          animation: false
        });
        this.weekPinchScrollTimer = -1;
      }, 0);
      return;
    }
    this.dayPendingPinchOffset = nextOffset;
    this.dayScroller.scrollTo({ xOffset: 0, yOffset: nextOffset, animation: false });
    if (this.dayPinchScrollTimer !== -1) {
      return;
    }
    this.dayPinchScrollTimer = setTimeout(() => {
      this.dayScroller.scrollTo({
        xOffset: 0,
        yOffset: this.dayPendingPinchOffset,
        animation: false
      });
      this.dayPinchScrollTimer = -1;
    }, 0);
  }

  // ==================== 日程长按菜单与复制/剪切/分享 ====================

  /** 创建日程深拷贝，避免修改日程副本时污染任务包模板或原日程。 */
  private cloneScheduledEvent(evt: ScheduledEvent): ScheduledEvent {
    return {
      id: evt.id,
      date: evt.date,
      packageId: evt.packageId,
      packageName: evt.packageName,
      color: evt.color,
      startHour: evt.startHour,
      startMinute: evt.startMinute,
      endHour: evt.endHour,
      endMinute: evt.endMinute,
      reminderEnabled: evt.reminderEnabled,
      steps: evt.steps.map((step: TaskStep): TaskStep => ({
        name: step.name,
        duration: step.duration
      }))
    };
  }

  /** 进入复制或剪切待粘贴状态。 */
  private prepareEventTransfer(evt: ScheduledEvent, mode: string): void {
    this.contextMenuEventId = '';
    this.pendingTransferEvent = this.cloneScheduledEvent(evt);
    this.transferEventName = evt.packageName;
    this.transferMode = mode;
    this.getUIContext().getContextMenuController().close();
    promptAction.showToast({
      message: `已${mode === 'copy' ? '复制' : '剪切'}“${evt.packageName}”，请点击目标时间`,
      duration: 2000
    });
  }

  /** 取消当前复制/剪切。 */
  private cancelEventTransfer(): void {
    this.pendingTransferEvent = null;
    this.transferMode = '';
    this.transferEventName = '';
  }

  /** 将待处理日程粘贴到指定日期和时间；复制生成新 ID，剪切保留原 ID。 */
  private pasteTransferredEvent(dateStr: string, y: number, hourHeight: number): void {
    if (this.pendingTransferEvent === null || this.transferMode === '') {
      return;
    }
    const targetTime: TimeResult = this.snapTimeFromY(y, 0, hourHeight);
    const pasted: ScheduledEvent = this.cloneScheduledEvent(this.pendingTransferEvent);
    const totalMinutes: number = getTotalDuration(pasted.steps);
    const startTotalMinutes: number = targetTime.hour * 60 + targetTime.minute;
    const excludedEventId: string = this.transferMode === 'cut' ? pasted.id : '';
    if (!this.canPlaceScheduledInterval(
      dateStr, startTotalMinutes, totalMinutes, excludedEventId
    )) {
      promptAction.showToast({
        message: '该时段已有两个任务包，不能继续安排',
        duration: 2000
      });
      return;
    }
    const endTotalMinutes: number = startTotalMinutes + totalMinutes;
    pasted.date = dateStr;
    pasted.startHour = targetTime.hour;
    pasted.startMinute = targetTime.minute;
    pasted.endHour = Math.floor(endTotalMinutes / 60) % 24;
    pasted.endMinute = endTotalMinutes % 60;

    const actionLabel: string = this.transferMode === 'copy' ? '复制' : '移动';
    if (this.transferMode === 'copy') {
      pasted.id = generateId();
      scheduleStore.addEvent(pasted);
    } else {
      scheduleStore.updateEvent(pasted);
    }
    this.cancelEventTransfer();
    this.loadData();
    promptAction.showToast({ message: `已${actionLabel}到目标时间`, duration: 1800 });
  }

  /** 将日程整理为纯文本并拉起 HarmonyOS 系统分享面板。 */
  private shareScheduledEvent(evt: ScheduledEvent): void {
    this.contextMenuEventId = '';
    this.getUIContext().getContextMenuController().close();
    const start: string =
      `${evt.startHour.toString().padStart(2, '0')}:${evt.startMinute.toString().padStart(2, '0')}`;
    const end: string =
      `${evt.endHour.toString().padStart(2, '0')}:${evt.endMinute.toString().padStart(2, '0')}`;
    const steps: string = evt.steps
      .map((step: TaskStep) => `${step.name}（${step.duration}分钟）`)
      .join('、');
    const sharedData: systemShare.SharedData = new systemShare.SharedData({
      utd: utd.UniformDataType.PLAIN_TEXT,
      title: evt.packageName,
      content: `${evt.packageName}\n${evt.date} ${start}-${end}\n${steps}`
    });
    const controller: systemShare.ShareController = new systemShare.ShareController(sharedData);
    const context: common.UIAbilityContext =
      this.getUIContext().getHostContext() as common.UIAbilityContext;
    controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    }).catch((error: BusinessError) => {
      promptAction.showToast({ message: `分享失败：${error.message}`, duration: 2000 });
    });
  }

  /** 从长按菜单进入拉伸模式；具体上下边界拖动由事件块手柄处理。 */
  private enterStretchMode(evt: ScheduledEvent): void {
    this.contextMenuEventId = '';
    this.stretchEventId = evt.id;
    this.stretchPreviewStartMinutes = evt.startHour * 60 + evt.startMinute;
    this.stretchPreviewDuration = getTotalDuration(evt.steps);
    this.stretchPreviewSteps = evt.steps.map((step: TaskStep): TaskStep => ({
      name: step.name,
      duration: step.duration
    }));
    this.getUIContext().getContextMenuController().close();
    promptAction.showToast({ message: '已进入拉伸模式，请拖动事件块上下边界', duration: 2000 });
  }

  // ==================== 日程拉伸 ====================

  /** 拉伸手势开始：保存不随 onActionUpdate 变化的原始快照。 */
  private beginEventStretch(evt: ScheduledEvent): void {
    this.stretchOriginalEvent = this.cloneScheduledEvent(evt);
    this.stretchPreviewStartMinutes = evt.startHour * 60 + evt.startMinute;
    this.stretchPreviewDuration = getTotalDuration(evt.steps);
    this.stretchPreviewSteps = evt.steps.map((step: TaskStep): TaskStep => ({
      name: step.name,
      duration: step.duration
    }));
  }

  /**
   * 拖动上/下边界更新预览，时间以 5 分钟吸附。
   * 上边界保持原结束时间不变；下边界保持原开始时间不变。
   */
  private updateEventStretch(edge: string, event: GestureEvent, hourHeight: number): void {
    if (this.stretchOriginalEvent === null) {
      return;
    }
    const original: ScheduledEvent = this.stretchOriginalEvent;
    const originalStart: number = original.startHour * 60 + original.startMinute;
    const originalDuration: number = getTotalDuration(original.steps);
    const originalEnd: number = originalStart + originalDuration;
    const minimumDuration: number = Math.max(5, Math.ceil(original.steps.length / 5) * 5);
    const deltaMinutes: number = Math.round((event.offsetY / hourHeight * 60) / 5) * 5;

    let nextStart: number = originalStart;
    let nextDuration: number = originalDuration;
    if (edge === 'top') {
      const latestStart: number = Math.min(1439, originalEnd - minimumDuration);
      nextStart = Math.max(0, Math.min(latestStart, originalStart + deltaMinutes));
      nextDuration = originalEnd - nextStart;
    } else {
      const maximumDuration: number = Math.max(originalDuration, 1440 - originalStart);
      nextDuration = Math.max(
        minimumDuration,
        Math.min(maximumDuration, originalDuration + deltaMinutes)
      );
    }

    this.stretchPreviewStartMinutes = nextStart;
    this.stretchPreviewDuration = nextDuration;
    this.stretchPreviewSteps = this.scaleStepsToDuration(original.steps, nextDuration);
  }

  /** 拉伸结束：把预览一次性写入 ScheduleStore 并持久化。 */
  private finishEventStretch(): void {
    if (this.stretchOriginalEvent === null) {
      return;
    }
    const updated: ScheduledEvent = this.cloneScheduledEvent(this.stretchOriginalEvent);
    updated.startHour = Math.floor(this.stretchPreviewStartMinutes / 60);
    updated.startMinute = this.stretchPreviewStartMinutes % 60;
    updated.steps = this.stretchPreviewSteps.map((step: TaskStep): TaskStep => ({
      name: step.name,
      duration: step.duration
    }));
    const endTotalMinutes: number = this.stretchPreviewStartMinutes + this.stretchPreviewDuration;
    updated.endHour = Math.floor(endTotalMinutes / 60) % 24;
    updated.endMinute = endTotalMinutes % 60;
    if (!this.canPlaceScheduledInterval(
      updated.date,
      this.stretchPreviewStartMinutes,
      this.stretchPreviewDuration,
      updated.id
    )) {
      this.stretchOriginalEvent = null;
      this.stretchEventId = '';
      this.loadData();
      promptAction.showToast({
        message: '该时段已有两个任务包，无法拉伸到此处',
        duration: 2000
      });
      return;
    }
    scheduleStore.updateEvent(updated);
    this.stretchOriginalEvent = null;
    this.stretchEventId = '';
    this.loadData();
    promptAction.showToast({ message: '日程时长已更新', duration: 1600 });
  }

  /** 手势取消时恢复进入拉伸模式时的预览，不写入持久化。 */
  private cancelEventStretch(): void {
    if (this.stretchOriginalEvent !== null) {
      const original: ScheduledEvent = this.stretchOriginalEvent;
      this.stretchPreviewStartMinutes = original.startHour * 60 + original.startMinute;
      this.stretchPreviewDuration = getTotalDuration(original.steps);
      this.stretchPreviewSteps = original.steps.map((step: TaskStep): TaskStep => ({
        name: step.name,
        duration: step.duration
      }));
    }
    this.stretchOriginalEvent = null;
  }

  /** 等比缩放步骤并由最后一步补齐舍入差额，保证总和严格等于目标时长。 */
  private scaleStepsToDuration(steps: TaskStep[], targetDuration: number): TaskStep[] {
    if (steps.length === 0) {
      return [];
    }
    const originalTotal: number = Math.max(1, getTotalDuration(steps));
    const result: TaskStep[] = [];
    let assigned: number = 0;
    for (let index: number = 0; index < steps.length - 1; index++) {
      const remainingSteps: number = steps.length - index - 1;
      const proportional: number = Math.max(
        1,
        Math.round(steps[index].duration * targetDuration / originalTotal)
      );
      const available: number = targetDuration - assigned - remainingSteps;
      const duration: number = Math.min(proportional, available);
      result.push({ name: steps[index].name, duration: duration });
      assigned += duration;
    }
    result.push({
      name: steps[steps.length - 1].name,
      duration: targetDuration - assigned
    });
    return result;
  }

  /** 拉伸预览期间使用预览步骤；其他事件仍读取自身步骤。 */
  private displayEventSteps(evt: ScheduledEvent): TaskStep[] {
    if (this.stretchEventId === evt.id && this.stretchPreviewSteps.length > 0) {
      return this.stretchPreviewSteps;
    }
    return evt.steps;
  }

  /** 拉伸预览期间显示新的开始时间。 */
  private displayEventStartLabel(evt: ScheduledEvent): string {
    const totalMinutes: number = this.stretchEventId === evt.id ?
      this.stretchPreviewStartMinutes : evt.startHour * 60 + evt.startMinute;
    return `${Math.floor(totalMinutes / 60).toString().padStart(2, '0')}:` +
      `${(totalMinutes % 60).toString().padStart(2, '0')}`;
  }

  // ==================== 左侧面板折叠控制 ====================

  /**
   * 切换左侧任务包面板的展开/折叠状态，带宽度过渡动画。
   */
  toggleLeftPanel(): void {
    animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.isLeftPanelExpanded = !this.isLeftPanelExpanded;
    });
  }

  // ==================== UI 构建入口 ====================

  build() {
    /**
     * 所有视图共用相同的左右双栏布局。
     * 左侧：任务包列表（拖拽源），右侧：日历内容区。
     * 通过 viewMode 切换右侧内容。
     */
    Row() {
      // ========== 左侧面板（30%）：任务包拖拽源 ==========
      this.buildLeftPanel()

      // ---- 分割线 ----
      Divider()
        .vertical(true)
        .height('100%')
        .strokeWidth(1)
        .color('#E0E0E0')

      // ========== 右侧面板：日历内容区（宽度随左侧面板折叠状态动态调整） ==========
      Column() {
        // 根据视图模式渲染不同的内容
        if (this.viewMode === 'month') {
          this.buildMonthContent()
        } else if (this.viewMode === 'week') {
          this.buildWeekContent()
        } else {
          this.buildDayContent()
        }
        // 拖拽预览条（周/日视图底部）
        this.buildDragPreviewBar()
      }
      .width(this.isLeftPanelExpanded ? '70%' : '90%')
      .height('100%')
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 左侧面板（折叠/展开双态） ====================

  /**
   * 构建左侧任务包面板，支持折叠（10%）/ 展开（30%）双态。
   *
   * - 折叠态：灰色窄条，显示竖排提示文字，点击展开。
   * - 展开态：完整任务包卡片列表，顶部有"←"按钮收起。
   * - 宽度过渡由 animateTo + @State isLeftPanelExpanded 驱动。
   */
  @Builder
  buildLeftPanel(): void {
    Column() {
      if (this.isLeftPanelExpanded) {
        // ==================== 展开态：完整任务包面板 ====================
        // 点击面板空白区域即可收起（保留右上角 → 按钮的收起功能）
        Column() {
        // 标题栏（含收起按钮）
        Row() {
          Text('任务包')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#666666')
            .layoutWeight(1)

          // 收起按钮
          Button('→')
            .fontSize(16)
            .fontColor('#999999')
            .backgroundColor('#00000000')
            .width(28)
            .height(28)
            .borderRadius(14)
            .padding(0)
            .onClick(() => { this.toggleLeftPanel(); })
        }
        .width('100%')
        .padding({ left: 8, right: 4, top: 12, bottom: 8 })

        // 可滚动的任务包卡片列表
        Scroll() {
          Column({ space: 8 }) {
            if (this.packages.length === 0) {
              Text('暂无任务包\n请先在任务包\n页面创建')
                .fontSize(12)
                .fontColor('#999999')
                .textAlign(TextAlign.Center)
                .padding(16)
            }

            ForEach(this.packages,
              (pkg: TaskPackage) => {
                // ===== 拖拽源卡片 =====
                Column() {
                  Text(pkg.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                    .width('100%')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  if (pkg.steps.length > 0) {
                    Text(
                      pkg.steps
                        .map((s: TaskStep) => `${s.name} ${s.duration}min`)
                        .join(' · ')
                    )
                      .fontSize(10)
                      .fontColor('#FFFFFF')
                      .opacity(0.85)
                      .width('100%')
                      .maxLines(4)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .padding({ top: 4 })
                  }

                  Text('长按拖拽 →')
                    .fontSize(9)
                    .fontColor('#FFFFFF')
                    .opacity(0.6)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                    .padding({ top: 6 })
                }
                .width('calc(100% - 8px)')
                .padding(10)
                .borderRadius(8)
                .backgroundColor(pkg.color)
                .margin({ left: 4, right: 4 })
                .shadow({
                  radius: 2,
                  color: '#20000000',
                  offsetX: 0,
                  offsetY: 1
                })
                .draggable(true)
                .onDragStart((event: DragEvent) => {
                  this.handleDragStart(pkg);
                })
                /**
                 * 点击卡片弹出详情弹窗（与 Tab1 行为一致）。
                 * 短按 = 弹窗，长按 = 拖拽，两者互不冲突。
                 * 卡片上有 onClick 后，事件不会冒泡到父级面板的 onClick，
                 * 因此点击卡片不会收起左侧面板。
                 */
                .onClick(() => {
                  this.showPackageDetail(pkg);
                })
              },
              (pkg: TaskPackage) => `${pkg.id}-v${pkg._version}`
            )
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor('#FAFAFA')
        }
        /**
         * 点击面板内空白区域收起面板。
         * 任务包卡片自身有 onClick（弹出详情弹窗），
         * 其点击事件不会冒泡至此，因此点击卡片不会触发收起。
         */
        .onClick(() => { this.toggleLeftPanel(); })
      } else {
        // ==================== 折叠态：灰色窄条 ====================
        Column() {
          // 提示图标
          Text('⇤')
            .fontSize(18)
            .fontColor('#AAAAAA')
            .margin({ bottom: 6 })

          // 竖排提示文字
          Text('任')
            .fontSize(11)
            .fontColor('#AAAAAA')
          Text('务')
            .fontSize(11)
            .fontColor('#AAAAAA')
          Text('包')
            .fontSize(11)
            .fontColor('#AAAAAA')

          // 数量角标
          if (this.packages.length > 0) {
            Text(this.packages.length.toString())
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#007AFF')
              .margin({ top: 4 })
              .width(20)
              .height(20)
              .borderRadius(10)
              .backgroundColor('#EBF5FF')
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#E8E8E8')
        .onClick(() => { this.toggleLeftPanel(); })
      }
    }
    .width(this.isLeftPanelExpanded ? '30%' : '10%')
    .height('100%')
    .backgroundColor(this.isLeftPanelExpanded ? '#F5F5F5' : '#E0E0E0')
    .borderRadius(0)
  }

  // ==================== 视图切换按钮组（所有视图共用） ====================

  /**
   * 构建视图切换按钮组："月" | "周" | "日"
   *
   * 当前激活的按钮使用主题色填充（#007AFF），其他使用灰色描边。
   * 三个按钮紧凑排列，整体为一个圆角矩形容器。
   */
  @Builder
  buildViewSwitcher(): void {
    Row({ space: 0 }) {
      // ----「月」按钮 ----
      Text('月')
        .fontSize(12)
        .fontWeight(this.viewMode === 'month' ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.viewMode === 'month' ? '#FFFFFF' : '#666666')
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(this.viewMode === 'month' ? '#007AFF' : '#00000000')
        .borderRadius(4)
        .onClick(() => { this.switchToView('month'); })

      // ----「周」按钮 ----
      Text('周')
        .fontSize(12)
        .fontWeight(this.viewMode === 'week' ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.viewMode === 'week' ? '#FFFFFF' : '#666666')
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(this.viewMode === 'week' ? '#007AFF' : '#00000000')
        .borderRadius(4)
        .onClick(() => { this.switchToView('week'); })

      // ----「日」按钮 ----
      Text('日')
        .fontSize(12)
        .fontWeight(this.viewMode === 'day' ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.viewMode === 'day' ? '#FFFFFF' : '#666666')
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(this.viewMode === 'day' ? '#007AFF' : '#00000000')
        .borderRadius(4)
        .onClick(() => { this.switchToView('day'); })
    }
    .borderRadius(6)
    .backgroundColor('#F0F0F0')
    .padding(2)
  }

  /** 长按事件块显示的操作菜单。 */
  @Builder
  buildEventContextMenu(evt: ScheduledEvent): void {
    Menu() {
      MenuItem({ content: '复制', labelInfo: '点击时间轴粘贴' })
        .onClick(() => { this.prepareEventTransfer(evt, 'copy'); })
      MenuItem({ content: '剪切', labelInfo: '点击时间轴移动' })
        .onClick(() => { this.prepareEventTransfer(evt, 'cut'); })
      MenuItem({ content: '分享' })
        .onClick(() => { this.shareScheduledEvent(evt); })
      MenuItem({ content: '拉伸', labelInfo: '拖动上下边界' })
        .onClick(() => { this.enterStretchMode(evt); })
    }
  }

  /** 静止长按识别成功后显示菜单；有位移的手势会先失败并交还给 Scroll。 */
  private showEventContextMenu(evt: ScheduledEvent): void {
    this.contextMenuEventId = evt.id;
  }

  /** 周视图合并卡内的一行；每个任务仍可独立点击或长按。 */
  @Builder
  buildWeekMergedEventEntry(evt: ScheduledEvent, showJoiner: boolean): void {
    Row() {
      if (showJoiner) {
        Text('和')
          .fontSize(9)
          .fontWeight(FontWeight.Normal)
          .fontColor('#FFFFFF')
          .opacity(0.85)
          .margin({ right: 2 })
      }
      Text(this.getEventDisplayTitle(evt))
        .fontSize(9)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .decoration({
          type: this.isEventCompleted(evt) ?
            TextDecorationType.LineThrough : TextDecorationType.None,
          color: '#FFFFFF'
        })
        .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 3, right: 2, top: 1, bottom: 1 })
    .opacity(this.isEventCompleted(evt) ? 0.45 : 1)
    .onClick(() => { this.showPackageDetailByEvent(evt); })
    .bindContextMenu(
      this.contextMenuEventId === evt.id,
      () => { this.buildEventContextMenu(evt); },
      {
        preview: MenuPreviewMode.NONE,
        onDisappear: () => {
          if (this.contextMenuEventId === evt.id) {
            this.contextMenuEventId = '';
          }
        }
      }
    )
    .priorityGesture(
      LongPressGesture({
        repeat: false,
        duration: 400,
        allowableMovement: 18
      })
        .onAction(() => { this.showEventContextMenu(evt); }),
      GestureMask.Normal
    )
  }

  /** 复制/剪切后的待粘贴提示。 */
  @Builder
  buildTransferBanner(): void {
    if (this.transferMode !== '') {
      Row() {
        Text(
          `${this.transferMode === 'copy' ? '复制' : '剪切'}“${this.transferEventName}”：点击目标时间完成`
        )
          .fontSize(11)
          .fontColor('#1F5F99')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('取消')
          .fontSize(11)
          .fontColor('#FF3B30')
          .padding({ left: 10, right: 4, top: 4, bottom: 4 })
          .onClick(() => { this.cancelEventTransfer(); })
      }
      .width('100%')
      .padding({ left: 10, right: 8, top: 5, bottom: 5 })
      .backgroundColor('#EAF4FF')
    }
  }

  /** 拉伸模式下覆盖在事件块上下边界的可拖动手柄。 */
  @Builder
  buildStretchHandles(evt: ScheduledEvent, hourHeight: number): void {
    if (this.stretchEventId === evt.id) {
      Row() {
        Row()
          .width(24)
          .height(3)
          .borderRadius(2)
          .backgroundColor('#FFFFFF')
      }
      .width('100%')
      .height(12)
      .justifyContent(FlexAlign.Center)
      .position({ x: 0, y: 0 })
      .gesture(
        PanGesture({ direction: PanDirection.Vertical, distance: 1 })
          .onActionStart(() => { this.beginEventStretch(evt); })
          .onActionUpdate((event: GestureEvent) => {
            this.updateEventStretch('top', event, hourHeight);
          })
          .onActionEnd(() => { this.finishEventStretch(); })
          .onActionCancel(() => { this.cancelEventStretch(); })
      )

      Row() {
        Row()
          .width(24)
          .height(3)
          .borderRadius(2)
          .backgroundColor('#FFFFFF')
      }
      .width('100%')
      .height(12)
      .justifyContent(FlexAlign.Center)
      .position({
        x: 0,
        y: Math.max(12, this.eventBlockHeight(evt, hourHeight, 24) - 12)
      })
      .gesture(
        PanGesture({ direction: PanDirection.Vertical, distance: 1 })
          .onActionStart(() => { this.beginEventStretch(evt); })
          .onActionUpdate((event: GestureEvent) => {
            this.updateEventStretch('bottom', event, hourHeight);
          })
          .onActionEnd(() => { this.finishEventStretch(); })
          .onActionCancel(() => { this.cancelEventStretch(); })
      )
    }
  }

  // ==================== 当前时间指示线 ====================

  /**
   * 在日视图 / 周视图的时间轴上叠加一条红色"现在"指示线。
   *
   * 外观：`[09:30] ●——————————`
   * - 左侧时间标签（36vp，浅灰背景，覆盖原时间文字）
   * - 红色圆点 + 红色横线（占据右侧剩余空间）
   *
   * 仅在选中日期为今天（日视图）或当前周包含今天（周视图）时显示。
   *
   * Builder 不接收 hourHeight 参数，直接读取当前视图的 @State 高度，
   * 确保捏合缩放的每次状态变化都会触发指示线位置刷新。
   */
  // 获取时间指示线偏移量（vp），返回 -1 表示不需要显示
  getTimeIndicatorOffset(hourHeight: number, startHour: number): number {
    if (this.nowHour < startHour) {
      return -1;
    }
    const minutesFromStart: number =
      (this.nowHour - startHour) * 60 + this.nowMinute + this.nowSecond / 60;
    return minutesFromStart / 60 * hourHeight;
  }

  // 获取时间指示线的时间字符串
  getTimeIndicatorStr(): string {
    return `${this.nowHour.toString().padStart(2, '0')}:${this.nowMinute.toString().padStart(2, '0')}`;
  }

  @Builder
  buildTimeIndicator(): void {
    // 使用条件渲染：当前时间早于可视范围起始时刻则不渲染
    if (this.nowHour >= (this.viewMode === 'week' ? WEEK_START_HOUR : 0)) {
      Row() {
        // 左侧 36vp：时间标签 + 红点（覆盖原时间文字）
        Row() {
          Text(this.getTimeIndicatorStr())
            .fontSize(9)
            .fontColor('#FF3B30')
            .fontWeight(FontWeight.Bold)
          Blank()
          Circle({ width: 6, height: 6 })
            .fill('#FF3B30')
        }
        .width(36)
        .height(12)
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#FAFAFA')
        // 右侧红色横线（用 Row 的 backgroundColor 画线，避免 Divider 被 height 裁切）
        Row()
          .layoutWeight(1)
          .height(1)
          .backgroundColor('#FF3B30')
      }
      .width('100%')
      .height(12)
      .alignItems(VerticalAlign.Center)
      // 指示线 y：当前时间边界 + GRID_LINE_OFFSET（对齐小时分割线），-6 使 12vp 高的标签行中心落在该位置
      .position({
        x: 0,
        y: this.getTimeIndicatorOffset(
          this.viewMode === 'week' ? this.weekHourHeight : this.dayHourHeight,
          this.viewMode === 'week' ? WEEK_START_HOUR : 0
        ) + GRID_LINE_OFFSET - 6
      })
      .hitTestBehavior(HitTestMode.Transparent)
    }
  }

  // ==================== 拖拽预览条（周/日视图共用） ====================

  /**
   * 构建时间轴内的虚线占位框。
   * 位置和高度分别对应吸附后的开始时间与任务包总时长。
   */
  @Builder
  buildTimeAxisDragPreview(dateStr: string, hourHeight: number, startHour: number): void {
    if (this.dragPreviewVisible && this.dragPreviewHasTime && this.dragPreviewDate === dateStr) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.dragPreviewColor)
          .opacity(0.12)

        Text(this.dragPreviewPkgName)
          .fontSize(9)
          .fontColor(this.dragPreviewColor)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 3, right: 3, top: 2 })
      }
      .width('calc(100% - 2px)')
      .height(this.dragPreviewHeight(hourHeight))
      .position({
        x: 1,
        y: this.dragPreviewTop(hourHeight, startHour)
      })
      .border({
        width: 1.5,
        color: this.dragPreviewColor,
        style: BorderStyle.Dashed
      })
      .borderRadius(4)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  /**
   * 构建底部半透明拖拽预览条。
   *
   * 当用户在周/日视图中拖拽任务包时，在日历区域底部显示吸附后的日程信息。
   * 格式："6月30日 15:00 - 15:45 健身包"
   */
  @Builder
  buildDragPreviewBar(): void {
    if (this.dragPreviewVisible) {
      Column() {
        Row() {
          if (this.dragPreviewHasTime) {
            // 有时间信息：显示完整时间范围
            Text(
              `${this.formatDateDisplay(this.dragPreviewDate)} ` +
              `${this.dragPreviewHour.toString().padStart(2, '0')}:${this.dragPreviewMinute.toString().padStart(2, '0')}` +
              ` - ${this.dragPreviewEndHour.toString().padStart(2, '0')}:${this.dragPreviewEndMinute.toString().padStart(2, '0')} ` +
              `${this.dragPreviewPkgName}`
            )
              .fontSize(12)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .padding({ left: 12, right: 8, top: 6, bottom: 6 })
          } else {
            // 拖拽中：仅显示日期和任务包名称
            Text(
              `${this.formatDateDisplay(this.dragPreviewDate)} ` +
              `${this.dragPreviewPkgName}`
            )
              .fontSize(12)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
              .padding({ left: 12, right: 8, top: 6, bottom: 6 })
          }

          // 颜色指示条
          Column()
            .width(4)
            .height(24)
            .borderRadius(2)
            .backgroundColor(this.dragPreviewColor)
            .margin({ right: 8 })
        }
        .width('calc(100% - 16px)')
        .borderRadius(8)
        .backgroundColor('#CC333333')
        .margin({ left: 8, right: 8, bottom: 6 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  // ==================== 月视图内容 ====================

  @Builder
  buildMonthContent(): void {
    Column() {
      // ---- 导航栏 ----
      Row() {
        // 上一个月
        Button('〈')
          .fontSize(20)
          .fontColor('#007AFF')
          .backgroundColor('#00000000')
          .padding(4)
          .onClick(() => { this.goToPrevMonth(); })

        // 回到今天按钮
        Button('今天')
          .fontSize(13)
          .fontColor('#007AFF')
          .backgroundColor('#EBF5FF')
          .borderRadius(12)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ left: 6 })
          .onClick(() => { this.goToToday(); })
          .enabled(!this.isCurrentMonthToday())
          .opacity(this.isCurrentMonthToday() ? 0.3 : 1.0)

        // 月份标题
        Text(this.monthLabel)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 视图切换按钮组
        this.buildViewSwitcher()

        // 下一个月
        Button('〉')
          .fontSize(20)
          .fontColor('#007AFF')
          .backgroundColor('#00000000')
          .padding(4)
          .margin({ left: 4 })
          .onClick(() => { this.goToNextMonth(); })
      }
      .width('100%')
      .padding({ top: 12, bottom: 8, left: 8, right: 8 })
      .backgroundColor('#FFFFFF')

      // ---- 星期标题行 ----
      Row() {
        ForEach(['一', '二', '三', '四', '五', '六', '日'],
          (dayName: string) => {
            Text(dayName)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(dayName === '六' || dayName === '日' ? '#FF3B30' : '#333333')
              .width('calc(100% / 7)')
              .textAlign(TextAlign.Center)
              .padding({ top: 4, bottom: 4 })
          }
        )
      }
      .width('100%')
      .backgroundColor('#FFFFFF')
      .padding({ bottom: 4 })

      // ---- 日期网格 ----
      Grid() {
        ForEach(this.calendarCells,
          (cell: CalendarCell, index: number) => {
            GridItem() {
              Stack() {
                Column() {
                  // 日期数字（当月和非当月都显示）
                  if (cell.date > 0) {
                    Text(cell.date.toString())
                      .fontSize(14)
                      .fontWeight(cell.isToday ? FontWeight.Bold : FontWeight.Regular)
                      /**
                       * Week 4 改进：非当月日期使用浅灰色，当月日期正常色。
                       * 今天仍然特殊高亮（白色文字 + 蓝色背景）。
                       */
                      .fontColor(
                        cell.isToday ? '#FFFFFF' :
                          cell.isCurrentMonth ?
                            (this.isWeekend(index) ? '#FF3B30' : '#333333') :
                            '#C0C0C0'  // 非当月日期置灰
                      )
                      .width(24)
                      .height(24)
                      .borderRadius(12)
                      .backgroundColor(cell.isToday ? '#007AFF' : '#00000000')
                      .textAlign(TextAlign.Center)
                      .margin({ top: 2 })
                  }

                  // 日程标记：彩色小圆点
                  if (cell.date > 0 && this.hasEventsOnDate(cell.dateStr)) {
                    Row({ space: 2 }) {
                      ForEach(
                        this.getEventsForDate(cell.dateStr).slice(0, 3),
                        (evt: ScheduledEvent) => {
                          Circle({ width: 5, height: 5 })
                            .fill(evt.color)
                            .opacity(this.isEventCompleted(evt) ? 0.45 : 1)
                        }
                      )
                      if (this.getEventsForDate(cell.dateStr).length > 3) {
                        Text('+')
                          .fontSize(8)
                          .fontColor('#999999')
                      }
                    }
                    .padding({ top: 2 })
                  }

                  Blank()
                }
                .width('100%')
                .height('100%')
                .padding(2)
                /**
                 * Week 4 改进：非当月格子背景色更淡（#F5F5F5），
                 * 当月格子保持白色（#FFFFFF）。
                 */
                .backgroundColor(cell.isCurrentMonth ? '#FFFFFF' : '#F5F5F5')

                /**
                 * 拖拽高亮覆盖层：
                 * 当用户拖拽任务包进入此日期格子时，显示蓝色半透明蒙层。
                 * 仅当月格子响应拖拽高亮。
                 */
                if (cell.isCurrentMonth && cell.date > 0 &&
                    this.dropHighlightDate === cell.dateStr) {
                  Column()
                    .width('100%')
                    .height('100%')
                    .backgroundColor('#007AFF20')
                    .border({
                      width: 2,
                      color: '#007AFF',
                      style: BorderStyle.Dashed
                    })
                    .borderRadius(4)
                }
              }
              .width('100%')
              .height('100%')
              .hitTestBehavior(HitTestMode.Default)
              /**
               * Week 4 新增：点击日期格子切换到日视图。
               * onClick 与拖拽手势不冲突（点击=短按，拖拽=长按拖动）。
               */
              .onClick(() => {
                if (cell.date > 0 && cell.dateStr) {
                  this.goToDayView(cell.dateStr);
                }
              })
              /**
               * 拖拽目标：只在当月格子上接收拖放。
               * 非当月格子不响应拖放。
               */
              .onDrop((event: DragEvent) => {
                if (cell.isCurrentMonth && cell.date > 0) {
                  this.handleDropByEvent(cell.dateStr, event);
                }
              })
              .onDragEnter(() => {
                if (cell.isCurrentMonth && cell.date > 0) {
                  this.handleDragEnter(cell.dateStr);
                }
              })
              .onDragLeave(() => {
                if (cell.isCurrentMonth && cell.date > 0) {
                  this.handleDragLeave(cell.dateStr);
                }
              })
            }
            .height(52)
          },
          /**
           * 键值生成器：使用 dateStr（如 "2026-06-15"）+ 索引做后备。
           *
           * 为什么不用 index.toString()？
           * 当切换月份时，calendarCells 数组长度不变（始终 42），
           * 纯索引键 "0"~"41" 不会变化，ArkUI ForEach 认为键未变、
           * 数据未变，直接复用旧 GridItem，导致日历"卡住不动"。
           *
           * 使用包含年月日的 dateStr 作为主键，每月每天都有唯一键，
           * 切换月份时所有键都会变，强制 ForEach 正确重建每个格子。
           */
          (_cell: CalendarCell, index: number) =>
            _cell.dateStr || `${this.currentYear}-${this.currentMonth}-${index}`
        )
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 周视图内容（Week 4 新增） ====================

  @Builder
  buildWeekContent(): void {
    Column() {
      // ---- 导航栏 ----
      Row() {
        // 上一周
        Button('〈')
          .fontSize(20)
          .fontColor('#007AFF')
          .backgroundColor('#00000000')
          .padding(4)
          .onClick(() => { this.goToPrevWeek(); })

        // 回到今天按钮
        Button('今天')
          .fontSize(13)
          .fontColor('#007AFF')
          .backgroundColor('#EBF5FF')
          .borderRadius(12)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ left: 6 })
          .onClick(() => { this.goToToday(); })
          .enabled(!this.isCurrentWeekContainingToday())
          .opacity(this.isCurrentWeekContainingToday() ? 0.3 : 1.0)

        // 周范围标题
        Text(this.weekLabel)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        // 视图切换按钮组
        this.buildViewSwitcher()

        // 下一周
        Button('〉')
          .fontSize(20)
          .fontColor('#007AFF')
          .backgroundColor('#00000000')
          .padding(4)
          .margin({ left: 4 })
          .onClick(() => { this.goToNextWeek(); })
      }
      .width('100%')
      .padding({ top: 12, bottom: 8, left: 8, right: 8 })
      .backgroundColor('#FFFFFF')

      // ---- 日期标题行（首列为周数，后 7 列为周一~周日） ----
      Row() {
        // 第一列：周数
        Column() {
          Text(this.weekNumberLabel)
            .fontSize(12)
            .fontColor('#888888')
        }
        .width(36)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)

        ForEach(this.weekDays,
          (day: WeekDayInfo) => {
            Column() {
              // 星期名称（如"周一"）
              Text(day.dayName)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(
                  day.isToday ? '#007AFF' :
                    (day.dayOfWeek >= 5 ? '#FF3B30' : '#666666')
                )
              // 日期数字 + 月份（如"6/22"）
              Text(`${day.monthNumber}/${day.dayNumber}`)
                .fontSize(13)
                .fontWeight(day.isToday ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(
                  day.isToday ? '#FFFFFF' :
                    (day.dayOfWeek >= 5 ? '#FF3B30' : '#333333')
                )
                .width(28)
                .height(28)
                .borderRadius(14)
                .backgroundColor(day.isToday ? '#007AFF' : '#00000000')
                .textAlign(TextAlign.Center)
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .padding({ top: 4, bottom: 6 })
            /**
             * Week 4：点击某天的标题，切换到该天的日视图。
             */
            .onClick(() => { this.goToDayView(day.dateStr); })
          },
          (day: WeekDayInfo) => day.dateStr
        )
      }
      .width('100%')
      .backgroundColor('#FFFFFF')
      .padding({ bottom: 4 })
      .border({ width: { bottom: 0.5 }, color: '#E8E8E8' })

      this.buildTransferBanner()

      // ---- 时间轴主体（可滚动） ----
      Scroll(this.weekScroller) {
        Stack({ alignContent: Alignment.Top }) {
          Row() {
            // ===== 左侧时间标签列 =====
            Column() {
              ForEach(
                this.generateHourRange(WEEK_START_HOUR, WEEK_END_HOUR - 1),
                (hour: number) => {
                  Column() {
                    Text(`${hour.toString().padStart(2, '0')}:00`)
                      .fontSize(9)
                      .fontColor('#AAAAAA')
                      .width('100%')
                      .textAlign(TextAlign.End)
                      .padding({ right: 4 })
                    Blank()
                  }
                  .height(this.weekHourHeight)
                  .width('100%')
                },
                (hour: number) => `time-${hour}`
              )
              // 24:00 末尾标签（贴时间轴底部，无下方槽位）
              Text('24:00')
                .fontSize(9)
                .fontColor('#AAAAAA')
                .width('100%')
                .textAlign(TextAlign.End)
                .padding({ right: 4 })
            }
            .width(36)
            .backgroundColor('#FAFAFA')
            .padding({ top: 0, bottom: 0 })

            // ===== 7 列日期栏（固定网格 + 绝对定位事件块） =====
            ForEach(this.weekDays,
              (day: WeekDayInfo) => {
                Stack({ alignContent: Alignment.Top }) {
                  // 事件块层：重叠的一对只渲染一张合并卡，避免依赖 Stack 覆盖顺序。
                  ForEach(this.getWeekEventGroups(day.dateStr),
                    (group: WeekEventGroup) => {
                      if (group.second !== undefined) {
                        Column() {
                          this.buildWeekMergedEventEntry(group.first, false)
                          Divider()
                            .strokeWidth(0.5)
                            .color('#66FFFFFF')
                          this.buildWeekMergedEventEntry(group.second, true)
                        }
                        .width('calc(100% - 2px)')
                        .borderRadius(4)
                        .backgroundColor(group.backgroundEvent.color)
                        .position({
                          x: 1,
                          y: (group.startMinutes - WEEK_START_HOUR * 60) /
                            60 * this.weekHourHeight + GRID_LINE_OFFSET
                        })
                        .height(Math.max(
                          (group.endMinutes - group.startMinutes) / 60 * this.weekHourHeight,
                          32
                        ))
                      } else {
                        Stack({ alignContent: Alignment.TopStart }) {
                          Column() {
                            Text(this.getEventDisplayTitle(group.first))
                              .fontSize(10)
                              .fontWeight(FontWeight.Bold)
                              .fontColor('#FFFFFF')
                              .maxLines(2)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .decoration({
                                type: this.isEventCompleted(group.first) ?
                                  TextDecorationType.LineThrough : TextDecorationType.None,
                                color: '#FFFFFF'
                              })
                              .width('100%')
                              .padding({ left: 2, right: 2, top: 2, bottom: 2 })
                            if (group.first.steps.length > 0) {
                              Text(
                                this.displayEventSteps(group.first)
                                  .map((s: TaskStep) => `${s.name}`)
                                  .join('·')
                              )
                                .fontSize(7)
                                .fontColor('#FFFFFF')
                                .opacity(0.8)
                                .maxLines(
                                  this.eventStepMaxLines(group.first, this.weekHourHeight, true)
                                )
                                .width('100%')
                                .padding({ left: 2, bottom: 2 })
                            }
                          }
                          .width('100%')
                          .height('100%')

                          this.buildStretchHandles(group.first, this.weekHourHeight)
                        }
                        .width('calc(100% - 2px)')
                        .borderRadius(4)
                        .backgroundColor(group.first.color)
                        .border({
                          width: this.stretchEventId === group.first.id ? 2 : 0,
                          color: '#FFFFFF'
                        })
                        .position({
                          x: 1,
                          y: this.eventBlockTop(
                            group.first, this.weekHourHeight, WEEK_START_HOUR
                          )
                        })
                        .height(this.eventBlockHeight(group.first, this.weekHourHeight, 20))
                        .opacity(this.isEventCompleted(group.first) ? 0.45 : 1)
                        .onClick(() => {
                          if (this.stretchEventId !== group.first.id) {
                            this.showPackageDetailByEvent(group.first);
                          }
                        })
                        .bindContextMenu(
                          this.contextMenuEventId === group.first.id,
                          () => { this.buildEventContextMenu(group.first); },
                          {
                            preview: MenuPreviewMode.NONE,
                            onDisappear: () => {
                              if (this.contextMenuEventId === group.first.id) {
                                this.contextMenuEventId = '';
                              }
                            }
                          }
                        )
                        .priorityGesture(
                          LongPressGesture({
                            repeat: false,
                            duration: 400,
                            allowableMovement: 18
                          })
                            .onAction(() => { this.showEventContextMenu(group.first); }),
                          GestureMask.Normal
                        )
                      }
                    },
                    (group: WeekEventGroup) => `${group.key}-v${this.schedulesVersion}`
                  )

                  // 单一网格覆盖层与时间轴共用 hourHeight；Transparent 允许下层事件继续命中。
                  Column() {
                    ForEach(
                      this.generateHourRange(WEEK_START_HOUR, WEEK_END_HOUR - 1),
                      (hour: number) => {
                        Column() {
                          Blank().height(GRID_LINE_OFFSET)
                          Row()
                            .width('100%')
                            .height(1)
                            .backgroundColor(GRID_LINE_COLOR)
                        }
                        .width('100%')
                        .height(this.weekHourHeight)
                      },
                      (hour: number) => `${day.dateStr}-grid-${hour}`
                    )
                  }
                  .width('100%')
                  .border({ width: { bottom: 1 }, color: GRID_LINE_COLOR })
                  .hitTestBehavior(HitTestMode.Transparent)

                  this.buildTimeAxisDragPreview(day.dateStr, this.weekHourHeight, WEEK_START_HOUR)
                }
                .layoutWeight(1)
                .backgroundColor(day.isToday ? '#F0F7FF' : '#FFFFFF')
                .onClick((event: ClickEvent) => {
                  if (this.transferMode !== '') {
                    this.pasteTransferredEvent(day.dateStr, event.y, this.weekHourHeight);
                  } else {
                    this.goToDayView(day.dateStr);
                  }
                })
                // ---- 周视图拖拽目标 ----
                .onDrop((event: DragEvent) => {
                  this.handleDropInTimeAxis(
                    event, day.dateStr, this.weekHourHeight,
                    this.weekScroller.currentOffset().yOffset, this.weekTimelineWindowY
                  );
                })
                .onDragEnter((event: DragEvent) => {
                  this.dropHighlightDate = day.dateStr;
                  this.handleDragMoveInTimeAxis(
                    event, day.dateStr, this.weekHourHeight,
                    this.weekScroller.currentOffset().yOffset, this.weekTimelineWindowY
                  );
                })
                .onDragMove((event: DragEvent) => {
                  this.handleDragMoveInTimeAxis(
                    event, day.dateStr, this.weekHourHeight,
                    this.weekScroller.currentOffset().yOffset, this.weekTimelineWindowY
                  );
                })
                .onDragLeave(() => {
                  this.dropHighlightDate = '';
                  if (this.dragPreviewDate === day.dateStr) {
                    this.dragPreviewVisible = false;
                    this.dragPreviewHasTime = false;
                  }
                })
              },
              (day: WeekDayInfo) => `col-${day.dateStr}`
            )
          }
          .width('100%')
          .padding({ right: 4 })
          .alignItems(VerticalAlign.Top)

          // 当前时间指示线
          if (this.isCurrentWeekContainingToday() && this.nowHour >= WEEK_START_HOUR) {
            this.buildTimeIndicator()
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#FFFFFF')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.weekTimelineWindowY = newValue.globalPosition.y as number;
      })
      .gesture(
        PinchGesture({ fingers: 2 })
          .onActionStart((event: GestureEvent) => {
            this.beginTimelinePinch('week', event);
          })
          .onActionUpdate((event: GestureEvent) => {
            this.updateTimelinePinch('week', event);
          })
      )
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 日视图内容（Week 4.5 重构：匹配周视图风格 + 放大动画） ====================

  /**
   * 构建日视图 —— 与周视图风格一致的单日时间轴。
   *
   * 布局：
   * ┌──────────────────────────────────────────────┐
   * │ 〈  今天  2026年6月30日 星期二  [月|周|日]  〉 │  ← 导航栏
   * ├──────┬───────────────────────────────────────┤
   * │ 00:00│- - - - - - - - - - - - - - - - - - -│  ← 灰色虚线分隔
   * │ 01:00│- - - - - - - - - - - - - - - - - - -│
   * │ ...  │                                       │
   * │ 09:00│  ┌──────────────────────────────┐    │  ← 彩色事件块
   * │      │  │ 晨间运动           09:00    │    │
   * │      │  │ 跑步 20min · 拉伸 5min       │    │
   * │      │  └──────────────────────────────┘    │
   * │      │- - - - - - - - - - - - - - - - - - -│
   * └──────┴───────────────────────────────────────┘
   *
   * 左侧时间标签与周视图完全一致：灰色小字（fontSize=9, #AAAAAA），宽 36vp。
   * 小时之间用灰色细虚线（BorderStyle.Dashed）分隔。
   * 整个视图应用 scale 变换，用于从周/月点击进入时的"放大"过渡动画。
   */
  @Builder
  buildDayContent(): void {
    Column() {
      // ---- 导航栏 ----
      Row() {
        // 前一天
        Button('〈')
          .fontSize(20)
          .fontColor('#007AFF')
          .backgroundColor('#00000000')
          .padding(4)
          .onClick(() => { this.goToPrevDay(); })

        // 回到今天按钮
        Button('今天')
          .fontSize(13)
          .fontColor('#007AFF')
          .backgroundColor('#EBF5FF')
          .borderRadius(12)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .margin({ left: 6 })
          .onClick(() => { this.goToToday(); })
          .enabled(!this.isSelectedDateToday())
          .opacity(this.isSelectedDateToday() ? 0.3 : 1.0)

        // 日期标题（居中，显示完整日期 + 星期）
        Text(this.dayLabel)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)

        // 视图切换按钮组
        this.buildViewSwitcher()

        // 后一天
        Button('〉')
          .fontSize(20)
          .fontColor('#007AFF')
          .backgroundColor('#00000000')
          .padding(4)
          .margin({ left: 4 })
          .onClick(() => { this.goToNextDay(); })
      }
      .width('100%')
      .padding({ top: 12, bottom: 8, left: 8, right: 8 })
      .backgroundColor('#FFFFFF')

      // ---- 日期标题（固定在顶部，不随滚动而滚动） ----
      Row() {
        Text(this.dayLabel)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1A1A')
          .padding({ left: 12, top: 10, bottom: 10 })
      }
      .width('100%')
      .backgroundColor('#FFFFFF')
      .border({ width: { bottom: 0.5 }, color: '#EEEEEE' })

      this.buildTransferBanner()

      // ---- 单日时间轴（与周视图风格一致） ----
      Scroll(this.dayScroller) {
        Stack({ alignContent: Alignment.Top }) {
          Row() {
            // ===== 左侧时间标签列 =====
            Column() {
              ForEach(
                this.generateHourRange(0, 24),
                (hour: number) => {
                  Column() {
                    Text(`${hour.toString().padStart(2, '0')}:00`)
                      .fontSize(9)
                      .fontColor('#AAAAAA')
                      .width('100%')
                      .textAlign(TextAlign.End)
                      .padding({ right: 4 })
                    Blank()
                  }
                  .height(this.dayHourHeight)
                  .width('100%')
                },
                (hour: number) => `day-time-${hour}`
              )
              // 24:00 末尾标签（贴时间轴底部，无下方槽位）
              Text('24:00')
                .fontSize(9)
                .fontColor('#AAAAAA')
                .width('100%')
                .textAlign(TextAlign.End)
                .padding({ right: 4 })
            }
            .width(36)
            .backgroundColor('#FAFAFA')
            .padding({ top: 0, bottom: 0 })

            // ===== 右侧：单日内容（固定网格 + 绝对定位事件块） =====
            Stack({ alignContent: Alignment.Top }) {
              // 事件块层：重叠日程分配到左右两列，未重叠日程仍占满宽度。
              ForEach(this.getDayEventLayouts(this.selectedDateStr),
                (layout: DayEventLayout) => {
                  Stack({ alignContent: Alignment.TopStart }) {
                    Column() {
                      Row() {
                        Text(this.getEventDisplayTitle(layout.event))
                          .fontSize(12)
                          .fontWeight(FontWeight.Bold)
                          .fontColor('#FFFFFF')
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .decoration({
                            type: this.isEventCompleted(layout.event) ?
                              TextDecorationType.LineThrough : TextDecorationType.None,
                            color: '#FFFFFF'
                          })
                          .layoutWeight(1)
                        Text(
                          this.displayEventStartLabel(layout.event)
                        )
                          .fontSize(10)
                          .fontColor('#FFFFFF')
                          .opacity(0.8)
                      }
                      .width('100%')
                      .padding({ left: 6, right: 6, top: 4 })
                      if (layout.event.steps.length > 0) {
                        Text(
                          this.displayEventSteps(layout.event)
                            .map((s: TaskStep) => `${s.name} ${s.duration}min`)
                            .join(' · ')
                        )
                          .fontSize(9)
                          .fontColor('#FFFFFF')
                          .opacity(0.75)
                          .maxLines(
                            this.eventStepMaxLines(layout.event, this.dayHourHeight, false)
                          )
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                          .padding({ left: 6, right: 6, bottom: 4 })
                      }
                    }
                    .width('100%')
                    .height('100%')

                    this.buildStretchHandles(layout.event, this.dayHourHeight)
                  }
                  .width(layout.isOverlapping ? 'calc(50% - 7px)' : 'calc(100% - 12px)')
                  .borderRadius(6)
                  .backgroundColor(layout.event.color)
                  .border({
                    width: this.stretchEventId === layout.event.id ? 2 : 0,
                    color: '#FFFFFF'
                  })
                  .position({
                    x: layout.isOverlapping && layout.column === 1 ? '50%' : 6,
                    y: this.eventBlockTop(layout.event, this.dayHourHeight)
                  })
                  .height(this.eventBlockHeight(layout.event, this.dayHourHeight, 28))
                  .opacity(this.isEventCompleted(layout.event) ? 0.45 : 1)
                  .onClick(() => {
                    if (this.stretchEventId !== layout.event.id) {
                      this.showPackageDetailByEvent(layout.event);
                    }
                  })
                  .bindContextMenu(
                    this.contextMenuEventId === layout.event.id,
                    () => { this.buildEventContextMenu(layout.event); },
                    {
                      preview: MenuPreviewMode.NONE,
                      onDisappear: () => {
                        if (this.contextMenuEventId === layout.event.id) {
                          this.contextMenuEventId = '';
                        }
                      }
                    }
                  )
                  .priorityGesture(
                    LongPressGesture({
                      repeat: false,
                      duration: 400,
                      allowableMovement: 18
                    })
                      .onAction(() => { this.showEventContextMenu(layout.event); }),
                    GestureMask.Normal
                  )
                },
                (layout: DayEventLayout) =>
                  `${layout.event.id}-c${layout.column}-v${this.schedulesVersion}`
              )

              // 单一网格覆盖层与时间轴共用 hourHeight；Transparent 允许下层事件继续命中。
              Column() {
                ForEach(
                  this.generateHourRange(0, 24),
                  (hour: number) => {
                    Column() {
                      Blank().height(GRID_LINE_OFFSET)
                      Row()
                        .width('100%')
                        .height(1)
                        .backgroundColor(GRID_LINE_COLOR)
                    }
                    .width('100%')
                    .height(this.dayHourHeight)
                  },
                  (hour: number) => `day-grid-${hour}`
                )
              }
              .width('100%')
              .border({ width: { bottom: 1 }, color: GRID_LINE_COLOR })
              .hitTestBehavior(HitTestMode.Transparent)

              this.buildTimeAxisDragPreview(this.selectedDateStr, this.dayHourHeight, 0)
            }
            .layoutWeight(1)
            .backgroundColor('#FFFFFF')
            .onClick((event: ClickEvent) => {
              if (this.transferMode !== '') {
                this.pasteTransferredEvent(this.selectedDateStr, event.y, this.dayHourHeight);
              }
            })
            // ---- 日视图拖拽目标 ----
            .onDrop((event: DragEvent) => {
              this.handleDropInTimeAxis(
                event, this.selectedDateStr, this.dayHourHeight,
                this.dayScroller.currentOffset().yOffset, this.dayTimelineWindowY
              );
            })
            .onDragEnter((event: DragEvent) => {
              this.dropHighlightDate = this.selectedDateStr;
              this.handleDragMoveInTimeAxis(
                event, this.selectedDateStr, this.dayHourHeight,
                this.dayScroller.currentOffset().yOffset, this.dayTimelineWindowY
              );
            })
            .onDragMove((event: DragEvent) => {
              this.handleDragMoveInTimeAxis(
                event, this.selectedDateStr, this.dayHourHeight,
                this.dayScroller.currentOffset().yOffset, this.dayTimelineWindowY
              );
            })
            .onDragLeave(() => {
              this.dropHighlightDate = '';
              this.dragPreviewVisible = false;
              this.dragPreviewHasTime = false;
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          // 当前时间指示线
          if (this.isSelectedDateToday()) {
            this.buildTimeIndicator()
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#FFFFFF')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.dayTimelineWindowY = newValue.globalPosition.y as number;
      })
      .gesture(
        PinchGesture({ fingers: 2 })
          .onActionStart((event: GestureEvent) => {
            this.beginTimelinePinch('day', event);
          })
          .onActionUpdate((event: GestureEvent) => {
            this.updateTimelinePinch('day', event);
          })
      )
    }
    .width('100%')
    .height('100%')
    /**
     * 缩放变换：用于从周/月视图点击某天进入日视图时的"放大"过渡动画。
     * goToDayView() 先将 dayViewScale 设为 0.6，再用 animateTo 过渡到 1，
     * 产生从点击的那天"放大展开"的视觉效果。
     */
    .scale({ x: this.dayViewScale, y: this.dayViewScale })
  }

  // ==================== 辅助方法 ====================

  /**
   * 计算事件块在时间轴上的垂直起始位置（vp）。
   * 公式：top = (startHour×60 + startMinute) / 60 × hourHeight。
   * 支持非整点开始（如 15:30 落在半格位置）。
   */
  private eventBlockTop(
    evt: ScheduledEvent, hourHeight: number, startHour: number = 0
  ): number {
    // 加上 GRID_LINE_OFFSET：分割线相对槽位顶部下移了该值，事件块上边界需与分割线对齐
    const startMinutes: number = this.stretchEventId === evt.id ?
      this.stretchPreviewStartMinutes : evt.startHour * 60 + evt.startMinute;
    return (startMinutes - startHour * 60) / 60 * hourHeight + GRID_LINE_OFFSET;
  }

  /**
   * 计算事件块高度（vp），支持跨小时：height = 总时长/60 × hourHeight。
   * 设最小高度，避免极短事件（如 5 分钟）视觉上不可见。
   */
  private eventBlockHeight(evt: ScheduledEvent, hourHeight: number, minHeight: number): number {
    const duration: number = this.stretchEventId === evt.id ?
      this.stretchPreviewDuration : getTotalDuration(evt.steps);
    return Math.max(duration / 60 * hourHeight, minHeight);
  }

  /** 根据事件块的缩放后高度，逐步放宽步骤摘要可显示行数。 */
  private eventStepMaxLines(evt: ScheduledEvent, hourHeight: number, compact: boolean): number {
    const blockHeight: number = this.eventBlockHeight(evt, hourHeight, compact ? 20 : 28);
    const lineHeight: number = compact ? 10 : 13;
    const reservedHeight: number = compact ? 18 : 26;
    const maxLines: number = compact ? 4 : 8;
    return Math.max(1, Math.min(maxLines, Math.floor((blockHeight - reservedHeight) / lineHeight)));
  }

  /**
   * 生成小时范围数组，用于 ForEach 循环
   * @param start 起始小时（含）
   * @param end 结束小时（不含）
   */
  private generateHourRange(start: number, end: number): number[] {
    const result: number[] = [];
    for (let h: number = start; h < end; h++) {
      result.push(h);
    }
    return result;
  }

  /**
   * 将颜色与白色混合，用于制作浅色背景的事件卡片
   * @param hexColor 原始十六进制颜色，如 "#007AFF"
   * @param ratio 原始颜色的比例（0-1），剩余部分混合白色
   */
  private mixWithWhite(hexColor: string, ratio: number): string {
    if (!hexColor || hexColor.length < 7) {
      return hexColor;
    }
    try {
      const r: number = parseInt(hexColor.substring(1, 3), 16);
      const g: number = parseInt(hexColor.substring(3, 5), 16);
      const b: number = parseInt(hexColor.substring(5, 7), 16);
      const mixedR: number = Math.round(r * ratio + 255 * (1 - ratio));
      const mixedG: number = Math.round(g * ratio + 255 * (1 - ratio));
      const mixedB: number = Math.round(b * ratio + 255 * (1 - ratio));
      return `#${mixedR.toString(16).padStart(2, '0')}${mixedG.toString(16).padStart(2, '0')}${mixedB.toString(16).padStart(2, '0')}`;
    } catch (_e) {
      return hexColor;
    }
  }

  /**
   * 判断当前显示的月份是否就是今天所在的月份。
   * 用于「今天」按钮的启用/禁用判断。
   */
  isCurrentMonthToday(): boolean {
    const today: Date = new Date();
    return this.currentYear === today.getFullYear() &&
      this.currentMonth === today.getMonth();
  }

  /**
   * 判断当前显示的周是否包含今天。
   * Week 4 新增：用于周视图「今天」按钮的启用/禁用判断。
   */
  isCurrentWeekContainingToday(): boolean {
    const today: Date = new Date();
    const monday: Date = CalendarTab.getMondayOf(today);
    return monday.getTime() === this.currentWeekStart.getTime();
  }

  /**
   * 判断当前选中的日期是否是今天。
   * Week 4 新增：用于日视图「今天」按钮的启用/禁用判断。
   */
  isSelectedDateToday(): boolean {
    const today: Date = new Date();
    const todayStr: string = this.formatDateStr(
      today.getFullYear(), today.getMonth(), today.getDate()
    );
    return this.selectedDateStr === todayStr;
  }

  /** 判断某个索引位置是否是周末（月视图网格中第 6、7 列） */
  isWeekend(index: number): boolean {
    const col: number = index % 7; // 0=周一, 6=周日
    return col === 5 || col === 6;  // 周六、周日
  }

  /**
   * 将 24 小时制的时间转为可读字符串，例如 9 → "09:00"
   */
  formatHour(hour: number): string {
    return `${hour.toString().padStart(2, '0')}:00`;
  }

  /**
   * 获取某个日期所在周的周一日期（静态工具方法）
   * @param date 任意日期
   * @returns 该日期所在周的周一 00:00:00
   */
  static getMondayOf(date: Date): Date {
    const d: Date = new Date(date);
    const day: number = d.getDay(); // 0=周日, 1=周一, ..., 6=周六
    // 计算到周一的偏移量
    const diff: number = day === 0 ? -6 : 1 - day;
    d.setDate(d.getDate() + diff);
    d.setHours(0, 0, 0, 0);
    return d;
  }
}
