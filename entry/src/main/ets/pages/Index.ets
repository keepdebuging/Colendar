/**
 * Index.ets —— 应用主页面（Tab 容器）
 *
 * Week 2 重构：引入底部导航栏，整合两个子页面。
 *
 * 结构：
 * ┌──────────────────────────┐
 * │    主内容区（TabContent）  │
 * │  Tab 0: TaskPackageTab   │
 * │  Tab 1: CalendarTab      │
 * ├──────────────────────────┤
 * │  📋 任务包  │  📅 日历    │  ← 底部导航栏
 * └──────────────────────────┘
 *
 * 默认显示 Tab 1（日历总览）。
 */

import { TaskPackageTab } from './TaskPackageTab';
import { CalendarTab } from './CalendarTab';

@Entry
@Component
struct Index {
  /**
   * 当前选中的 Tab 索引
   * 0 = 任务包列表
   * 1 = 日历总览（默认）
   */
  @State currentTabIndex: number = 1;

  /**
   * 数据刷新触发器
   *
   * 使用 @Provide 向所有后代组件广播。值变化时，
   * TaskPackageTab 和 CalendarTab 通过 @Consume 接收，
   * @Watch 自动触发 loadData()。
   *
   * 每次 onPageShow（从创建/编辑页返回）或切换 Tab 时递增。
   */
  @Provide refreshTrigger: number = 0;

  /**
   * 每次页面显示时触发（包括从创建页 router.back 返回）
   */
  onPageShow(): void {
    // 递增触发器，通知所有子 Tab 刷新数据
    this.refreshTrigger++;
  }

  build() {
    /**
     * Tabs 组件：底部导航栏容器
     *
     * barPosition: BarPosition.End → 导航栏在底部
     * index: this.currentTabIndex → 绑定当前选中的 Tab
     */
    Tabs({
      barPosition: BarPosition.End,
      index: this.currentTabIndex
    }) {
      // ========== Tab 0：任务包列表 ==========
      TabContent() {
        TaskPackageTab()
      }
      /**
       * tabBar：定义底部导航栏中该 Tab 的图标和文字
       * 使用自定义 @Builder 方法构建
       */
      .tabBar(this.TabBarBuilder('任务包', 0, '📋'))

      // ========== Tab 1：日历总览（默认）==========
      TabContent() {
        CalendarTab()
      }
      .tabBar(this.TabBarBuilder('日历', 1, '📅'))
    }
    .width('100%')
    .height('100%')
    .barWidth('100%')
    .barHeight(56)
    /**
     * onChange：当用户点击底部导航切换 Tab 时触发
     * 我们在此刷新数据，确保日历页和任务包页都是最新的
     */
    .onChange((index: number) => {
      this.currentTabIndex = index;
      // 切换 Tab 时刷新数据
      this.refreshTrigger++;
    })
    .id('main-tabs')
  }

  /**
   * TabBarBuilder：自定义底部导航栏的每个 Tab 按钮样式
   *
   * @param title Tab 文字
   * @param tabIndex Tab 索引
   * @param icon Tab 图标（使用 Emoji 临时替代，后续可替换为资源图片）
   */
  @Builder
  TabBarBuilder(title: string, tabIndex: number, icon: string) {
    Column() {
      // 图标
      Text(icon)
        .fontSize(20)
        .margin({ bottom: 2 })

      // 文字
      Text(title)
        .fontSize(11)
        .fontWeight(this.currentTabIndex === tabIndex ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTabIndex === tabIndex ? '#007AFF' : '#999999')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .id(tabIndex === 0 ? 'tab-packages' : 'tab-calendar')
  }
}
