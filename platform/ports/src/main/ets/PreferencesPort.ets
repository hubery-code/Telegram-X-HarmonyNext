/**
 * platform/ports — PreferencesPort 键值偏好存储契约（PLAT-001）。
 *
 * 对应计划 §5.6：Preferences 只保存小型、非敏感开关（主题、字号、UI 偏好）。
 * 生产实现由 PLAT-002 基于 HarmonyOS Preferences Kit 提供；本模块只定义契约 + Fake。
 *
 * 语义约定：
 * - 纯 ArkTS 同步读写（生产 adapter 内部落盘，flush 为异步持久化点）；
 * - get* 返回值：key 不存在 → ok(null)；存在但类型不匹配 → err(parameter/invalid)；
 * - 变更监听对齐 HarmonyOS Preferences 语义：put/remove/clear 先作用于内存视图，
 *   监听器在 flush() 成功后按变更批次回调；flush 失败不产生 change 事件；
 * - 同一批次内对同一 key 的多次变更只向监听者推送最后一次（合并语义）；
 * - clear() 向监听者推送 key='*'、value=null 的通配变更（对齐 Preferences 的
 *   flush 后 change 通配行为，生产实现如无法区分应在此文档登记差异）；
 * - 错误统一用 core/common 的 Result<_, AppError> 表达，不做异常控制流。
 */

import { Result, AppError } from '@tgx/core-common';
import { Subscription } from './Common';

/** Preferences 可承载的值类型（与 HarmonyOS Preferences 原生类型一致）。 */
export type PreferenceValue = boolean | number | string;

/** 一次 flush 后对外可见的变更。value 为 null 表示该 key 被移除。 */
export interface PreferenceChange {
  readonly key: string;
  readonly value: PreferenceValue | null;
}

/** clear() 产生的通配变更事件的 key。 */
export const PREFERENCES_CLEAR_ALL_KEY: string = '*';

export interface PreferencesPort {
  /** 读取字符串；不存在返回 ok(null)，类型不匹配返回 err。 */
  getString(key: string): Result<string | null, AppError>;

  /** 读取数值；不存在返回 ok(null)，类型不匹配返回 err。 */
  getNumber(key: string): Result<number | null, AppError>;

  /** 读取布尔；不存在返回 ok(null)，类型不匹配返回 err。 */
  getBoolean(key: string): Result<boolean | null, AppError>;

  /** 写入键值（内存视图立即生效，持久化点在 flush）。 */
  put(key: string, value: PreferenceValue): Result<void, AppError>;

  /** 移除键；不存在的 key 视为成功（幂等）。 */
  remove(key: string): Result<void, AppError>;

  /** 清空全部键；语义等同逐 key 移除 + 通配变更事件。 */
  clear(): Result<void, AppError>;

  /** 把挂起的变更持久化；成功后按合并批次派发 change 事件。 */
  flush(): Promise<Result<void, AppError>>;

  /** 注册变更监听；返回注销句柄。注销后不得再收到事件。 */
  observeChanges(listener: (change: PreferenceChange) => void): Subscription;

  /** 当前是否挂起未 flush 的变更（测试/诊断用）。 */
  hasPendingChanges(): boolean;
}
