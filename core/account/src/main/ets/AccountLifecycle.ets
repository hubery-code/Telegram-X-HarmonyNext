/**
 * core/account — AccountScope 生命周期状态机（CORE-003）。
 *
 * 计划 §5.5：AccountScope 生命周期至少覆盖创建/激活/休眠/销毁。
 * 本文件是纯 reducer（无副作用、无时钟、无 IO），全部转换可单测；
 * AccountScope 负责在转换成立时执行网关启停等副作用，并保证幂等。
 *
 * 状态语义：
 * - active：gateway 订阅中，事件正常派发给账号监听；
 * - hibernating：gateway 退订，描述符与数据目录保留，可经 activate 恢复；
 * - closed：终态。任意事件都返回 closed（幂等），迟到事件由 scope 层丢弃并计数。
 */

import { AppError, AppErrors, Result, err, ok } from '@tgx/core-common';

export type AccountLifecycleState = 'active' | 'hibernating' | 'closed';

export type AccountLifecycleEvent = 'activate' | 'hibernate' | 'close';

/** 新建 scope 的初始状态：创建即激活（对应 §6.1 冷启动「create AccountScope」）。 */
export const INITIAL_ACCOUNT_LIFECYCLE: AccountLifecycleState = 'active';

/**
 * 生命周期转换 reducer。约定：
 * - activate/hibernate 在目标状态已是自身时返回原状态（幂等 no-op）；
 * - close 从任意非终态进入 closed；
 * - closed 为终态：任何事件都安全地返回 closed，绝不抛错。
 */
export function reduceAccountLifecycle(
  state: AccountLifecycleState,
  event: AccountLifecycleEvent
): Result<AccountLifecycleState, AppError> {
  if (state === 'closed') {
    return ok<AccountLifecycleState, AppError>('closed');
  }
  switch (event) {
    case 'activate':
      return ok<AccountLifecycleState, AppError>('active');
    case 'hibernate':
      return ok<AccountLifecycleState, AppError>('hibernating');
    case 'close':
      return ok<AccountLifecycleState, AppError>('closed');
    default:
      return err<AccountLifecycleState, AppError>(
        AppErrors.internal('core_account.lifecycle.unknown_event', `unknown lifecycle event: ${event}`)
      );
  }
}
