/**
 * platform/ports — NetworkStatePort 网络状态契约（PLAT-001）。
 *
 * 对应计划 §5.7：监听默认网络变化，将网络可用性和切换信号发给 gateway。
 * 生产实现由 PLAT-004 基于 HarmonyOS Network Kit 提供；本模块只定义契约 + Fake。
 *
 * 语义约定：
 * - 快照式读取 current() + 推送式监听 observe()，纯 ArkTS 无 Kit 回调泄漏；
 * - 实现必须对「值相同的连续快照」去重：不连续推送两个相等的 NetworkSnapshot
 *  （Fake 按全字段相等去重；生产 adapter 若底层天然重复上报，也必须过滤）；
 * - 断网时 transport 为 null、metered 为 false；
 * - 推送在注册监听后至少派发一次当前快照（初始值语义），后续仅派发散逸；
 * - 监听回调线程：实现保证串行派发（无并发重入同一 listener）；
 * - 错误模型：current() 无失败路径；observe() 注册失败（如权限未授予）返回 err。
 */

import { Result, AppError } from '@tgx/core-common';
import { Subscription } from './Common';

export type NetworkTransport = 'wifi' | 'cellular' | 'ethernet' | 'other';

/** 不可变网络快照；两个字段全相等即视为同一快照。 */
export interface NetworkSnapshot {
  /** connected / disconnected。 */
  readonly connected: boolean;
  /** 主传输通道；断网时为 null。 */
  readonly transport: NetworkTransport | null;
  /** 计费网络提示（蜂窝通常为 true）；断网为 false。 */
  readonly metered: boolean;
}

export interface NetworkStatePort {
  /** 当前快照；无失败路径（取不到时返回 disconnected/unknown 语义快照）。 */
  current(): NetworkSnapshot;

  /**
   * 注册状态监听：立即向 listener 派发一次当前快照，之后仅在网络状态
   * 变化（且与上一快照不等）时派发。返回注销句柄。
   */
  observe(listener: (snapshot: NetworkSnapshot) => void): Result<Subscription, AppError>;
}
