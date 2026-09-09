import { describe, it, expect } from '@ohos/hypium';
import {
  AppError,
  AppErrors,
  ManualClock,
  Result,
  SequentialIdGenerator,
  ok
} from '@tgx/core-common';
import {
  AuthState,
  AuthorizationStateHolder
} from '@tgx/core-account';
import { ReducerEnv } from '@tgx/feature-template';
import { TdRoutedEvent, TdWireObject } from '@tgx/td-gateway';
import { AuthUiState } from '../main/ets/contract/AuthUiState';
import {
  ChangePhoneInput,
  SubmitPhone,
  ChangePasswordInput,
  SubmitPassword,
  RequestQrCodeLogin
} from '../main/ets/contract/AuthIntent';
import {
  AuthAccountScopeLike,
  AuthCoordinator,
  AuthSubscriptionLike,
  TdlibParametersConfig
} from '../main/ets/coordinator/AuthCoordinator';

function wireJson(json: string): TdWireObject {
  const parsed: Object = JSON.parse(json);
  return parsed as TdWireObject;
}

interface RecordedRequest {
  readonly method: string;
  readonly params?: TdWireObject;
}

class SimpleSubscription implements AuthSubscriptionLike {
  private readonly onUnsub: () => void;

  constructor(onUnsub: () => void) {
    this.onUnsub = onUnsub;
  }

  unsubscribe(): void {
    this.onUnsub();
  }
}

class TestRoutedEvent implements TdRoutedEvent {
  readonly clientId: number;
  readonly sequence: string;
  readonly type: string;
  readonly payload: TdWireObject;

  constructor(clientId: number, sequence: string, type: string, payload: TdWireObject) {
    this.clientId = clientId;
    this.sequence = sequence;
    this.type = type;
    this.payload = payload;
  }
}

class FakeAuthAccountScope implements AuthAccountScopeLike {
  readonly accountId: string = 'test-acc-1';
  readonly authorizationHolder: AuthorizationStateHolder = new AuthorizationStateHolder();
  readonly requests: RecordedRequest[] = [];
  readonly eventListeners: Array<(event: TdRoutedEvent) => void> = [];

  get authorization(): AuthState {
    return this.authorizationHolder.current;
  }

  request(method: string, params?: TdWireObject): Promise<Result<TdWireObject, AppError>> {
    this.requests.push({ method: method, params: params });
    const emptyOk: TdWireObject = wireJson('{"@type":"ok"}');
    return Promise.resolve(ok(emptyOk));
  }

  subscribeEvents(listener: (event: TdRoutedEvent) => void): AuthSubscriptionLike {
    this.eventListeners.push(listener);
    return new SimpleSubscription(() => {
      const idx: number = this.eventListeners.indexOf(listener);
      if (idx >= 0) {
        this.eventListeners.splice(idx, 1);
      }
    });
  }

  emitEvent(payload: TdWireObject): void {
    const routed: TdRoutedEvent = new TestRoutedEvent(
      1,
      '1',
      'updateAuthorizationState',
      payload
    );
    for (let i = 0; i < this.eventListeners.length; i++) {
      this.eventListeners[i](routed);
    }
  }
}

function makeEnv(): ReducerEnv {
  return {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('coord-test-')
  };
}

function makeTdlibParameters(): TdlibParametersConfig {
  return {
    apiId: 1,
    apiHash: 'test-hash',
    databaseDirectory: '/tmp/test-db',
    filesDirectory: '/tmp/test-files',
    systemLanguageCode: 'en',
    deviceModel: 'test-device',
    applicationVersion: '0.1.0',
    useTestDc: true
  };
}

function makeCoordinator(scope: FakeAuthAccountScope): AuthCoordinator {
  return new AuthCoordinator({ scope, env: makeEnv(), tdlibParameters: makeTdlibParameters() });
}

export default function authCoordinatorTest(): void {
  describe('AuthCoordinatorTest', () => {
    it('start_syncsInitialStateAndSubscribes', 0, () => {
      const scope = new FakeAuthAccountScope();
      const coord = makeCoordinator(scope);
      coord.start();

      expect(scope.eventListeners.length).assertEqual(1);
      expect(coord.state.step).assertEqual('waitParams');
      coord.destroy();
      expect(scope.eventListeners.length).assertEqual(0);
    });

    it('dispatch_submitPhone_sendsRequestToScope', 0, () => {
      const scope = new FakeAuthAccountScope();
      const coord = makeCoordinator(scope);

      coord.dispatch(new ChangePhoneInput('13800138000'));
      coord.dispatch(new SubmitPhone());

      expect(scope.requests.length).assertEqual(1);
      expect(scope.requests[0].method).assertEqual('setAuthenticationPhoneNumber');
      expect(scope.requests[0].params !== undefined).assertTrue();
      if (scope.requests[0].params !== undefined) {
        expect(scope.requests[0].params['phone_number']).assertEqual('+8613800138000');
      }

      coord.destroy();
    });

    it('incomingEvent_waitCode_transitionsUiState', 0, () => {
      const scope = new FakeAuthAccountScope();
      const coord = makeCoordinator(scope);
      coord.start();

      const updatePayload: TdWireObject = wireJson(
        '{"@type":"updateAuthorizationState","authorization_state":{"@type":"authorizationStateWaitCode","code_info":{"@type":"authenticationCodeInfo","phone_number":"+8613800138000","type":{"@type":"authenticationCodeTypeSms","length":6},"timeout":60}}}'
      );

      scope.emitEvent(updatePayload);

      expect(coord.state.step).assertEqual('waitCode');
      expect(coord.state.codeLength).assertEqual(6);
      expect(scope.authorization.kind).assertEqual('waitCode');

      coord.destroy();
    });

    it('incomingEvent_waitPassword_transitions2faAndSubmits', 0, () => {
      const scope = new FakeAuthAccountScope();
      const coord = makeCoordinator(scope);
      coord.start();

      const updatePayload: TdWireObject = wireJson(
        '{"@type":"updateAuthorizationState","authorization_state":{"@type":"authorizationStateWaitPassword","password_hint":"my hint","has_recovery_email_address":false}}'
      );

      scope.emitEvent(updatePayload);

      expect(coord.state.step).assertEqual('wait2fa');
      expect(coord.state.passwordHint).assertEqual('my hint');

      coord.dispatch(new ChangePasswordInput('pwd123'));
      coord.dispatch(new SubmitPassword());

      expect(scope.requests.length).assertEqual(2);
      expect(scope.requests[1].method).assertEqual('checkAuthenticationPassword');
      if (scope.requests[1].params !== undefined) {
        expect(scope.requests[1].params['password']).assertEqual('pwd123');
      }

      coord.destroy();
    });

    it('listener_receivesStateUpdates_andUnsubscribes', 0, () => {
      const scope = new FakeAuthAccountScope();
      const coord = makeCoordinator(scope);
      const captured: AuthUiState[] = [];

      const unsub = coord.subscribe((s: AuthUiState) => {
        captured.push(s);
      });

      expect(captured.length).assertEqual(1); // 初始同步

      coord.dispatch(new ChangePhoneInput('123'));
      expect(captured.length).assertEqual(2);

      unsub();
      coord.dispatch(new ChangePhoneInput('12345'));
      expect(captured.length).assertEqual(2); // 不再接收更新

      coord.destroy();
    });

    it('requestQrCodeLogin_sendsTdlibRequestAndDisplaysUpdates', 0, () => {
      const scope = new FakeAuthAccountScope();
      const coord = makeCoordinator(scope);
      coord.start();

      coord.dispatch(new RequestQrCodeLogin());
      expect(scope.requests.length).assertEqual(2);
      expect(scope.requests[1].method).assertEqual('requestQrCodeAuthentication');

      const updatePayload: TdWireObject = wireJson(
        '{"@type":"updateAuthorizationState","authorization_state":{"@type":"authorizationStateWaitOtherDeviceConfirmation","link":"tg://login?token=test-token"}}'
      );
      scope.emitEvent(updatePayload);

      expect(coord.state.step).assertEqual('waitQrCode');
      expect(coord.state.qrCodeLink).assertEqual('tg://login?token=test-token');
      coord.destroy();
    });

    it('incomingRecaptcha_reportsFailureToReleasePendingRequest', 0, () => {
      const scope = new FakeAuthAccountScope();
      const coord = makeCoordinator(scope);
      coord.start();

      const updatePayload: TdWireObject = wireJson(
        '{"@type":"updateApplicationRecaptchaVerificationRequired","verification_id":77,"action":"login","recaptcha_key_id":"mobile-key"}'
      );
      scope.emitEvent(updatePayload);

      expect(coord.state.step).assertEqual('waitRecaptcha');
      expect(scope.requests.length).assertEqual(2);
      expect(scope.requests[1].method).assertEqual('setApplicationVerificationToken');
      if (scope.requests[1].params !== undefined) {
        expect(scope.requests[1].params['verification_id']).assertEqual(77);
        expect(scope.requests[1].params['token']).assertEqual('');
      }
      coord.destroy();
    });
  });
}
