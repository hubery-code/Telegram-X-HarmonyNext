/**
 * feature/auth — 登录协调器（AUTH-001）。
 *
 * 桥接 core/account 的 AccountScope 与 feature/auth 的 AuthReducer：
 * - 接收 UI Intent 并经 authReducer 驱动状态更新
 * - 执行 AuthEffect（向 AccountScope 发起 TDLib 请求）
 * - 订阅 AccountScope 的事件流，解析 updateAuthorizationState 并驱动内部状态
 */

import { AppError, Result, err } from '@tgx/core-common';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AuthState,
  AuthEvent,
  AuthEffect as CoreAuthEffect,
  AuthReducerResult,
  authReducer,
  AuthorizationStateHolder
} from '@tgx/core-account';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { TdRoutedEvent, TdWireObject } from '@tgx/td-gateway';
import { AuthUiState } from '../contract/AuthUiState';
import {
  AuthIntent,
  CountdownTick,
  OnAuthStateChanged,
  OnRequestError,
  OnRecaptchaRequired
} from '../contract/AuthIntent';
import { AuthEffect, SendVerificationToken } from '../contract/AuthEffect';
import { authReducer as authFeatureReducer } from '../reducer/AuthReducer';
import { parseAuthEventFromWire, parseRecaptchaUpdateFromWire } from './AuthEventParser';

const DOMAIN: number = 0x0000;
const TAG: string = 'AuthCoordinator';

export interface AuthSubscriptionLike {
  unsubscribe(): void;
}

export interface AuthAccountScopeLike {
  readonly accountId: string;
  readonly authorization: AuthState;
  readonly authorizationHolder: AuthorizationStateHolder;
  request(method: string, params?: TdWireObject): Promise<Result<TdWireObject, AppError>>;
  subscribeEvents(listener: (event: TdRoutedEvent) => void): AuthSubscriptionLike;
}

export type AuthUiStateListener = (state: AuthUiState) => void;

export interface TdlibParametersConfig {
  readonly apiId: number;
  readonly apiHash: string;
  readonly databaseDirectory: string;
  readonly filesDirectory: string;
  readonly systemLanguageCode: string;
  readonly deviceModel: string;
  readonly applicationVersion: string;
  readonly useTestDc: boolean;
}

export interface AuthCoordinatorDeps {
  readonly scope: AuthAccountScopeLike;
  readonly env: ReducerEnv;
  readonly tdlibParameters: TdlibParametersConfig;
  readonly onNavigate?: (route: string) => void;
  readonly onToast?: (message: string) => void;
}

function wireParam1(key: string, value: string): TdWireObject {
  const json: string = `{"${key}":${JSON.stringify(value)}}`;
  const parsed: Object = JSON.parse(json);
  return parsed as TdWireObject;
}

function wireParam2(k1: string, v1: string, k2: string, v2: string): TdWireObject {
  const json: string = `{"${k1}":${JSON.stringify(v1)},"${k2}":${JSON.stringify(v2)}}`;
  const parsed: Object = JSON.parse(json);
  return parsed as TdWireObject;
}

function buildSetTdlibParametersParams(config: TdlibParametersConfig): TdWireObject {
  const obj: Record<string, Object> = {};
  obj['database_directory'] = config.databaseDirectory;
  obj['files_directory'] = config.filesDirectory;
  obj['api_id'] = config.apiId;
  obj['api_hash'] = config.apiHash;
  obj['system_language_code'] = config.systemLanguageCode;
  obj['device_model'] = config.deviceModel;
  obj['application_version'] = config.applicationVersion;
  obj['use_secret_chats'] = true;
  obj['use_message_database'] = true;
  obj['use_file_database'] = true;
  obj['use_chat_info_database'] = true;
  obj['use_test_dc'] = config.useTestDc;
  const json: string = JSON.stringify(obj);
  const parsed: Object = JSON.parse(json);
  return parsed as TdWireObject;
}

export class AuthCoordinator {
  private readonly scope: AuthAccountScopeLike;
  private readonly env: ReducerEnv;
  private readonly tdlibParameters: TdlibParametersConfig;
  private readonly onNavigate?: (route: string) => void;
  private readonly onToast?: (message: string) => void;

  private currentState: AuthUiState;
  private readonly listeners: AuthUiStateListener[] = [];
  private eventSubscription: AuthSubscriptionLike | null = null;
  private countdownTimerId: number | null = null;
  private tdlibParamsSent: boolean = false;
  private dbKeySent: boolean = false;

  constructor(deps: AuthCoordinatorDeps, initialState?: AuthUiState) {
    this.scope = deps.scope;
    this.env = deps.env;
    this.tdlibParameters = deps.tdlibParameters;
    this.onNavigate = deps.onNavigate;
    this.onToast = deps.onToast;
    this.currentState = initialState !== undefined ? initialState : AuthUiState.initial();
  }

  get state(): AuthUiState {
    return this.currentState;
  }

  start(): void {
    if (this.eventSubscription !== null) {
      return;
    }

    // 订阅 scope 的事件流
    this.eventSubscription = this.scope.subscribeEvents((event: TdRoutedEvent) => {
      this.handleIncomingEvent(event);
    });

    // TDLib 在 gateway.start() 后立刻 emit 初始授权事件，但此时 eventListener
    // 尚未注册，第一个事件被静默丢弃。这里主动补发当前状态对应的 core effect，
    // 确保 setTdlibParameters / checkDbKey 一定被执行。
    this.executeCoreEffectsForState(this.scope.authorization);

    // 初始状态同步
    this.dispatch(new OnAuthStateChanged(this.scope.authorization));
  }

  destroy(): void {
    if (this.eventSubscription !== null) {
      this.eventSubscription.unsubscribe();
      this.eventSubscription = null;
    }
    this.stopCountdownTimer();
    this.listeners.length = 0;
  }

  subscribe(listener: AuthUiStateListener): () => void {
    this.listeners.push(listener);
    listener(this.currentState);
    return () => {
      const idx: number = this.listeners.indexOf(listener);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
      }
    };
  }

  dispatch(intent: AuthIntent): void {
    const result: ReducerResult<AuthUiState, AuthEffect> = authFeatureReducer(
      this.currentState,
      intent,
      this.env
    );

    const stateChanged: boolean = result.state !== this.currentState;
    this.currentState = result.state;

    if (stateChanged) {
      for (let i = 0; i < this.listeners.length; i++) {
        this.listeners[i](this.currentState);
      }
    }

    if (result.effects !== undefined && result.effects.length > 0) {
      for (let i = 0; i < result.effects.length; i++) {
        this.executeEffect(result.effects[i]);
      }
    }
  }

  private handleIncomingEvent(event: TdRoutedEvent): void {
    const recaptchaInfo = parseRecaptchaUpdateFromWire(event.payload);
    if (recaptchaInfo !== null) {
      hilog.info(DOMAIN, TAG, 'recaptcha required: verificationId=%{public}d action=%{public}s keyId=%{public}s',
        recaptchaInfo.verificationId, recaptchaInfo.action, recaptchaInfo.recaptchaKeyId);
      this.dispatch(new OnRecaptchaRequired(
        recaptchaInfo.verificationId, recaptchaInfo.action, recaptchaInfo.recaptchaKeyId));
      return;
    }

    const authEvent: AuthEvent | null = parseAuthEventFromWire(event.payload);
    if (authEvent === null) {
      return;
    }

    // 驱动 core/account 的底层状态机
    const authResult: AuthReducerResult = authReducer(
      this.scope.authorization,
      authEvent,
      { accountId: this.scope.accountId }
    );
    this.scope.authorizationHolder.replace(authResult.state);

    // 执行 core/account auth effects（setTdlibParameters / checkDbKey 等）
    if (authResult.effects !== undefined && authResult.effects.length > 0) {
      for (let i = 0; i < authResult.effects.length; i++) {
        this.executeCoreAuthEffect(authResult.effects[i]);
      }
    }

    // 同步到 UI 状态
    this.dispatch(new OnAuthStateChanged(authResult.state));
  }

  /**
   * 补发当前授权状态对应的 core effect。
   * 处理 start() 前 TDLib 已 emit 但被丢弃的初始事件（setTdlibParameters / checkDbKey）。
   */
  private executeCoreEffectsForState(authState: AuthState): void {
    switch (authState.kind) {
      case 'waitParams':
        this.executeCoreAuthEffect({ kind: 'setTdlibParameters' });
        break;
      case 'waitDbKey':
        this.executeCoreAuthEffect({ kind: 'checkDbKey' });
        break;
      default:
        break;
    }
  }

  private executeCoreAuthEffect(effect: CoreAuthEffect): void {
    switch (effect.kind) {
      case 'setTdlibParameters': {
        if (this.tdlibParamsSent) {
          hilog.info(DOMAIN, TAG, 'setTdlibParameters already sent, skipping');
          break;
        }
        this.tdlibParamsSent = true;
        hilog.info(DOMAIN, TAG, 'executing setTdlibParameters');
        const params: TdWireObject = buildSetTdlibParametersParams(this.tdlibParameters);
        this.scope.request('setTdlibParameters', params).then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            hilog.error(DOMAIN, TAG, 'setTdlibParameters failed: %{public}s %{public}s', res.error.kind, res.error.message);
            this.dispatch(new OnRequestError(res.error));
          } else {
            hilog.info(DOMAIN, TAG, 'setTdlibParameters succeeded');
          }
        });
        break;
      }
      case 'checkDbKey': {
        if (this.dbKeySent) {
          hilog.info(DOMAIN, TAG, 'checkDbKey already sent, skipping');
          break;
        }
        this.dbKeySent = true;
        hilog.info(DOMAIN, TAG, 'executing checkDatabaseEncryptionKey');
        const json: string = '{"@type":"checkDatabaseEncryptionKey","encryption_key":""}';
        const parsed: Object = JSON.parse(json);
        this.scope.request('checkDatabaseEncryptionKey', parsed as TdWireObject).then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            hilog.error(DOMAIN, TAG, 'checkDbKey failed: %{public}s %{public}s', res.error.kind, res.error.message);
            this.dispatch(new OnRequestError(res.error));
          } else {
            hilog.info(DOMAIN, TAG, 'checkDbKey succeeded');
          }
        });
        break;
      }
      case 'none':
        break;
      default:
        break;
    }
  }

  private executeEffect(effect: AuthEffect): void {
    switch (effect.kind) {
      case 'sendPhoneNumber': {
        const params: TdWireObject = wireParam1('phone_number', effect.phoneNumber);
        hilog.info(DOMAIN, TAG, 'executing setAuthenticationPhoneNumber');
        this.scope.request('setAuthenticationPhoneNumber', params).then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            hilog.error(DOMAIN, TAG, 'setAuthenticationPhoneNumber failed: %{public}s %{public}s %{public}s',
              res.error.kind, res.error.message, res.error.cause ?? '');
            this.dispatch(new OnRequestError(res.error));
          } else {
            hilog.info(DOMAIN, TAG, 'setAuthenticationPhoneNumber succeeded');
          }
        });
        break;
      }

      case 'checkCode': {
        const params: TdWireObject = wireParam1('code', effect.code);
        hilog.info(DOMAIN, TAG, 'executing checkAuthenticationCode');
        this.scope.request('checkAuthenticationCode', params).then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            hilog.error(DOMAIN, TAG, 'checkAuthenticationCode failed: %{public}s %{public}s %{public}s',
              res.error.kind, res.error.message, res.error.cause ?? '');
            this.dispatch(new OnRequestError(res.error));
          } else {
            hilog.info(DOMAIN, TAG, 'checkAuthenticationCode succeeded');
          }
        });
        break;
      }

      case 'resendCode': {
        this.scope.request('resendAuthenticationCode').then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            this.dispatch(new OnRequestError(res.error));
          }
        });
        break;
      }

      case 'checkPassword': {
        const params: TdWireObject = wireParam1('password', effect.password);
        this.scope.request('checkAuthenticationPassword', params).then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            this.dispatch(new OnRequestError(res.error));
          }
        });
        break;
      }

      case 'registerUser': {
        const params: TdWireObject = wireParam2('first_name', effect.firstName, 'last_name', effect.lastName);
        this.scope.request('registerUser', params).then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            this.dispatch(new OnRequestError(res.error));
          }
        });
        break;
      }

      case 'startCountdown': {
        this.startCountdownTimer();
        break;
      }

      case 'stopCountdown': {
        this.stopCountdownTimer();
        break;
      }

      case 'navigateToRoute': {
        if (this.onNavigate !== undefined) {
          this.onNavigate(effect.routeName);
        }
        break;
      }

      case 'showToast': {
        if (this.onToast !== undefined) {
          this.onToast(effect.messageKey);
        }
        break;
      }

      case 'sendVerificationToken': {
        const params: Record<string, Object> = {};
        params['verification_id'] = effect.verificationId;
        params['token'] = effect.token;
        hilog.info(DOMAIN, TAG, 'executing setApplicationVerificationToken verificationId=%{public}d', effect.verificationId);
        this.scope.request('setApplicationVerificationToken', params as TdWireObject).then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            hilog.error(DOMAIN, TAG, 'setApplicationVerificationToken failed: %{public}s %{public}s %{public}s',
              res.error.kind, res.error.message, res.error.cause ?? '');
            this.dispatch(new OnRequestError(res.error));
          } else {
            hilog.info(DOMAIN, TAG, 'setApplicationVerificationToken succeeded — waiting for auth state update');
          }
        });
        break;
      }
    }
  }

  private startCountdownTimer(): void {
    this.stopCountdownTimer();
    this.countdownTimerId = setInterval(() => {
      this.dispatch(new CountdownTick());
    }, 1000);
  }

  private stopCountdownTimer(): void {
    if (this.countdownTimerId !== null) {
      clearInterval(this.countdownTimerId);
      this.countdownTimerId = null;
    }
  }
}
