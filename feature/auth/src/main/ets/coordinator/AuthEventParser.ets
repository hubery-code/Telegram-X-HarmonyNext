/**
 * feature/auth — TDLib updateAuthorizationState 事件解析器（AUTH-001）。
 *
 * 把 wire JSON / TdWireObject 解析为 core/account 的强类型 AuthEvent。
 */

import { TdWireObject, isWireObject, wireNumber, wireString } from '@tgx/td-gateway';
import { AuthCodeInfo, AuthEvent } from '@tgx/core-account';

export interface RecaptchaUpdateInfo {
  readonly verificationId: number;
  readonly action: string;
  readonly recaptchaKeyId: string;
}

export function parseRecaptchaUpdateFromWire(payload: TdWireObject): RecaptchaUpdateInfo | null {
  const type: string = wireString(payload['@type']);
  if (type !== 'updateApplicationRecaptchaVerificationRequired') {
    return null;
  }

  const verificationId: number = wireNumber(payload['verification_id'], 0);
  const action: string = wireString(payload['action']);
  const recaptchaKeyId: string = wireString(payload['recaptcha_key_id']);

  if (verificationId === 0 || recaptchaKeyId.length === 0) {
    return null;
  }

  return { verificationId, action, recaptchaKeyId };
}

export function parseAuthEventFromWire(payload: TdWireObject): AuthEvent | null {
  const type: string = wireString(payload['@type']);
  if (type !== 'updateAuthorizationState') {
    return null;
  }

  const rawAuthState = payload['authorization_state'];
  if (!isWireObject(rawAuthState)) {
    return null;
  }
  const authStateObj: TdWireObject = rawAuthState as TdWireObject;

  const stateType: string = wireString(authStateObj['@type']);
  if (stateType.length === 0) {
    return null;
  }

  switch (stateType) {
    case 'authorizationStateWaitTdlibParameters':
      return { type: 'authorizationStateWaitTdlibParameters' };

    case 'authorizationStateWaitEncryptionKey': {
      const isEncrypted: boolean = authStateObj['is_encrypted'] === true;
      return { type: 'authorizationStateWaitEncryptionKey', isEncrypted };
    }

    case 'authorizationStateWaitPhoneNumber':
      return { type: 'authorizationStateWaitPhoneNumber' };

    case 'authorizationStateWaitEmailAddress':
      return { type: 'authorizationStateWaitEmailAddress' };

    case 'authorizationStateWaitOtherDeviceConfirmation':
      return { type: 'authorizationStateWaitOtherDeviceConfirmation' };

    case 'authorizationStateWaitCode': {
      const rawCodeInfo = authStateObj['code_info'];
      const codeInfoObj: TdWireObject | null = isWireObject(rawCodeInfo) ? (rawCodeInfo as TdWireObject) : null;
      const phone: string = codeInfoObj !== null ? wireString(codeInfoObj['phone_number']) : '';
      const timeout: number = codeInfoObj !== null ? wireNumber(codeInfoObj['timeout'], 60) : 60;
      let codeType: string = 'authenticationCodeTypeSms';
      let length: number = 5;

      if (codeInfoObj !== null) {
        const rawType = codeInfoObj['type'];
        if (isWireObject(rawType)) {
          const typeObj: TdWireObject = rawType as TdWireObject;
          codeType = wireString(typeObj['@type'], codeType);
          const len: number = wireNumber(typeObj['length'], 0);
          if (len > 0) {
            length = len;
          }
        }
      }

      const ci: AuthCodeInfo = {
        phoneNumber: phone,
        codeType,
        length,
        timeout
      };
      return { type: 'authorizationStateWaitCode', codeInfo: ci };
    }

    case 'authorizationStateWaitPassword': {
      const hint: string = wireString(authStateObj['password_hint']);
      const hasRecovery: boolean = authStateObj['has_recovery_email_address'] === true;
      const pattern: string = wireString(authStateObj['recovery_email_address_pattern']);
      return {
        type: 'authorizationStateWaitPassword',
        passwordHint: hint,
        hasRecoveryEmailAddress: hasRecovery,
        recoveryEmailAddressPattern: pattern
      };
    }

    case 'authorizationStateWaitRegistration': {
      return { type: 'authorizationStateWaitRegistration' };
    }

    case 'authorizationStateReady':
      return { type: 'authorizationStateReady' };

    case 'authorizationStateLoggingOut':
      return { type: 'authorizationStateLoggingOut' };

    case 'authorizationStateClosing':
      return { type: 'authorizationStateClosing' };

    case 'authorizationStateClosed':
      return { type: 'authorizationStateClosed' };
  }

  return null;
}
