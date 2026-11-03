/**
 * TaskPackage.ets —— 数据模型与全局状态管理
 *
 * 定义：
 * - TaskStep 接口：单个步骤的数据结构
 * - TaskPackage 接口：任务包的数据结构（Week 2 新增 color 字段）
 * - TaskStore 单例：全局任务包存储
 * - 颜色分配工具：为每个任务包自动分配主题色
 */

import { persistence } from './Persistence';
import { scheduleStore } from './ScheduledEvent';
import { TaskAction } from './TaskAction';

// ==================== 预设颜色数组 ====================
/**
 * PACKAGE_COLORS：8 种主题色，循环分配给新创建的任务包。
 *
 * 颜色设计原则：
 * - 每个颜色都有足够的亮度，白色文字在其上可读
 * - 相邻颜色区分度大，在日历小圆点中也能分辨
 */
export const PACKAGE_COLORS: string[] = [
  '#FF9500', // 橙色 — 健身体育
  '#007AFF', // 蓝色 — 学习阅读
  '#34C759', // 绿色 — 家务清洁
  '#FF3B30', // 红色 — 紧急重要
  '#AF52DE', // 紫色 — 兴趣创意
  '#FFCC00', // 黄色 — 休闲娱乐
  '#5AC8FA', // 天蓝 — 日常工作
  '#FF6482', // 粉色 — 个人护理
];

/**
 * 根据已有任务包数量，返回下一个可用的颜色
 *
 * 算法：取数组长度取模，实现循环使用
 * 例如：第1个用橙色，第2个用蓝色……第9个又用橙色
 */
export function getNextColor(existingCount: number): string {
  return PACKAGE_COLORS[existingCount % PACKAGE_COLORS.length];
}

// ==================== TaskStep 接口 ====================
export interface TaskStep {
  /** 步骤名称，例如 "跑步" */
  name: string;
  /** 步骤时长，单位：分钟 */
  duration: number;
}

// ==================== TaskPackage 接口 ====================
export interface TaskPackage {
  /** 唯一标识，随机生成 */
  id: string;
  /** 任务包名称，例如 "晨间运动" */
  name: string;
  /** 包含的步骤列表 */
  steps: TaskStep[];
  /** (Week 2 新增) 主题色，用于卡片背景和日历标记 */
  color: string;
  /** 用户明确配置的低风险启动动作 */
  actions?: TaskAction[];
  /**
   * 内部版本号：每次 updatePackage 自增。
   * 不暴露给 UI 表单，仅用于 ForEach key 强制刷新——
   * 编辑后 id 不变但 _version 变化 → key 变化 → ListItem 重建。
   */
  _version: number;
}

// ==================== ID 生成工具 ====================
export function generateId(): string {
  const timePart: string = Date.now().toString(36);
  const randomPart: string = Math.random().toString(36).substring(2, 10);
  return `${timePart}-${randomPart}`;
}

/** 任务包列表在 Preferences 中的存储键 */
const TASK_PACKAGES_KEY: string = 'task_packages';

// ==================== TaskStore 单例 ====================
/**
 * 全局任务包数据仓库（持久化到用户首选项，应用重启后保留）
 */
class TaskStore {
  private static instance: TaskStore;
  public packages: TaskPackage[] = [];

  static getInstance(): TaskStore {
    if (!TaskStore.instance) {
      TaskStore.instance = new TaskStore();
    }
    return TaskStore.instance;
  }

  /**
   * 添加任务包
   * 颜色在外部（CreatePackage）确定后传入，这里只负责存储
   */
  public addPackage(pkg: TaskPackage): void {
    pkg._version = 0;
    this.packages.push(pkg);
    this.persist();
  }

  /**
   * 根据 ID 查找任务包，找不到返回 undefined
   */
  public getPackageById(id: string): TaskPackage | undefined {
    return this.packages.find((p: TaskPackage) => p.id === id);
  }

  /**
   * 更新指定 ID 的任务包数据。
   *
   * 用于编辑页面保存时，替换原任务包的全部字段。
   * 直接修改数组中的引用，调用方需要负责刷新 UI。
   *
   * @param id 要更新的任务包 ID
   * @param updatedPkg 新的任务包数据（需包含完整的 id、name、steps、color）
   * @returns 是否找到并更新成功
   */
  public updatePackage(id: string, updatedPkg: TaskPackage): boolean {
    const index: number = this.packages.findIndex((p: TaskPackage) => p.id === id);
    if (index !== -1) {
      // 版本号自增，驱动 ForEach key 变化 → ListItem 强制重建
      updatedPkg._version = (this.packages[index]._version || 0) + 1;
      this.packages[index] = updatedPkg;
      this.persist();
      // 级联同步已排日程中的冗余字段（packageName / color / steps / 结束时间）
      scheduleStore.syncPackageFields(updatedPkg);
      return true;
    }
    return false;
  }

  /**
   * 删除指定 ID 的任务包。
   *
   * 使用 filter 创建新数组，有利于响应式检测。
   * 删除成功后级联删除所有关联的 ScheduledEvent（见 scheduleStore.removeEventsByPackageId）。
   *
   * @param id 要删除的任务包 ID
   * @returns 是否找到并删除成功
   */
  public deletePackage(id: string): boolean {
    const initialLength: number = this.packages.length;
    this.packages = this.packages.filter((p: TaskPackage) => p.id !== id);
    const changed: boolean = this.packages.length < initialLength;
    if (changed) {
      this.persist();
      // 级联删除关联日程，避免产生"幽灵日程"
      scheduleStore.removeEventsByPackageId(id);
    }
    return changed;
  }

  /**
   * 将当前任务包列表序列化并写入 Preferences。
   * 在所有会改变 packages 的方法（add / update / delete）末尾调用。
   */
  public persist(): void {
    persistence.writeString(TASK_PACKAGES_KEY, JSON.stringify(this.packages));
  }

  /**
   * 从 Preferences 读取任务包列表并恢复内存数据。
   * 仅在应用启动时由 EntryAbility 调用一次，键不存在时保持空数组。
   */
  public restore(): void {
    const raw: string = persistence.readString(TASK_PACKAGES_KEY);
    if (raw !== '') {
      this.packages = JSON.parse(raw) as TaskPackage[];
    }
  }
}

export const taskStore: TaskStore = TaskStore.getInstance();
