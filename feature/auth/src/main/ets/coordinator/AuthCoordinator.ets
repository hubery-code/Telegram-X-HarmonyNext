/**
 * feature/auth — 登录协调器（AUTH-001）。
 *
 * 桥接 core/account 的 AccountScope 与 feature/auth 的 AuthReducer：
 * - 接收 UI Intent 并经 authReducer 驱动状态更新
 * - 执行 AuthEffect（向 AccountScope 发起 TDLib 请求）
 * - 订阅 AccountScope 的事件流，解析 updateAuthorizationState 并驱动内部状态
 */

import { AppError, AppErrors, Result, TdlibAppError, err } from '@tgx/core-common';
import { Logger } from '@tgx/observability';
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
  OnRecaptchaRequired,
  OnQrCodeLinkReceived
} from '../contract/AuthIntent';
import { AuthEffect } from '../contract/AuthEffect';
import { authReducer as authFeatureReducer } from '../reducer/AuthReducer';
import {
  parseAuthEventFromWire,
  parseQrCodeLinkFromWire,
  parseRecaptchaUpdateFromWire
} from './AuthEventParser';

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
  /** 获取 Base64 编码的 TDLib 数据库加密密钥（DATA-001）。 */
  getDatabaseEncryptionKeyBase64?(): Promise<Result<string, AppError>>;
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
  readonly logger?: Logger;
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

function buildSetTdlibParametersParams(
  config: TdlibParametersConfig,
  databaseEncryptionKey: string = ''
): TdWireObject {
  const obj: Record<string, Object> = {};
  obj['database_directory'] = config.databaseDirectory;
  obj['files_directory'] = config.filesDirectory;
  obj['database_encryption_key'] = databaseEncryptionKey;
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

function buildSetDatabaseEncryptionKeyParams(newEncryptionKey: string): TdWireObject {
  const obj: Record<string, Object> = {};
  obj['new_encryption_key'] = newEncryptionKey;
  const json: string = JSON.stringify(obj);
  const parsed: Object = JSON.parse(json);
  return parsed as TdWireObject;
}

function isDatabaseKeyError(error: AppError): boolean {
  if (error.kind === 'tdlib') {
    const tdErr: TdlibAppError = error as TdlibAppError;
    if (tdErr.code === 'unauthorized') {
      return true;
    }
  }
  const msg: string = error.message.toLowerCase();
  const cause: string = (error.cause !== undefined && error.cause !== null ? error.cause : '').toLowerCase();
  return msg.indexOf('401') >= 0 || msg.indexOf('encryption') >= 0 || cause.indexOf('401') >= 0 || cause.indexOf('encryption') >= 0;
}

export class AuthCoordinator {
  private readonly scope: AuthAccountScopeLike;
  private readonly env: ReducerEnv;
  private readonly tdlibParameters: TdlibParametersConfig;
  private readonly onNavigate?: (route: string) => void;
  private readonly onToast?: (message: string) => void;
  private readonly logger: Logger;

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
    this.logger = deps.logger !== undefined ? deps.logger : new Logger();
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
      this.logger.info(TAG, 'recaptcha_required', `verificationId=${recaptchaInfo.verificationId}`);
      this.dispatch(new OnRecaptchaRequired(
        recaptchaInfo.verificationId, recaptchaInfo.action, recaptchaInfo.recaptchaKeyId));
      return;
    }

    const qrCodeLink: string | null = parseQrCodeLinkFromWire(event.payload);
    if (qrCodeLink !== null) {
      this.logger.info(TAG, 'qr_authentication_link_updated');
      this.dispatch(new OnQrCodeLinkReceived(qrCodeLink));
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
          this.logger.info(TAG, 'set_tdlib_parameters_already_sent');
          break;
        }
        this.tdlibParamsSent = true;
        this.sendSetTdlibParameters();
        break;
      }
      case 'checkDbKey': {
        if (this.dbKeySent) {
          this.logger.info(TAG, 'check_db_key_already_sent');
          break;
        }
        this.dbKeySent = true;
        this.sendCheckDbKey();
        break;
      }
      case 'none':
        break;
      default:
        break;
    }
  }

  private sendSetTdlibParameters(): void {
    if (this.scope.getDatabaseEncryptionKeyBase64 === undefined) {
      this.doSendSetTdlibParameters('', false);
      return;
    }
    this.scope.getDatabaseEncryptionKeyBase64().then((res: Result<string, AppError>) => {
      const keyBase64: string = res.fold(
        (val: string): string => val,
        (error: AppError): string => {
          this.logger.logError(TAG, error);
          throw new Error(error.message);
        }
      );
      this.doSendSetTdlibParameters(keyBase64, true);
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.logger.error(TAG, 'send_set_tdlib_parameters_aborted');
      this.dispatch(new OnRequestError(AppErrors.platform(-1, `Failed to retrieve database encryption key: ${msg}`, true)));
    });
  }

  private doSendSetTdlibParameters(keyBase64: string, allowMigration: boolean): void {
    this.logger.info(TAG, 'executing_set_tdlib_parameters', `encrypted=${keyBase64.length > 0}`);
    const params: TdWireObject = buildSetTdlibParametersParams(this.tdlibParameters, keyBase64);
    this.scope.request('setTdlibParameters', params).then((res: Result<TdWireObject, AppError>) => {
      if (res.err) {
        this.logger.logError(TAG, res.error);
        if (allowMigration && keyBase64.length > 0 && isDatabaseKeyError(res.error)) {
          this.logger.info(TAG, 'legacy_database_migration_attempt');
          this.attemptLegacyDatabaseMigration(keyBase64, res.error);
          return;
        }
        this.dispatch(new OnRequestError(res.error));
      } else {
        this.logger.info(TAG, 'set_tdlib_parameters_succeeded');
      }
    });
  }

  private attemptLegacyDatabaseMigration(targetKeyBase64: string, originalError: AppError): void {
    const emptyKeyParams: TdWireObject = buildSetTdlibParametersParams(this.tdlibParameters, '');
    this.scope.request('setTdlibParameters', emptyKeyParams).then((emptyRes: Result<TdWireObject, AppError>) => {
      if (emptyRes.err) {
        this.logger.logError(TAG, emptyRes.error);
        this.dispatch(new OnRequestError(originalError));
        return;
      }

      this.logger.info(TAG, 'legacy_database_opened_with_empty_key');
      const migrateParams: TdWireObject = buildSetDatabaseEncryptionKeyParams(targetKeyBase64);
      this.scope.request('setDatabaseEncryptionKey', migrateParams).then((migrateRes: Result<TdWireObject, AppError>) => {
        if (migrateRes.err) {
          this.logger.logError(TAG, migrateRes.error);
          this.dispatch(new OnRequestError(migrateRes.error));
        } else {
          this.logger.info(TAG, 'database_migrated_to_huks');
        }
      });
    });
  }

  private sendCheckDbKey(): void {
    if (this.scope.getDatabaseEncryptionKeyBase64 === undefined) {
      this.doSendCheckDbKey('');
      return;
    }
    this.scope.getDatabaseEncryptionKeyBase64().then((res: Result<string, AppError>) => {
      const keyBase64: string = res.fold(
        (val: string): string => val,
        (error: AppError): string => {
          this.logger.logError(TAG, error);
          throw new Error(error.message);
        }
      );
      this.doSendCheckDbKey(keyBase64);
    }).catch((e: Object) => {
      const msg: string = e instanceof Error ? e.message : String(e);
      this.logger.error(TAG, 'send_check_db_key_aborted');
      this.dispatch(new OnRequestError(AppErrors.platform(-1, `Failed to retrieve db key: ${msg}`, true)));
    });
  }

  private doSendCheckDbKey(keyBase64: string): void {
    this.logger.info(TAG, 'executing_check_database_encryption_key');
    const obj: Record<string, Object> = {};
    obj['@type'] = 'checkDatabaseEncryptionKey';
    obj['encryption_key'] = keyBase64;
    const json: string = JSON.stringify(obj);
    const parsed: Object = JSON.parse(json);
    this.scope.request('checkDatabaseEncryptionKey', parsed as TdWireObject).then((res: Result<TdWireObject, AppError>) => {
      if (res.err) {
        this.logger.logError(TAG, res.error);
        this.dispatch(new OnRequestError(res.error));
      } else {
        this.logger.info(TAG, 'check_db_key_succeeded');
      }
    });
  }

  private executeEffect(effect: AuthEffect): void {
    switch (effect.kind) {
      case 'sendPhoneNumber': {
        const params: TdWireObject = wireParam1('phone_number', effect.phoneNumber);
        this.logger.info(TAG, 'executing_set_authentication_phone_number');
        this.scope.request('setAuthenticationPhoneNumber', params).then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            this.logger.logError(TAG, res.error);
            if (this.currentState.step === 'waitRecaptcha' || this.currentState.step === 'waitQrCode') {
              this.logger.info(TAG, 'phone_request_released_for_qr_fallback');
            } else {
              this.dispatch(new OnRequestError(res.error));
            }
          } else {
            this.logger.info(TAG, 'set_authentication_phone_number_succeeded');
          }
        });
        break;
      }

      case 'checkCode': {
        const params: TdWireObject = wireParam1('code', effect.code);
        this.logger.info(TAG, 'executing_check_authentication_code');
        this.scope.request('checkAuthenticationCode', params).then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            this.logger.logError(TAG, res.error);
            this.dispatch(new OnRequestError(res.error));
          } else {
            this.logger.info(TAG, 'check_authentication_code_succeeded');
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
        this.logger.info(TAG, 'executing_set_application_verification_token', `verificationId=${effect.verificationId}`);
        this.scope.request('setApplicationVerificationToken', params as TdWireObject).then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            this.logger.logError(TAG, res.error);
            if (effect.token.length > 0) {
              this.dispatch(new OnRequestError(res.error));
            }
          } else {
            this.logger.info(TAG, effect.token.length === 0
              ? 'unsupported_application_verification_reported'
              : 'set_application_verification_token_succeeded');
          }
        });
        break;
      }

      case 'requestQrCodeAuthentication': {
        const parsed: Object = JSON.parse('{"other_user_ids":[]}');
        this.logger.info(TAG, 'executing_request_qr_code_authentication');
        this.scope.request('requestQrCodeAuthentication', parsed as TdWireObject).then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            this.logger.logError(TAG, res.error);
            this.dispatch(new OnRequestError(res.error));
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
