import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator, AppErrors } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import {
  AuthState,
  AuthStateWaitPhone,
  AuthStateWaitCode,
  AuthStateWait2FA,
  AuthStateWaitRegistration,
  AuthStateReady,
  AuthStateFailed
} from '@tgx/core-account';
import { AuthUiState } from '../main/ets/contract/AuthUiState';
import {
  SelectCountry,
  ChangePhoneInput,
  SubmitPhone,
  ChangeCodeInput,
  SubmitCode,
  RequestResendCode,
  CountdownTick,
  ChangePasswordInput,
  TogglePasswordVisibility,
  SubmitPassword,
  ChangeFirstName,
  ChangeLastName,
  SubmitRegistration,
  OnAuthStateChanged,
  OnRequestError,
  ClearError,
  BackToPhone,
  OnRecaptchaRequired,
  RequestQrCodeLogin,
  OnQrCodeLinkReceived
} from '../main/ets/contract/AuthIntent';
import {
  SendPhoneNumber,
  CheckCode,
  ResendCode,
  CheckPassword,
  RegisterUser,
  NavigateToRoute,
  ShowToast,
  StartCountdown,
  StopCountdown,
  SendVerificationToken,
  RequestQrCodeAuthentication
} from '../main/ets/contract/AuthEffect';
import { authReducer } from '../main/ets/reducer/AuthReducer';

function makeEnv(): ReducerEnv {
  return {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('auth-test-')
  };
}

export default function authReducerTest(): void {
  describe('AuthReducerTest', () => {
    it('initialState_hasCorrectDefaults', 0, () => {
      const state: AuthUiState = AuthUiState.initial();
      expect(state.step).assertEqual('waitPhone');
      expect(state.countryCode).assertEqual('+86');
      expect(state.formattedPhone).assertEqual('+86');
      expect(state.isSubmitting).assertFalse();
      expect(state.errorMessage).assertNull();
      expect(state.canResendCode).assertFalse();
    });

    it('selectCountry_updatesCountryAndFormattedPhone', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({ rawPhone: '12345678' });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new SelectCountry('+1', 'United States'),
        makeEnv()
      );
      expect(res.state.countryCode).assertEqual('+1');
      expect(res.state.countryName).assertEqual('United States');
      expect(res.state.formattedPhone).assertEqual('+112345678');
      expect(res.effects.length).assertEqual(0);
    });

    it('changePhoneInput_updatesDigitsAndClearsError', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({
        errorMessage: 'error',
        errorCode: 'ERR'
      });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new ChangePhoneInput('138-0013-8000'),
        makeEnv()
      );
      expect(res.state.rawPhone).assertEqual('13800138000');
      expect(res.state.formattedPhone).assertEqual('+8613800138000');
      expect(res.state.errorMessage).assertNull();
      expect(res.state.errorCode).assertNull();
    });

    it('submitPhone_empty_setsError', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({ rawPhone: '' });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new SubmitPhone(),
        makeEnv()
      );
      expect(res.state.errorMessage).assertEqual('auth.error.phone_empty');
      expect(res.state.errorCode).assertEqual('VALIDATION_FAILED');
      expect(res.state.isSubmitting).assertFalse();
      expect(res.effects.length).assertEqual(0);
    });

    it('submitPhone_short_setsError', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({ rawPhone: '12' });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new SubmitPhone(),
        makeEnv()
      );
      expect(res.state.errorMessage).assertEqual('auth.error.phone_too_short');
      expect(res.state.isSubmitting).assertFalse();
      expect(res.effects.length).assertEqual(0);
    });

    it('submitPhone_valid_setsSubmittingAndEmitsEffect', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({
        rawPhone: '13800138000',
        formattedPhone: '+8613800138000'
      });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new SubmitPhone(),
        makeEnv()
      );
      expect(res.state.isSubmitting).assertTrue();
      expect(res.state.errorMessage).assertNull();
      expect(res.effects.length).assertEqual(1);
      const effect: SendPhoneNumber = res.effects[0] as SendPhoneNumber;
      expect(effect.kind).assertEqual('sendPhoneNumber');
      expect(effect.phoneNumber).assertEqual('+8613800138000');
    });

    it('changeCodeInput_partial_updatesCode', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({ codeLength: 5 });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new ChangeCodeInput('123'),
        makeEnv()
      );
      expect(res.state.code).assertEqual('123');
      expect(res.state.isSubmitting).assertFalse();
      expect(res.effects.length).assertEqual(0);
    });

    it('changeCodeInput_fullLength_autoSubmits', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({ codeLength: 5 });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new ChangeCodeInput('12345'),
        makeEnv()
      );
      expect(res.state.code).assertEqual('12345');
      expect(res.state.isSubmitting).assertTrue();
      expect(res.effects.length).assertEqual(1);
      const effect: CheckCode = res.effects[0] as CheckCode;
      expect(effect.kind).assertEqual('checkCode');
      expect(effect.code).assertEqual('12345');
    });

    it('submitCode_empty_setsError', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({ code: '' });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new SubmitCode(),
        makeEnv()
      );
      expect(res.state.errorMessage).assertEqual('auth.error.code_empty');
      expect(res.state.isSubmitting).assertFalse();
      expect(res.effects.length).assertEqual(0);
    });

    it('submitCode_valid_setsSubmittingAndEmitsEffect', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({ code: '98765' });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new SubmitCode(),
        makeEnv()
      );
      expect(res.state.isSubmitting).assertTrue();
      expect(res.effects.length).assertEqual(1);
      const effect: CheckCode = res.effects[0] as CheckCode;
      expect(effect.code).assertEqual('98765');
    });

    it('requestResendCode_whenNotAllowed_noOp', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({ canResendCode: false });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new RequestResendCode(),
        makeEnv()
      );
      expect(res.state === initial).assertTrue();
      expect(res.effects.length).assertEqual(0);
    });

    it('requestResendCode_whenAllowed_resetsTimerAndEmitsEffects', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({ canResendCode: true });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new RequestResendCode(),
        makeEnv()
      );
      expect(res.state.canResendCode).assertFalse();
      expect(res.state.resendTimeoutSeconds).assertEqual(60);
      expect(res.effects.length).assertEqual(2);
      expect((res.effects[0] as ResendCode).kind).assertEqual('resendCode');
      expect((res.effects[1] as StartCountdown).durationSeconds).assertEqual(60);
    });

    it('countdownTick_decrementsTimer', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({ resendTimeoutSeconds: 30 });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new CountdownTick(),
        makeEnv()
      );
      expect(res.state.resendTimeoutSeconds).assertEqual(29);
      expect(res.effects.length).assertEqual(0);
    });

    it('countdownTick_atZero_enablesResendAndEmitsStopCountdown', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({
        resendTimeoutSeconds: 1,
        canResendCode: false
      });
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        initial,
        new CountdownTick(),
        makeEnv()
      );
      expect(res.state.resendTimeoutSeconds).assertEqual(0);
      expect(res.state.canResendCode).assertTrue();
      expect(res.effects.length).assertEqual(1);
      expect((res.effects[0] as StopCountdown).kind).assertEqual('stopCountdown');
    });

    it('changePasswordInput_updatesPassword', 0, () => {
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        AuthUiState.initial(),
        new ChangePasswordInput('secret-2fa'),
        makeEnv()
      );
      expect(res.state.password).assertEqual('secret-2fa');
      expect(res.effects.length).assertEqual(0);
    });

    it('togglePasswordVisibility_flipsFlag', 0, () => {
      const res1: ReducerResult<AuthUiState, Object> = authReducer(
        AuthUiState.initial(),
        new TogglePasswordVisibility(),
        makeEnv()
      );
      expect(res1.state.isPasswordVisible).assertTrue();

      const res2: ReducerResult<AuthUiState, Object> = authReducer(
        res1.state,
        new TogglePasswordVisibility(),
        makeEnv()
      );
      expect(res2.state.isPasswordVisible).assertFalse();
    });

    it('submitPassword_empty_setsError', 0, () => {
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        AuthUiState.initial().copyWith({ password: '' }),
        new SubmitPassword(),
        makeEnv()
      );
      expect(res.state.errorMessage).assertEqual('auth.error.password_empty');
      expect(res.effects.length).assertEqual(0);
    });

    it('submitPassword_valid_emitsEffect', 0, () => {
      const res: ReducerResult<AuthUiState, Object> = authReducer(
        AuthUiState.initial().copyWith({ password: 'my-strong-password' }),
        new SubmitPassword(),
        makeEnv()
      );
      expect(res.state.isSubmitting).assertTrue();
      expect(res.effects.length).assertEqual(1);
      const effect: CheckPassword = res.effects[0] as CheckPassword;
      expect(effect.password).assertEqual('my-strong-password');
    });

    it('changeNames_and_submitRegistration', 0, () => {
      const r1 = authReducer(AuthUiState.initial(), new ChangeFirstName('Alice'), makeEnv());
      const r2 = authReducer(r1.state, new ChangeLastName('Smith'), makeEnv());
      expect(r2.state.firstName).assertEqual('Alice');
      expect(r2.state.lastName).assertEqual('Smith');

      const submitRes = authReducer(r2.state, new SubmitRegistration(), makeEnv());
      expect(submitRes.state.isSubmitting).assertTrue();
      expect(submitRes.effects.length).assertEqual(1);
      const effect: RegisterUser = submitRes.effects[0] as RegisterUser;
      expect(effect.firstName).assertEqual('Alice');
      expect(effect.lastName).assertEqual('Smith');
    });

    it('onAuthStateChanged_waitPhone', 0, () => {
      const auth: AuthStateWaitPhone = { kind: 'waitPhone', loginType: 'phone' };
      const res = authReducer(AuthUiState.initial(), new OnAuthStateChanged(auth), makeEnv());
      expect(res.state.step).assertEqual('waitPhone');
      expect(res.state.isSubmitting).assertFalse();
    });

    it('onAuthStateChanged_waitCode', 0, () => {
      const auth: AuthStateWaitCode = {
        kind: 'waitCode',
        phoneOrEmail: '+8613800138000',
        resendTimeoutMs: 45000,
        codeLength: 6
      };
      const res = authReducer(AuthUiState.initial(), new OnAuthStateChanged(auth), makeEnv());
      expect(res.state.step).assertEqual('waitCode');
      expect(res.state.codeLength).assertEqual(6);
      expect(res.state.resendTimeoutSeconds).assertEqual(45);
      expect(res.state.canResendCode).assertFalse();
      expect(res.effects.length).assertEqual(1);
      expect((res.effects[0] as StartCountdown).durationSeconds).assertEqual(45);
    });

    it('onAuthStateChanged_wait2fa', 0, () => {
      const auth: AuthStateWait2FA = {
        kind: 'wait2fa',
        passwordHint: 'first pet',
        hasRecoveryEmail: true,
        recoveryEmailPattern: 'a***@b.com'
      };
      const res = authReducer(AuthUiState.initial(), new OnAuthStateChanged(auth), makeEnv());
      expect(res.state.step).assertEqual('wait2fa');
      expect(res.state.passwordHint).assertEqual('first pet');
    });

    it('onAuthStateChanged_waitRegistration', 0, () => {
      const auth: AuthStateWaitRegistration = {
        kind: 'waitRegistration'
      };
      const res = authReducer(AuthUiState.initial(), new OnAuthStateChanged(auth), makeEnv());
      expect(res.state.step).assertEqual('waitRegistration');
    });

    it('onAuthStateChanged_ready_navigatesToChats', 0, () => {
      const auth: AuthStateReady = { kind: 'ready' };
      const res = authReducer(AuthUiState.initial(), new OnAuthStateChanged(auth), makeEnv());
      expect(res.state.step).assertEqual('ready');
      expect(res.effects.length).assertEqual(1);
      expect((res.effects[0] as NavigateToRoute).routeName).assertEqual('chat_list');
    });

    it('onAuthStateChanged_failed_setsError', 0, () => {
      const auth: AuthStateFailed = {
        kind: 'failed',
        error: AppErrors.internal('auth.failed.network', 'auth failed')
      };
      const res = authReducer(AuthUiState.initial(), new OnAuthStateChanged(auth), makeEnv());
      expect(res.state.step).assertEqual('failed');
      expect(res.state.errorMessage).assertEqual('auth failed');
      expect(res.state.errorCode).assertEqual('internal');
    });

    it('onRequestError_resetsSubmittingAndShowsToast', 0, () => {
      const initial: AuthUiState = AuthUiState.initial().copyWith({ isSubmitting: true });
      const res = authReducer(
        initial,
        new OnRequestError(AppErrors.parameter('invalid', 'phone_number', 'PHONE_NUMBER_INVALID')),
        makeEnv()
      );
      expect(res.state.isSubmitting).assertFalse();
      expect(res.state.errorMessage).assertEqual('PHONE_NUMBER_INVALID');
      expect(res.effects.length).assertEqual(1);
      expect((res.effects[0] as ShowToast).messageKey).assertEqual('PHONE_NUMBER_INVALID');
    });

    it('clearError_clearsErrorOrReturnsSame', 0, () => {
      const noError = AuthUiState.initial();
      const res1 = authReducer(noError, new ClearError(), makeEnv());
      expect(res1.state === noError).assertTrue();

      const withError = noError.copyWith({ errorMessage: 'some error', errorCode: 'E' });
      const res2 = authReducer(withError, new ClearError(), makeEnv());
      expect(res2.state.errorMessage).assertNull();
      expect(res2.state.errorCode).assertNull();
    });

    it('backToPhone_resetsToPhoneStep', 0, () => {
      const inCode = AuthUiState.initial().copyWith({
        step: 'waitCode',
        code: '123',
        errorMessage: 'error'
      });
      const res = authReducer(inCode, new BackToPhone(), makeEnv());
      expect(res.state.step).assertEqual('waitPhone');
      expect(res.state.code).assertEqual('');
      expect(res.state.errorMessage).assertNull();
    });

    it('onRecaptchaRequired_reportsUnsupportedVerification', 0, () => {
      const res = authReducer(
        AuthUiState.initial(),
        new OnRecaptchaRequired(42, 'login', 'mobile-key'),
        makeEnv()
      );
      expect(res.state.step).assertEqual('waitRecaptcha');
      expect(res.state.verificationId).assertEqual(42);
      expect(res.effects.length).assertEqual(1);
      const effect: SendVerificationToken = res.effects[0] as SendVerificationToken;
      expect(effect.kind).assertEqual('sendVerificationToken');
      expect(effect.verificationId).assertEqual(42);
      expect(effect.token).assertEqual('');
    });

    it('requestQrCodeLogin_startsQrAuthentication', 0, () => {
      const res = authReducer(AuthUiState.initial(), new RequestQrCodeLogin(), makeEnv());
      expect(res.state.step).assertEqual('waitQrCode');
      expect(res.state.isSubmitting).assertTrue();
      expect(res.effects.length).assertEqual(1);
      expect((res.effects[0] as RequestQrCodeAuthentication).kind).assertEqual('requestQrCodeAuthentication');
    });

    it('onQrCodeLinkReceived_displaysLatestLink', 0, () => {
      const res = authReducer(
        AuthUiState.initial().copyWith({ step: 'waitQrCode', isSubmitting: true }),
        new OnQrCodeLinkReceived('tg://login?token=test'),
        makeEnv()
      );
      expect(res.state.step).assertEqual('waitQrCode');
      expect(res.state.qrCodeLink).assertEqual('tg://login?token=test');
      expect(res.state.isSubmitting).assertFalse();
    });

    it('onRequestError_duringQrLogin_isVisibleAndRetryable', 0, () => {
      const res = authReducer(
        AuthUiState.initial().copyWith({ step: 'waitQrCode', isSubmitting: true }),
        new OnRequestError(AppErrors.internal('qr.failed', 'QR login failed')),
        makeEnv()
      );
      expect(res.state.step).assertEqual('waitQrCode');
      expect(res.state.isSubmitting).assertFalse();
      expect(res.state.errorMessage).assertEqual('QR login failed');
      expect(res.effects.length).assertEqual(1);
    });

    it('reducer_pure_sameInputSameOutput', 0, () => {
      const env = makeEnv();
      const s = AuthUiState.initial().copyWith({ rawPhone: '13812345678' });
      const intent = new SubmitPhone();
      const r1 = authReducer(s, intent, env);
      const r2 = authReducer(s, intent, env);
      expect(r1.state.isSubmitting).assertEqual(r2.state.isSubmitting);
      expect(r1.state.formattedPhone).assertEqual(r2.state.formattedPhone);
      expect(r1.effects.length).assertEqual(r2.effects.length);
    });
  });
}
