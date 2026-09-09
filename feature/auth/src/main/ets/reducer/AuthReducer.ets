/**
 * feature/auth — 登录状态机纯 Reducer（AUTH-001）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 纯函数：(state, intent, env) -> ReducerResult<AuthUiState, AuthEffect>
 * - 禁止直接修改 state；无变化返回原引用 reduced(state)
 * - 禁止在 reducer 内做 I/O 或异步，副作用全部通过 AuthEffect 表达
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { AuthUiState } from '../contract/AuthUiState';
import {
  AuthIntent,
  SelectCountry,
  ChangePhoneInput,
  ChangeCodeInput,
  ChangePasswordInput,
  ChangeFirstName,
  ChangeLastName,
  OnAuthStateChanged,
  OnRequestError
} from '../contract/AuthIntent';
import {
  AuthEffect,
  SendPhoneNumber,
  CheckCode,
  ResendCode,
  CheckPassword,
  RegisterUser,
  NavigateToRoute,
  ShowToast,
  StartCountdown,
  StopCountdown
} from '../contract/AuthEffect';
import { formatFullPhoneNumber } from '../model/CountryCode';

export const authReducer: Reducer<AuthUiState, AuthIntent, AuthEffect> = (
  state: AuthUiState,
  intent: AuthIntent,
  env: ReducerEnv
): ReducerResult<AuthUiState, AuthEffect> => {
  switch (intent.kind) {
    case 'selectCountry': {
      const selectIntent: SelectCountry = intent as SelectCountry;
      const formatted: string = formatFullPhoneNumber(selectIntent.countryCode, state.rawPhone);
      const nextState: AuthUiState = state.copyWith({
        countryCode: selectIntent.countryCode,
        countryName: selectIntent.countryName,
        formattedPhone: formatted
      });
      return reduced(nextState);
    }

    case 'changePhoneInput': {
      const phoneIntent: ChangePhoneInput = intent as ChangePhoneInput;
      const cleanPhone: string = phoneIntent.phone.replace(/\D/g, '');
      const formatted: string = formatFullPhoneNumber(state.countryCode, cleanPhone);
      const nextState: AuthUiState = state.copyWith({
        rawPhone: cleanPhone,
        formattedPhone: formatted,
        errorMessage: null,
        errorCode: null
      });
      return reduced(nextState);
    }

    case 'submitPhone': {
      if (state.rawPhone.trim().length === 0) {
        return reduced(state.copyWith({
          errorMessage: 'auth.error.phone_empty',
          errorCode: 'VALIDATION_FAILED'
        }));
      }
      if (state.rawPhone.trim().length < 3) {
        return reduced(state.copyWith({
          errorMessage: 'auth.error.phone_too_short',
          errorCode: 'VALIDATION_FAILED'
        }));
      }
      const nextState: AuthUiState = state.copyWith({
        isSubmitting: true,
        errorMessage: null,
        errorCode: null
      });
      const effects: AuthEffect[] = [new SendPhoneNumber(state.formattedPhone)];
      return reduced(nextState, effects);
    }

    case 'changeCodeInput': {
      const codeIntent: ChangeCodeInput = intent as ChangeCodeInput;
      const cleanCode: string = codeIntent.code.replace(/\D/g, '');
      // 达到预期位数时自动提交
      if (cleanCode.length >= state.codeLength && state.codeLength > 0) {
        const nextState: AuthUiState = state.copyWith({
          code: cleanCode,
          isSubmitting: true,
          errorMessage: null,
          errorCode: null
        });
        const effects: AuthEffect[] = [new CheckCode(cleanCode)];
        return reduced(nextState, effects);
      }
      const nextState: AuthUiState = state.copyWith({
        code: cleanCode,
        errorMessage: null,
        errorCode: null
      });
      return reduced(nextState);
    }

    case 'submitCode': {
      if (state.code.trim().length === 0) {
        return reduced(state.copyWith({
          errorMessage: 'auth.error.code_empty',
          errorCode: 'VALIDATION_FAILED'
        }));
      }
      const nextState: AuthUiState = state.copyWith({
        isSubmitting: true,
        errorMessage: null,
        errorCode: null
      });
      const effects: AuthEffect[] = [new CheckCode(state.code)];
      return reduced(nextState, effects);
    }

    case 'requestResendCode': {
      if (!state.canResendCode) {
        return reduced(state);
      }
      const nextState: AuthUiState = state.copyWith({
        canResendCode: false,
        resendTimeoutSeconds: 60,
        errorMessage: null,
        errorCode: null
      });
      const effects: AuthEffect[] = [new ResendCode(), new StartCountdown(60)];
      return reduced(nextState, effects);
    }

    case 'countdownTick': {
      if (state.resendTimeoutSeconds <= 1) {
        const nextState: AuthUiState = state.copyWith({
          resendTimeoutSeconds: 0,
          canResendCode: true
        });
        const effects: AuthEffect[] = [new StopCountdown()];
        return reduced(nextState, effects);
      }
      const nextState: AuthUiState = state.copyWith({
        resendTimeoutSeconds: state.resendTimeoutSeconds - 1
      });
      return reduced(nextState);
    }

    case 'changePasswordInput': {
      const pwdIntent: ChangePasswordInput = intent as ChangePasswordInput;
      const nextState: AuthUiState = state.copyWith({
        password: pwdIntent.password,
        errorMessage: null,
        errorCode: null
      });
      return reduced(nextState);
    }

    case 'togglePasswordVisibility': {
      const nextState: AuthUiState = state.copyWith({
        isPasswordVisible: !state.isPasswordVisible
      });
      return reduced(nextState);
    }

    case 'submitPassword': {
      if (state.password.length === 0) {
        return reduced(state.copyWith({
          errorMessage: 'auth.error.password_empty',
          errorCode: 'VALIDATION_FAILED'
        }));
      }
      const nextState: AuthUiState = state.copyWith({
        isSubmitting: true,
        errorMessage: null,
        errorCode: null
      });
      const effects: AuthEffect[] = [new CheckPassword(state.password)];
      return reduced(nextState, effects);
    }

    case 'changeFirstName': {
      const fnIntent: ChangeFirstName = intent as ChangeFirstName;
      const nextState: AuthUiState = state.copyWith({
        firstName: fnIntent.firstName,
        errorMessage: null,
        errorCode: null
      });
      return reduced(nextState);
    }

    case 'changeLastName': {
      const lnIntent: ChangeLastName = intent as ChangeLastName;
      const nextState: AuthUiState = state.copyWith({
        lastName: lnIntent.lastName,
        errorMessage: null,
        errorCode: null
      });
      return reduced(nextState);
    }

    case 'submitRegistration': {
      const trimmedFirst: string = state.firstName.trim();
      if (trimmedFirst.length === 0) {
        return reduced(state.copyWith({
          errorMessage: 'auth.error.first_name_empty',
          errorCode: 'VALIDATION_FAILED'
        }));
      }
      const nextState: AuthUiState = state.copyWith({
        isSubmitting: true,
        errorMessage: null,
        errorCode: null
      });
      const effects: AuthEffect[] = [new RegisterUser(trimmedFirst, state.lastName.trim())];
      return reduced(nextState, effects);
    }

    case 'onAuthStateChanged': {
      const authIntent: OnAuthStateChanged = intent as OnAuthStateChanged;
      const auth = authIntent.authState;
      switch (auth.kind) {
        case 'waitParams':
          return reduced(state.copyWith({
            step: 'waitParams',
            isSubmitting: false,
            rawAuthState: auth
          }));

        case 'waitDbKey':
          return reduced(state.copyWith({
            step: 'waitDbKey',
            isSubmitting: false,
            rawAuthState: auth
          }));

        case 'waitPhone':
          return reduced(state.copyWith({
            step: 'waitPhone',
            isSubmitting: false,
            rawAuthState: auth
          }));

        case 'waitCode': {
          const timeoutSeconds: number = auth.resendTimeoutMs > 0
            ? Math.floor(auth.resendTimeoutMs / 1000)
            : 60;
          const nextState: AuthUiState = state.copyWith({
            step: 'waitCode',
            code: '',
            codeLength: auth.codeLength > 0 ? auth.codeLength : 5,
            resendTimeoutSeconds: timeoutSeconds,
            canResendCode: timeoutSeconds <= 0,
            isSubmitting: false,
            errorMessage: null,
            errorCode: null,
            rawAuthState: auth
          });
          const effects: AuthEffect[] = timeoutSeconds > 0
            ? [new StartCountdown(timeoutSeconds)]
            : [];
          return reduced(nextState, effects);
        }

        case 'wait2fa':
          return reduced(state.copyWith({
            step: 'wait2fa',
            password: '',
            passwordHint: auth.passwordHint,
            isSubmitting: false,
            errorMessage: null,
            errorCode: null,
            rawAuthState: auth
          }));

        case 'waitRegistration':
          return reduced(state.copyWith({
            step: 'waitRegistration',
            isSubmitting: false,
            errorMessage: null,
            errorCode: null,
            rawAuthState: auth
          }));

        case 'ready': {
          const nextState: AuthUiState = state.copyWith({
            step: 'ready',
            isSubmitting: false,
            rawAuthState: auth
          });
          const effects: AuthEffect[] = [new NavigateToRoute('chat_list')];
          return reduced(nextState, effects);
        }

        case 'loggingOut':
          return reduced(state.copyWith({
            step: 'loggingOut',
            isSubmitting: false,
            rawAuthState: auth
          }));

        case 'closing':
          return reduced(state.copyWith({
            step: 'closing',
            isSubmitting: false,
            rawAuthState: auth
          }));

        case 'closed':
          return reduced(state.copyWith({
            step: 'closed',
            isSubmitting: false,
            rawAuthState: auth
          }));

        case 'failed':
          return reduced(state.copyWith({
            step: 'failed',
            isSubmitting: false,
            errorMessage: auth.error.message,
            errorCode: auth.error.kind,
            rawAuthState: auth
          }));
      }
      return reduced(state);
    }

    case 'onRequestError': {
      const errIntent: OnRequestError = intent as OnRequestError;
      const nextState: AuthUiState = state.copyWith({
        isSubmitting: false,
        errorMessage: errIntent.error.message,
        errorCode: errIntent.error.kind
      });
      const effects: AuthEffect[] = [new ShowToast(errIntent.error.message)];
      return reduced(nextState, effects);
    }

    case 'clearError': {
      if (state.errorMessage === null && state.errorCode === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({ errorMessage: null, errorCode: null }));
    }

    case 'backToPhone': {
      return reduced(state.copyWith({
        step: 'waitPhone',
        isSubmitting: false,
        errorMessage: null,
        errorCode: null,
        code: '',
        password: ''
      }));
    }
  }

  return reduced(state);
};
