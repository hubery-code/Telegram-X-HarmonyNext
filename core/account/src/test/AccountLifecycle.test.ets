/**
 * AccountLifecycle 纯 reducer 单测（CORE-003）。
 * 覆盖状态机全转换矩阵 + 终态幂等 + 未知事件。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, Result } from '@tgx/core-common';
import {
  AccountLifecycleEvent,
  AccountLifecycleState,
  INITIAL_ACCOUNT_LIFECYCLE,
  reduceAccountLifecycle
} from '../main/ets/AccountLifecycle';

function reduceOk(state: AccountLifecycleState, event: AccountLifecycleEvent): AccountLifecycleState {
  const result: Result<AccountLifecycleState, AppError> = reduceAccountLifecycle(state, event);
  expect(result.ok).assertTrue();
  if (result.ok) {
    return result.value;
  }
  return state;
}

export default function accountLifecycleTest() {
  describe('AccountLifecycleTest', () => {

    it('initialState_isActive', 0, () => {
      expect(INITIAL_ACCOUNT_LIFECYCLE).assertEqual('active');
    });

    it('active_hibernate_transitionsToHibernating', 0, () => {
      expect(reduceOk('active', 'hibernate')).assertEqual('hibernating');
    });

    it('hibernating_activate_transitionsToActive', 0, () => {
      expect(reduceOk('hibernating', 'activate')).assertEqual('active');
    });

    it('active_activate_isIdempotentNoOp', 0, () => {
      expect(reduceOk('active', 'activate')).assertEqual('active');
    });

    it('hibernating_hibernate_isIdempotentNoOp', 0, () => {
      expect(reduceOk('hibernating', 'hibernate')).assertEqual('hibernating');
    });

    it('active_close_transitionsToClosed', 0, () => {
      expect(reduceOk('active', 'close')).assertEqual('closed');
    });

    it('hibernating_close_transitionsToClosed', 0, () => {
      expect(reduceOk('hibernating', 'close')).assertEqual('closed');
    });

    it('closed_activate_staysClosed_terminal', 0, () => {
      expect(reduceOk('closed', 'activate')).assertEqual('closed');
    });

    it('closed_hibernate_staysClosed_terminal', 0, () => {
      expect(reduceOk('closed', 'hibernate')).assertEqual('closed');
    });

    it('closed_close_isIdempotent', 0, () => {
      expect(reduceOk('closed', 'close')).assertEqual('closed');
    });

    it('allDefinedEvents_returnOk_neverErr', 0, () => {
      const states: AccountLifecycleState[] = ['active', 'hibernating', 'closed'];
      const events: AccountLifecycleEvent[] = ['activate', 'hibernate', 'close'];
      for (const state of states) {
        for (const event of events) {
          const result: Result<AccountLifecycleState, AppError> = reduceAccountLifecycle(state, event);
          expect(result.ok).assertTrue();
        }
      }
    });

    it('unknownEvent_returnsErr_internal', 0, () => {
      const result: Result<AccountLifecycleState, AppError> = reduceAccountLifecycle(
        'active',
        'explode' as AccountLifecycleEvent
      );
      expect(result.ok).assertFalse();
      if (result.ok === false) {
        expect(result.error.kind).assertEqual('internal');
      }
    });
  });
}
