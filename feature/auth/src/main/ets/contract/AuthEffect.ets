/**
 * feature/auth — 登录副作用描述（AUTH-001）。
 *
 * Effect 是一次性副作用的描述，由 Coordinator / Handler 执行，reducer 严禁执行。
 */

import { Effect } from '@tgx/feature-template';

export class SendPhoneNumber implements Effect {
  readonly kind: 'sendPhoneNumber' = 'sendPhoneNumber';
  readonly phoneNumber: string;

  constructor(phoneNumber: string) {
    this.phoneNumber = phoneNumber;
  }
}

export class CheckCode implements Effect {
  readonly kind: 'checkCode' = 'checkCode';
  readonly code: string;

  constructor(code: string) {
    this.code = code;
  }
}

export class ResendCode implements Effect {
  readonly kind: 'resendCode' = 'resendCode';
}

export class CheckPassword implements Effect {
  readonly kind: 'checkPassword' = 'checkPassword';
  readonly password: string;

  constructor(password: string) {
    this.password = password;
  }
}

export class RegisterUser implements Effect {
  readonly kind: 'registerUser' = 'registerUser';
  readonly firstName: string;
  readonly lastName: string;

  constructor(firstName: string, lastName: string) {
    this.firstName = firstName;
    this.lastName = lastName;
  }
}

export class NavigateToRoute implements Effect {
  readonly kind: 'navigateToRoute' = 'navigateToRoute';
  readonly routeName: string;

  constructor(routeName: string) {
    this.routeName = routeName;
  }
}

export class ShowToast implements Effect {
  readonly kind: 'showToast' = 'showToast';
  readonly messageKey: string;

  constructor(messageKey: string) {
    this.messageKey = messageKey;
  }
}

export class StartCountdown implements Effect {
  readonly kind: 'startCountdown' = 'startCountdown';
  readonly durationSeconds: number;

  constructor(durationSeconds: number) {
    this.durationSeconds = durationSeconds;
  }
}

export class StopCountdown implements Effect {
  readonly kind: 'stopCountdown' = 'stopCountdown';
}

export class SendVerificationToken implements Effect {
  readonly kind: 'sendVerificationToken' = 'sendVerificationToken';
  readonly verificationId: number;
  readonly token: string;

  constructor(verificationId: number, token: string) {
    this.verificationId = verificationId;
    this.token = token;
  }
}

export type AuthEffect =
  | SendPhoneNumber
  | CheckCode
  | ResendCode
  | CheckPassword
  | RegisterUser
  | NavigateToRoute
  | ShowToast
  | StartCountdown
  | StopCountdown
  | SendVerificationToken;
