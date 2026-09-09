/**
 * core/account — AccountCancellation：账号级取消域（CORE-003）。
 *
 * 计划 §5.5：AccountScope 是「该账号全部 pending request 的 cancellation owner」。
 * scope.request() 产出的每个 TdPendingRequest 都登记进本域：
 * - close() 时 cancelAll() 一次性取消全部未结算请求（迟到响应由 CORE-002
 *   的 tombstone 机制安全丢弃，绝不二次 resolve）；
 * - 请求结算（任意方式）后自动注销，域内不泄漏已完结句柄。
 * 全部操作在 ArkTS 单线程同步执行，无锁。
 */

import { AppError, Result } from '@tgx/core-common';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';

export class AccountCancellation {
  private readonly pending: Set<TdPendingRequest> = new Set();

  /** 登记一个 in-flight 请求；结算后自动注销。 */
  track(request: TdPendingRequest): void {
    this.pending.add(request);
    const self: AccountCancellation = this;
    request.promise.then((result: Result<TdWireObject, AppError>): void => {
      self.pending.delete(request);
    });
  }

  /** 取消全部未结算请求，返回实际取消数（已结算的不计）。幂等。 */
  cancelAll(): number {
    let cancelled: number = 0;
    for (const request of Array.from(this.pending)) {
      if (request.cancel()) {
        cancelled += 1;
      }
    }
    this.pending.clear();
    return cancelled;
  }

  get pendingCount(): number {
    return this.pending.size;
  }
}
