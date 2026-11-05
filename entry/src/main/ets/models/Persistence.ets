/**
 * Persistence.ets —— 全局持久化持有器
 *
 * 基于 @ohos.data.preferences（用户首选项）封装轻量级 KV 读写。
 * 供 TaskStore / ScheduleStore 调用，把内存数据序列化为 JSON 字符串落盘。
 *
 * 设计原则：
 * - 本模块不 import 任何 store，避免与 TaskStore / ScheduleStore 形成循环依赖。
 * - 全部使用同步接口（getPreferencesSync / getSync / putSync / flushSync），
 *   保证写入即落盘、读取即返回，无需处理异步时序。
 * - 单进程、轻量数据场景，符合 Preferences 的适用边界。
 */

import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** Preferences 实例名称（对应沙箱内的持久化文件名） */
const STORE_NAME: string = 'studystream_store';

/**
 * 持久化持有器单例。
 *
 * 由 EntryAbility.onCreate 调用 init() 注入 context 并缓存 Preferences 实例；
 * 之后各 store 直接调用 readString / writeString 即可，无需再接触 context。
 */
class Persistence {
  /** 缓存的 Preferences 实例，init 前为 null */
  private prefs: preferences.Preferences | null = null;

  /**
   * 初始化：获取 Preferences 实例。
   * 幂等——重复调用不会重复获取。
   *
   * @param context 应用上下文（Stage 模型下由 UIAbility 提供）
   */
  public init(context: common.Context): void {
    if (this.prefs !== null) {
      return;
    }
    this.prefs = preferences.getPreferencesSync(context, { name: STORE_NAME });
  }

  /**
   * 读取字符串类型的值，键不存在时返回空字符串。
   *
   * @param key 存储键
   */
  public readString(key: string): string {
    if (this.prefs === null) {
      throw new Error('PERSISTENCE_NOT_INITIALIZED');
    }
    const value: preferences.ValueType = this.prefs.getSync(key, '');
    if (typeof value !== 'string') {
      throw new Error('PERSISTENCE_VALUE_TYPE_INVALID');
    }
    return value;
  }

  /**
   * 写入字符串类型的值，并立即 flush 落盘。
   *
   * @param key 存储键
   * @param value 存储值（字符串）
   */
  public writeString(key: string, value: string): void {
    if (this.prefs === null) {
      throw new Error('PERSISTENCE_NOT_INITIALIZED');
    }
    this.prefs.putSync(key, value);
    this.prefs.flushSync();
  }
}

/** 导出全局唯一的持久化持有器实例 */
export const persistence: Persistence = new Persistence();

