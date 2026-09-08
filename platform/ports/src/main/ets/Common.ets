/**
 * platform/ports — 端口公共类型（PLAT-001）。
 *
 * Subscription：所有「变更监听」类端口统一的注销句柄。
 * 约定：
 * - unsubscribe() 幂等，重复调用无副作用；
 * - unsubscribe() 之后实现不得再向该 listener 派发任何事件（迟到的底层事件被丢弃）。
 */

export interface Subscription {
  unsubscribe(): void;

  /** 查询是否已注销（调试/断言用）。 */
  readonly isActive: boolean;
}
