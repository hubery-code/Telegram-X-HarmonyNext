/**
 * core/account — AuthorizationState 状态机（CORE-005：完整 reducer + 状态机封装）。
 *
 * 计划 §5.5：每个 AccountScope 持有一个 AuthorizationStateMachine。
 * 本文件实现：
 * - AuthState discriminated union（10 个状态，每个携带该状态下的 context）
 * - AuthEvent（TDLib updateAuthorizationState 已解析事件）
 * - AuthEffect（待执行 effect，由上层 TdGateway send 执行）
 * - authReducer(state, event, deps) → {state, effects}（纯 reducer，无 ArkUI/Kit 依赖）
 * - AuthorizationStateMachine（不可变包装，state 当前 + apply(event) 驱动一帧）
 * - AuthorizationStateHolder（scope 持有授权状态的位置，供 UI 只读）
 *
 * 状态转换语义参考 Android 行为基线：
 * docs/product/behavior-samples/login-flow.md §2 场景步骤序列。
 */

import { AppError } from '@tgx/core-common';

// ── AuthState（discriminated union）──

/** 登录类型：手机号 / 邮箱 / 二维码（留给 AUTH-001 扩展）。 */
export type LoginType = 'phone' | 'email' | 'qr';

/** 等待 setTdlibParameters（冷启动第一步，§6.1 恢复时序）。 */
export interface AuthStateWaitParams {
  readonly kind: 'waitParams';
}

/** 等待数据库加密 key（数据目录已知）。 */
export interface AuthStateWaitDbKey {
  readonly kind: 'waitDbKey';
  readonly dataDir: string;
}

/** 等待手机号/邮箱/二维码登录入口。 */
export interface AuthStateWaitPhone {
  readonly kind: 'waitPhone';
  readonly loginType: LoginType;
}

/** 等待验证码（已发送到 phoneOrEmail）。 */
export interface AuthStateWaitCode {
  readonly kind: 'waitCode';
  /** 已发送验证码的手机号或邮箱。 */
  readonly phoneOrEmail: string;
  /** 重发倒计时（毫秒），归零后重发按钮可用。 */
  readonly resendTimeoutMs: number;
  /** 验证码长度（按 codeInfo.length 动态适配）。 */
  readonly codeLength: number;
}

/** 等待 2FA 密码。 */
export interface AuthStateWait2FA {
  readonly kind: 'wait2fa';
  /** 密码提示（可能为空字符串）。 */
  readonly passwordHint: string;
  /** 是否有恢复邮箱。 */
  readonly hasRecoveryEmail: boolean;
  /** 恢复邮箱地址模式（脱敏，如 "j***@e***.com"，可能为空）。 */
  readonly recoveryEmailPattern: string;
}

/** 等待注册（调 registerUser）。 */
export interface AuthStateWaitRegistration {
  readonly kind: 'waitRegistration';
}

/** 授权完成，正常运行。 */
export interface AuthStateReady {
  readonly kind: 'ready';
}

/** 正在登出。 */
export interface AuthStateLoggingOut {
  readonly kind: 'loggingOut';
}

/** 正在关闭。 */
export interface AuthStateClosing {
  readonly kind: 'closing';
}

/** 已关闭。 */
export interface AuthStateClosed {
  readonly kind: 'closed';
}

/** 授权失败（携带 AppError）。 */
export interface AuthStateFailed {
  readonly kind: 'failed';
  readonly error: AppError;
}

export type AuthState =
  | AuthStateWaitParams
  | AuthStateWaitDbKey
  | AuthStateWaitPhone
  | AuthStateWaitCode
  | AuthStateWait2FA
  | AuthStateWaitRegistration
  | AuthStateReady
  | AuthStateLoggingOut
  | AuthStateClosing
  | AuthStateClosed
  | AuthStateFailed;

/** @deprecated 向后兼容别名，等价于 AuthState。 */
export type AuthorizationState = AuthState;

/** 初始状态：等待 setTdlibParameters（§6.1 恢复时序的第一步）。 */
export const INITIAL_AUTH_STATE: AuthState = { kind: 'waitParams' };

/** @deprecated 向后兼容别名，等价于 INITIAL_AUTH_STATE。 */
export const INITIAL_AUTHORIZATION_STATE: AuthState = INITIAL_AUTH_STATE;

// ── AuthEvent（TDLib updateAuthorizationState 已解析 /@type 事件）──

/** 验证码类型信息（TDLib AuthenticationCodeInfo.type 的简化表示）。 */
export interface AuthCodeInfo {
  /** 已发送验证码的手机号。 */
  readonly phoneNumber: string;
  /** 验证码类型 @type，如 "authenticationCodeTypeTelegramMessage"、"authenticationCodeTypeSms" 等。 */
  readonly codeType: string;
  /** 验证码长度。 */
  readonly length: number;
  /** 倒计时超时（秒），UI 层转换为毫秒。 */
  readonly timeout: number;
}

// ── AuthEvent（TDLib updateAuthorizationState 已解析 /@type 事件）──

export interface AuthEventWaitTdlibParameters { readonly type: 'authorizationStateWaitTdlibParameters'; }
export interface AuthEventWaitEncryptionKey { readonly type: 'authorizationStateWaitEncryptionKey'; readonly isEncrypted: boolean; }
export interface AuthEventWaitPhoneNumber { readonly type: 'authorizationStateWaitPhoneNumber'; }
export interface AuthEventWaitEmailAddress { readonly type: 'authorizationStateWaitEmailAddress'; }
export interface AuthEventWaitOtherDeviceConfirmation { readonly type: 'authorizationStateWaitOtherDeviceConfirmation'; }
export interface AuthEventWaitCode { readonly type: 'authorizationStateWaitCode'; readonly codeInfo: AuthCodeInfo; }
export interface AuthEventWaitPassword {
  readonly type: 'authorizationStateWaitPassword';
  readonly passwordHint: string;
  readonly hasRecoveryEmailAddress: boolean;
  readonly recoveryEmailAddressPattern: string;
}
export interface AuthEventWaitRegistration { readonly type: 'authorizationStateWaitRegistration'; }
export interface AuthEventReady { readonly type: 'authorizationStateReady'; }
export interface AuthEventLoggingOut { readonly type: 'authorizationStateLoggingOut'; }
export interface AuthEventClosing { readonly type: 'authorizationStateClosing'; }
export interface AuthEventClosed { readonly type: 'authorizationStateClosed'; }

export type AuthEvent =
  AuthEventWaitTdlibParameters
  | AuthEventWaitEncryptionKey
  | AuthEventWaitPhoneNumber
  | AuthEventWaitEmailAddress
  | AuthEventWaitOtherDeviceConfirmation
  | AuthEventWaitCode
  | AuthEventWaitPassword
  | AuthEventWaitRegistration
  | AuthEventReady
  | AuthEventLoggingOut
  | AuthEventClosing
  | AuthEventClosed;

// ── AuthEffect（待执行 effect，由上层 TdGateway send 执行）──

export interface AuthEffectNone { readonly kind: 'none'; }
export interface AuthEffectSetTdlibParameters { readonly kind: 'setTdlibParameters'; }
export interface AuthEffectCheckDbKey { readonly kind: 'checkDbKey'; }
export interface AuthEffectSendPhoneNumber { readonly kind: 'sendPhoneNumber'; }
export interface AuthEffectSendCode { readonly kind: 'sendCode'; }
export interface AuthEffectSendPassword { readonly kind: 'sendPassword'; }
export interface AuthEffectRegisterUser { readonly kind: 'registerUser'; }
export interface AuthEffectResendCode { readonly kind: 'resendCode'; }
export interface AuthEffectLogOut { readonly kind: 'logOut'; }

export type AuthEffect =
  AuthEffectNone
  | AuthEffectSetTdlibParameters
  | AuthEffectCheckDbKey
  | AuthEffectSendPhoneNumber
  | AuthEffectSendCode
  | AuthEffectSendPassword
  | AuthEffectRegisterUser
  | AuthEffectResendCode
  | AuthEffectLogOut;

// ── Reducer 依赖与结果 ──

/** authReducer 注入依赖。 */
export interface AuthReducerDeps {
  readonly accountId: string;
}

/** authReducer 返回：新状态 + 待执行 effect 列表。 */
export interface AuthReducerResult {
  readonly state: AuthState;
  readonly effects: readonly AuthEffect[];
}

// ── authReducer（纯 reducer，无副作用）──

/**
 * 授权状态转换 reducer。
 *
 * 约定：
 * - 输入：当前 AuthState + TDLib 授权状态事件 + 注入 deps
 * - 输出：新 AuthState + 待执行 effect（由上层 TdGateway send 执行）
 * - 不 import ArkUI，不 import TdGateway（只消费解析后的事件和 emit effect）
 * - 终态 closed 对任何事件幂等返回 closed
 * - 未知事件类型 → failed（AppError internal）
 * - 每个状态转换分支有对应 Android 行为基线注释
 */
export function authReducer(
  state: AuthState,
  event: AuthEvent,
  deps: AuthReducerDeps
): AuthReducerResult {
  // ── 终态 closed：任何事件都幂等返回 closed ──
  // 基线：MainActivity.java:609-614 登出期间 UI 不做页面切换，完成后 TDLib 实例销毁
  if (state.kind === 'closed' || state.kind === 'failed') {
    return { state: state, effects: [{ kind: 'none' }] };
  }

  switch (event.type) {
    // ── WaitTdlibParameters ──
    // 基线：冷启动第一步，App 发 SetTdlibParameters（数据库目录、api_id/api_hash 由 app 注入）
    // Android: MainActivity.java:630-642 initUnauthorizedController
    case 'authorizationStateWaitTdlibParameters':
      return {
        state: { kind: 'waitParams' },
        effects: [{ kind: 'setTdlibParameters' }]
      };

    // ── WaitEncryptionKey ──
    // 基线：TDLib 需要数据库加密 key（数据目录已知）
    case 'authorizationStateWaitEncryptionKey':
      return {
        state: {
          kind: 'waitDbKey',
          dataDir: deps.accountId !== '' ? `/accounts/${deps.accountId}/tdlib/db` : ''
        },
        effects: [{ kind: 'checkDbKey' }]
      };

    // ── WaitPhoneNumber ──
    // 基线：选择国家码、输入手机号，勾选服务条款 → SetAuthenticationPhoneNumber
    // Android: ui/PhoneController.java:1141
    case 'authorizationStateWaitPhoneNumber':
      return {
        state: { kind: 'waitPhone', loginType: 'phone' },
        effects: [{ kind: 'sendPhoneNumber' }]
      };

    // ── WaitEmailAddress ──
    // 基线：邮箱登录入口（Android: MainActivity.java:564-567 分支，PasswordController MODE_CODE）
    case 'authorizationStateWaitEmailAddress':
      return {
        state: { kind: 'waitPhone', loginType: 'email' },
        effects: [{ kind: 'sendPhoneNumber' }]
      };

    // ── WaitOtherDeviceConfirmation ──
    // 基线：TGX 不展示此状态（MainActivity.java:604-606 "Should never come to TGX"），仅作防御分支
    case 'authorizationStateWaitOtherDeviceConfirmation':
      return {
        state: { kind: 'waitPhone', loginType: 'qr' },
        effects: [{ kind: 'none' }]
      };

    // ── WaitCode ──
    // 基线：TDLib 接受手机号后进入验证码页，验证码输入框、倒计时、「重新发送」
    // Android: PasswordController MODE_CODE, MainActivity.java:564-567
    case 'authorizationStateWaitCode': {
      const codeInfo: AuthCodeInfo = event.codeInfo;
      return {
        state: {
          kind: 'waitCode',
          phoneOrEmail: codeInfo.phoneNumber !== undefined ? codeInfo.phoneNumber : '',
          resendTimeoutMs: codeInfo.timeout > 0 ? codeInfo.timeout * 1000 : 0,
          codeLength: codeInfo.length
        },
        effects: [{ kind: 'sendCode' }]
      };
    }

    // ── WaitPassword ──
    // 基线：账号已设 2FA → 密码页，含 passwordHint、恢复邮箱入口
    // Android: PasswordController MODE_LOGIN, MainActivity.java:588-591
    case 'authorizationStateWaitPassword': {
      const hint: string = event.passwordHint !== undefined ? event.passwordHint : '';
      return {
        state: {
          kind: 'wait2fa',
          passwordHint: hint,
          hasRecoveryEmail: event.hasRecoveryEmailAddress === true,
          recoveryEmailPattern: event.recoveryEmailAddressPattern !== undefined ? event.recoveryEmailAddressPattern : ''
        },
        effects: [{ kind: 'sendPassword' }]
      };
    }

    // ── WaitRegistration ──
    // 基线：新注册 → 名/姓两个输入框，提交 RegisterUser
    // Android: EditNameController MODE_SIGNUP, MainActivity.java:582-585
    case 'authorizationStateWaitRegistration':
      return {
        state: { kind: 'waitRegistration' },
        effects: [{ kind: 'registerUser' }]
      };

    // ── Ready ──
    // 基线：授权完成，授权页栈被 ChatsController 替换，进入会话列表
    // Android: MainActivity.java:612 分支
    case 'authorizationStateReady':
      return {
        state: { kind: 'ready' },
        effects: [{ kind: 'none' }]
      };

    // ── LoggingOut ──
    // 基线：设置 → 登出，LogOut → LoggingOut → Closing → Closed
    // Android: MainActivity.java:609-614 为空分支
    case 'authorizationStateLoggingOut':
      return {
        state: { kind: 'loggingOut' },
        effects: [{ kind: 'logOut' }]
      };

    // ── Closing ──
    // 基线：登出过渡态，UI 不做页面切换
    case 'authorizationStateClosing':
      return {
        state: { kind: 'closing' },
        effects: [{ kind: 'none' }]
      };

    // ── Closed ──
    // 基线：TDLib 实例销毁，回到手机号页
    case 'authorizationStateClosed':
      return {
        state: { kind: 'closed' },
        effects: [{ kind: 'none' }]
      };

    default: {
      // 未知事件类型 → failed（防御性分支）
      const _exhaustive: never = event;
      return {
        state: {
          kind: 'failed',
          error: {
            kind: 'internal',
            invariant: 'core_account.auth.unknown_event',
            message: `unknown auth event type: ${(_exhaustive as AuthEvent).type}`
          }
        },
        effects: [{ kind: 'none' }]
      };
    }
  }
}

// ── AuthorizationStateMachine（不可变包装）──

/**
 * 授权状态机：不可变包装 reducer。
 *
 * 用法：
 *   let machine = AuthorizationStateMachine.create(accountId);
 *   machine = machine.apply(event); // 不可变，返回新机实例
 *   console.log(machine.state.kind); // 当前状态
 */
export class AuthorizationStateMachine {
  readonly state: AuthState;
  private readonly accountId: string;

  private constructor(state: AuthState, accountId: string) {
    this.state = state;
    this.accountId = accountId;
  }

  /** 创建初始状态机（waitParams）。 */
  static create(accountId: string): AuthorizationStateMachine {
    return new AuthorizationStateMachine(INITIAL_AUTH_STATE, accountId);
  }

  /**
   * 驱动一帧：输入 TDLib 授权状态事件，返回新机实例（不可变）。
   *
   * @param event TDLib updateAuthorizationState 已解析事件
   * @returns 新 AuthorizationStateMachine 实例，state 与 effects 已更新
   */
  apply(event: AuthEvent): AuthorizationStateMachine {
    const result: AuthReducerResult = authReducer(this.state, event, { accountId: this.accountId });
    return new AuthorizationStateMachine(result.state, this.accountId);
  }
}

// ── AuthorizationStateHolder（scope 持有授权状态的位置）──

/**
 * scope 持有授权状态的位置。CORE-005 的 auth reducer 经此提交新状态；
 * UI（AUTH-001）只读 scope.authorization 渲染。
 */
export class AuthorizationStateHolder {
  private currentState: AuthState = INITIAL_AUTH_STATE;

  get current(): AuthState {
    return this.currentState;
  }

  /**
   * 以 reducer 产出的新状态整体替换。本包不做转换合法性校验——
   * 校验规则归 authReducer 纯 reducer。
   */
  replace(next: AuthState): void {
    this.currentState = next;
  }
}