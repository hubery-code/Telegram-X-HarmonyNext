/**
 * entry/src/main/ets/deeplink/ScopeAppLinkPort.ets — 把 AccountScope 适配成 AppLinkTdPort。
 *
 * `AccountScope.request` 返回的是 `Result<TdPendingRequest>`（同步拿到在途请求、
 * 异步拿应答），而 AppLinkRouter 只想要「一次请求一次应答」。这层把两步合成一步。
 *
 * scope 用提供者而不是构造时快照：切账号会换 scope，未登录时根本没有 scope，
 * 而路由器只在页面创建时建一次。
 *
 * 出错时不回传 `AccountScope.request` 的原 `AppError`，只回一条 internal：
 * 路由器对任何失败都只给一个 `link_type_error` 结论，原错误在这里没有下游消费者。
 */

import { AppError, err, Result } from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { AppLinkTdPort, appLinkInternalError } from './AppLinkRouter';

export class ScopeAppLinkPort implements AppLinkTdPort {
  private readonly scopeProvider: () => AccountScope | null;

  constructor(scopeProvider: () => AccountScope | null) {
    this.scopeProvider = scopeProvider;
  }

  async request(method: string, params: TdWireObject): Promise<Result<TdWireObject, AppError>> {
    const scope: AccountScope | null = this.scopeProvider();
    if (scope === null) {
      return err<TdWireObject, AppError>(appLinkInternalError('no active account scope'));
    }
    const pending: Result<TdPendingRequest, AppError> = scope.request(method, params);
    // `getOrNull()` 而不是 `if (pending.ok) pending.value`：ArkTS 不收窄 Result，
    // 走判别式取不出「同步就失败」的那条错误，只能按可空句柄一次判掉。
    const inFlight: TdPendingRequest | null = pending.getOrNull();
    if (inFlight === null) {
      return err<TdWireObject, AppError>(appLinkInternalError(`request rejected: ${method}`));
    }
    return await inFlight.promise;
  }
}
