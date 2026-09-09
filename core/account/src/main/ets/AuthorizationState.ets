/**
 * core/account — AuthorizationState 占位类型（CORE-003 → CORE-005 交接）。
 *
 * 计划 §5.5：每个 AccountScope 持有一个 AuthorizationStateMachine。
 * 本工作包只定义状态类型与「scope 持有它的位置」（AuthorizationStateHolder），
 * 状态转换 reducer（updateAuthorizationState → state 的映射）是 CORE-005 的职责，
 * 这里刻意不实现任何转换逻辑，holder 的 replace() 留给 CORE-005 的 reducer 产出驱动。
 */

/** 授权状态清单（计划 §5.5 状态机清单的 ArkTS 建模）。 */
export type AuthorizationState =
  'waitParams'
  | 'waitDbKey'
  | 'waitPhone'
  | 'waitCode'
  | 'wait2fa'
  | 'waitRegistration'
  | 'ready'
  | 'loggingOut'
  | 'closing'
  | 'closed'
  | 'failed';

/** 初始状态：等待 setTdlibParameters（§6.1 恢复时序的第一步）。 */
export const INITIAL_AUTHORIZATION_STATE: AuthorizationState = 'waitParams';

/**
 * scope 持有授权状态的位置。CORE-005 实现转换 reducer 后，
 * 经 scope.authorizationHolder.replace(nextState) 提交新状态；
 * UI（AUTH-001）只读 scope.authorization 渲染。
 */
export class AuthorizationStateHolder {
  private currentState: AuthorizationState = INITIAL_AUTHORIZATION_STATE;

  get current(): AuthorizationState {
    return this.currentState;
  }

  /**
   * 以 reducer 产出的新状态整体替换。本包不做转换合法性校验——
   * 校验规则归 CORE-005 的纯 reducer。
   */
  replace(next: AuthorizationState): void {
    this.currentState = next;
  }
}
