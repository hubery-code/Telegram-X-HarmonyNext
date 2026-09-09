/**
 * AuthorizationStateMachine 全分支 fixture 单测（CORE-005）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppErrors } from '@tgx/core-common';
import {
  AuthState,
  AuthEvent,
  AuthReducerResult,
  AuthCodeInfo,
  authReducer,
  AuthorizationStateMachine,
  INITIAL_AUTH_STATE,
  AuthReducerDeps
} from '../main/ets/AuthorizationState';

function deps(): AuthReducerDeps {
  return { accountId: 'test-account-1' };
}

function reduce(state: AuthState, event: AuthEvent): AuthReducerResult {
  return authReducer(state, event, deps());
}

function codeInfo(overrides?: Partial<AuthCodeInfo>): AuthCodeInfo {
  const base: AuthCodeInfo = {
    phoneNumber: '+8613800138000',
    codeType: 'authenticationCodeTypeSms',
    length: 5,
    timeout: 60,
  };
  if (!overrides) {
    return base;
  }
  return {
    phoneNumber: overrides.phoneNumber ?? base.phoneNumber,
    codeType: overrides.codeType ?? base.codeType,
    length: overrides.length ?? base.length,
    timeout: overrides.timeout ?? base.timeout,
  };
}

function stWaitParams(): AuthState { return { kind: 'waitParams' }; }
function stWaitDbKey(dataDir: string): AuthState { return { kind: 'waitDbKey', dataDir }; }
function stWaitPhone(): AuthState { return { kind: 'waitPhone', loginType: 'phone' }; }
function stWaitCode(phoneOrEmail: string): AuthState {
  return { kind: 'waitCode', phoneOrEmail, resendTimeoutMs: 60000, codeLength: 5 };
}
function stWait2fa(): AuthState {
  return { kind: 'wait2fa', passwordHint: '', hasRecoveryEmail: false, recoveryEmailPattern: '' };
}
function stWaitRegistration(): AuthState { return { kind: 'waitRegistration' }; }
function stReady(): AuthState { return { kind: 'ready' }; }
function stLoggingOut(): AuthState { return { kind: 'loggingOut' }; }
function stClosing(): AuthState { return { kind: 'closing' }; }
function stClosed(): AuthState { return { kind: 'closed' }; }
function stFailed(): AuthState { return { kind: 'failed', error: AppErrors.internal('test-failed') }; }

function evWaitParams(): AuthEvent { return { type: 'authorizationStateWaitTdlibParameters' }; }
function evWaitEncryptionKey(isEncrypted: boolean): AuthEvent {
  return { type: 'authorizationStateWaitEncryptionKey', isEncrypted };
}
function evWaitPhoneNumber(): AuthEvent { return { type: 'authorizationStateWaitPhoneNumber' }; }
function evWaitEmailAddress(): AuthEvent { return { type: 'authorizationStateWaitEmailAddress' }; }
function evWaitOtherDeviceConfirmation(): AuthEvent {
  return { type: 'authorizationStateWaitOtherDeviceConfirmation' };
}
function evWaitCode(ci: AuthCodeInfo): AuthEvent { return { type: 'authorizationStateWaitCode', codeInfo: ci }; }
function evWaitPassword(passwordHint: string, hasRecovery: boolean, recoveryPattern: string): AuthEvent {
  return {
    type: 'authorizationStateWaitPassword',
    passwordHint,
    hasRecoveryEmailAddress: hasRecovery,
    recoveryEmailAddressPattern: recoveryPattern,
  };
}
function evWaitRegistration(): AuthEvent { return { type: 'authorizationStateWaitRegistration' }; }
function evReady(): AuthEvent { return { type: 'authorizationStateReady' }; }
function evLoggingOut(): AuthEvent { return { type: 'authorizationStateLoggingOut' }; }
function evClosing(): AuthEvent { return { type: 'authorizationStateClosing' }; }
function evClosed(): AuthEvent { return { type: 'authorizationStateClosed' }; }

function hasEffectKind(result: AuthReducerResult, kind: string): boolean {
  for (const e of result.effects) {
    if (e.kind === kind) {
      return true;
    }
  }
  return false;
}

export default function authorizationStateMachineTest() {
  describe('AuthorizationStateMachineTest', () => {

    it('initialState_isWaitParams', 0, () => {
      const machine: AuthorizationStateMachine = AuthorizationStateMachine.create('acc-1');
      expect(machine.state.kind).assertEqual('waitParams');
      expect(INITIAL_AUTH_STATE.kind).assertEqual('waitParams');
    });

    it('stateMachine_applyReturnsNewInstance', 0, () => {
      const m1: AuthorizationStateMachine = AuthorizationStateMachine.create('acc-1');
      const m2: AuthorizationStateMachine = m1.apply(evWaitPhoneNumber());
      expect(m2.state.kind).assertEqual('waitPhone');
      expect(m1.state.kind).assertEqual('waitParams');
    });

    it('waitParams_to_waitDbKey_onEncryptionKey', 0, () => {
      const result: AuthReducerResult = reduce(stWaitParams(), evWaitEncryptionKey(false));
      expect(result.state.kind).assertEqual('waitDbKey');
      expect(hasEffectKind(result, 'checkDbKey')).assertTrue();
      expect(result.effects.length).assertEqual(1);
    });

    it('waitDbKey_to_waitPhone_onWaitPhoneNumber', 0, () => {
      const result: AuthReducerResult = reduce(stWaitDbKey('/db'), evWaitPhoneNumber());
      expect(result.state.kind).assertEqual('waitPhone');
      expect(hasEffectKind(result, 'sendPhoneNumber')).assertTrue();
    });

    it('waitPhone_to_waitCode_onWaitCode', 0, () => {
      const result: AuthReducerResult = reduce(stWaitPhone(), evWaitCode(codeInfo()));
      expect(result.state.kind).assertEqual('waitCode');
      expect(hasEffectKind(result, 'sendCode')).assertTrue();
    });

    it('waitCode_contextPreserved', 0, () => {
      const result: AuthReducerResult = reduce(stWaitPhone(), evWaitCode(codeInfo({ phoneNumber: '+861', length: 6, timeout: 120 })));
      expect(result.state.kind).assertEqual('waitCode');
      if (result.state.kind === 'waitCode') {
        expect(result.state.phoneOrEmail).assertEqual('+861');
        expect(result.state.codeLength).assertEqual(6);
      }
    });

    it('waitCode_to_ready_onReady', 0, () => {
      const result: AuthReducerResult = reduce(stWaitCode('+861'), evReady());
      expect(result.state.kind).assertEqual('ready');
    });

    it('wait2fa_to_ready_onReady', 0, () => {
      const result: AuthReducerResult = reduce(stWait2fa(), evReady());
      expect(result.state.kind).assertEqual('ready');
    });

    it('waitRegistration_to_ready_onReady', 0, () => {
      const result: AuthReducerResult = reduce(stWaitRegistration(), evReady());
      expect(result.state.kind).assertEqual('ready');
    });

    it('ready_to_loggingOut_onLoggingOut', 0, () => {
      const result: AuthReducerResult = reduce(stReady(), evLoggingOut());
      expect(result.state.kind).assertEqual('loggingOut');
    });

    it('loggingOut_to_closing_onClosing', 0, () => {
      const result: AuthReducerResult = reduce(stLoggingOut(), evClosing());
      expect(result.state.kind).assertEqual('closing');
    });

    it('closing_to_closed_onClosed', 0, () => {
      const result: AuthReducerResult = reduce(stClosing(), evClosed());
      expect(result.state.kind).assertEqual('closed');
    });

    it('closed_absorbsAnyEvent', 0, () => {
      const events: AuthEvent[] = [evReady(), evWaitPhoneNumber(), evWaitCode(codeInfo()), evClosed()];
      for (const event of events) {
        const result: AuthReducerResult = reduce(stClosed(), event);
        expect(result.state.kind).assertEqual('closed');
        expect(hasEffectKind(result, 'none')).assertTrue();
      }
    });

    it('waitPhone_to_wait2fa_onWaitPassword', 0, () => {
      const result: AuthReducerResult = reduce(stWaitPhone(), evWaitPassword('hint', true, 'p@t.com'));
      expect(result.state.kind).assertEqual('wait2fa');
      if (result.state.kind === 'wait2fa') {
        expect(result.state.passwordHint).assertEqual('hint');
        expect(result.state.hasRecoveryEmail).assertEqual(true);
      }
    });

    it('wait2fa_passwordHintMayBeEmpty', 0, () => {
      const result: AuthReducerResult = reduce(stWaitPhone(), evWaitPassword('', false, ''));
      expect(result.state.kind).assertEqual('wait2fa');
      if (result.state.kind === 'wait2fa') {
        expect(result.state.passwordHint).assertEqual('');
      }
    });

    it('waitParams_to_waitPhone_onWaitEmailAddress', 0, () => {
      const result: AuthReducerResult = reduce(stWaitParams(), evWaitEmailAddress());
      expect(result.state.kind).assertEqual('waitPhone');
      if (result.state.kind === 'waitPhone') {
        expect(result.state.loginType).assertEqual('email');
      }
    });

    it('waitParams_to_waitPhone_onWaitOtherDeviceConfirmation', 0, () => {
      const result: AuthReducerResult = reduce(stWaitParams(), evWaitOtherDeviceConfirmation());
      expect(result.state.kind).assertEqual('waitPhone');
      if (result.state.kind === 'waitPhone') {
        expect(result.state.loginType).assertEqual('qr');
      }
    });

    it('waitDbKey_repeatedEncryptionKey_staysWaitDbKey', 0, () => {
      const result: AuthReducerResult = reduce(stWaitDbKey('/db'), evWaitEncryptionKey(true));
      expect(result.state.kind).assertEqual('waitDbKey');
      if (result.state.kind === 'waitDbKey') {
        expect(result.state.dataDir).assertEqual('/accounts/test-account-1/tdlib/db');
      }
    });

    it('ready_staysReady_onRepeatedReady', 0, () => {
      const result: AuthReducerResult = reduce(stReady(), evReady());
      expect(result.state.kind).assertEqual('ready');
    });

    it('waitParams_to_waitCode_onWaitCode', 0, () => {
      const result: AuthReducerResult = reduce(stWaitParams(), evWaitCode(codeInfo()));
      expect(result.state.kind).assertEqual('waitCode');
    });

    it('waitCode_to_waitPhone_onWaitPhoneNumber', 0, () => {
      const result: AuthReducerResult = reduce(stWaitCode('+861'), evWaitPhoneNumber());
      expect(result.state.kind).assertEqual('waitPhone');
    });

    it('reducer_isPure_sameInputSameOutput', 0, () => {
      const state: AuthState = stWaitParams();
      const event: AuthEvent = evWaitCode(codeInfo());
      const r1: AuthReducerResult = authReducer(state, event, deps());
      const r2: AuthReducerResult = authReducer(state, event, deps());
      expect(r1.state.kind).assertEqual(r2.state.kind);
    });

    it('reducer_doesNotMutateInputState', 0, () => {
      const state: AuthState = stWaitCode('+8613800138000');
      authReducer(state, evReady(), deps());
      expect(state.kind).assertEqual('waitCode');
      if (state.kind === 'waitCode') {
        expect(state.phoneOrEmail).assertEqual('+8613800138000');
      }
    });

    it('failedState_staysFailed_onAnyEvent', 0, () => {
      const result: AuthReducerResult = reduce(stFailed(), evReady());
      expect(result.state.kind).assertEqual('failed');
    });

    it('wait2fa_withLongPasswordHint_stillAccepted', 0, () => {
      const longHint: string = 'a'.repeat(200);
      const result: AuthReducerResult = reduce(stWaitPhone(), evWaitPassword(longHint, false, ''));
      expect(result.state.kind).assertEqual('wait2fa');
      if (result.state.kind === 'wait2fa') {
        expect(result.state.passwordHint.length).assertEqual(200);
      }
    });

    it('allKnownEvents_fromAnyState_neverFail', 0, () => {
      const states: AuthState[] = [
        stWaitParams(), stWaitDbKey('/db'), stWaitPhone(), stWaitCode('+86'),
        stWait2fa(), stWaitRegistration(), stReady(), stLoggingOut(), stClosing(),
      ];
      const events: AuthEvent[] = [
        evWaitParams(), evWaitEncryptionKey(false), evWaitPhoneNumber(), evWaitEmailAddress(),
        evWaitOtherDeviceConfirmation(), evWaitCode(codeInfo()), evWaitPassword('hint', false, ''),
        evWaitRegistration(), evReady(), evLoggingOut(), evClosing(), evClosed(),
      ];
      for (const state of states) {
        for (const event of events) {
          const result: AuthReducerResult = reduce(state, event);
          expect(result.state.kind === 'failed').assertEqual(false);
        }
      }
    });

    it('holder_createThenApply_updatesState', 0, () => {
      const holder: AuthorizationStateMachine = AuthorizationStateMachine.create('acc-1');
      expect(holder.state.kind).assertEqual('waitParams');
      const next: AuthorizationStateMachine = holder.apply(evWaitPhoneNumber());
      expect(next.state.kind).assertEqual('waitPhone');
    });

    it('waitCode_codeLengthZero_accepted', 0, () => {
      const info: AuthCodeInfo = codeInfo({ length: 0, timeout: 0 });
      const result: AuthReducerResult = reduce(stWaitPhone(), evWaitCode(info));
      expect(result.state.kind).assertEqual('waitCode');
      if (result.state.kind === 'waitCode') {
        expect(result.state.codeLength).assertEqual(0);
        expect(result.state.resendTimeoutMs).assertEqual(0);
      }
    });

    it('ready_to_loggingOut_then_closing_then_closed', 0, () => {
      const r1: AuthReducerResult = reduce(stReady(), evLoggingOut());
      expect(r1.state.kind).assertEqual('loggingOut');
      const r2: AuthReducerResult = reduce(r1.state, evClosing());
      expect(r2.state.kind).assertEqual('closing');
      const r3: AuthReducerResult = reduce(r2.state, evClosed());
      expect(r3.state.kind).assertEqual('closed');
    });

    it('wait2fa_to_waitCode_onWaitCode', 0, () => {
      const result: AuthReducerResult = reduce(stWait2fa(), evWaitCode(codeInfo()));
      expect(result.state.kind).assertEqual('waitCode');
    });

    it('waitRegistration_to_waitPhone_onWaitPhoneNumber', 0, () => {
      const result: AuthReducerResult = reduce(stWaitRegistration(), evWaitPhoneNumber());
      expect(result.state.kind).assertEqual('waitPhone');
    });

    it('waitParams_to_ready_onReady', 0, () => {
      const result: AuthReducerResult = reduce(stWaitParams(), evReady());
      expect(result.state.kind).assertEqual('ready');
    });

    it('waitDbKey_to_waitDbKey_onEncryptionKeyTrue_emitsCheckDbKey', 0, () => {
      const result: AuthReducerResult = reduce(stWaitDbKey('/db'), evWaitEncryptionKey(true));
      expect(result.state.kind).assertEqual('waitDbKey');
      expect(hasEffectKind(result, 'checkDbKey')).assertTrue();
    });

    it('waitParams_onEncryptionKeyFalse_emitsCheckDbKey', 0, () => {
      const result: AuthReducerResult = reduce(stWaitParams(), evWaitEncryptionKey(false));
      expect(result.state.kind).assertEqual('waitDbKey');
      expect(hasEffectKind(result, 'checkDbKey')).assertTrue();
    });

    it('authorizationStateHolder_replace_changesCurrent', 0, () => {
      const holder: AuthorizationStateMachine = AuthorizationStateMachine.create('acc-1');
      expect(holder.state.kind).assertEqual('waitParams');
      const next: AuthorizationStateMachine = holder.apply(evWaitPhoneNumber());
      expect(next.state.kind).assertEqual('waitPhone');
    });

    it('waitPhone_to_waitCode_emailCodeInfo', 0, () => {
      const info: AuthCodeInfo = codeInfo({ phoneNumber: 'user@example.com', codeType: 'authenticationCodeTypeEmail' });
      const result: AuthReducerResult = reduce(stWaitPhone(), evWaitCode(info));
      expect(result.state.kind).assertEqual('waitCode');
      if (result.state.kind === 'waitCode') {
        expect(result.state.phoneOrEmail).assertEqual('user@example.com');
      }
    });

    it('waitCode_to_wait2fa_onWaitPassword', 0, () => {
      const result: AuthReducerResult = reduce(stWaitCode('+86'), evWaitPassword('my hint', false, ''));
      expect(result.state.kind).assertEqual('wait2fa');
    });

    it('waitParams_to_waitPhone_onWaitPhoneNumber', 0, () => {
      const result: AuthReducerResult = reduce(stWaitParams(), evWaitPhoneNumber());
      expect(result.state.kind).assertEqual('waitPhone');
      if (result.state.kind === 'waitPhone') {
        expect(result.state.loginType).assertEqual('phone');
      }
    });
  });
}
