import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator, AppErrors } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ChatUiState } from '../main/ets/contract/ChatUiState';
import {
  ChatIntent,
  ComposerTextChanged,
  SendCurrentMessage,
  OnMessageSendFailed
} from '../main/ets/contract/ChatIntent';
import { ChatEffect, SendTextMessage } from '../main/ets/contract/ChatEffect';
import { chatReducer } from '../main/ets/reducer/ChatReducer';

function makeEnv(nowMillis: number = 1000, monotonicMillis: number = 500): ReducerEnv {
  const env: ReducerEnv = {
    clock: new ManualClock(nowMillis, monotonicMillis),
    ids: new SequentialIdGenerator('req-test-')
  };
  return env;
}

function makeState(composerText: string = '', errorMessage: string | null = null): ChatUiState {
  return new ChatUiState(42, 'chat', [], false, true, errorMessage, composerText);
}

export default function chatReducerTest() {
  describe('ChatReducerTest', () => {
    it('composerTextChanged_updatesComposerText_andClearsError', 0, () => {
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(makeState('', 'send failed'), new ComposerTextChanged('hello'), makeEnv());
      expect(result.state.composerText).assertEqual('hello');
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('sendCurrentMessage_emptyText_isNoOpSameStateRef', 0, () => {
      const state: ChatUiState = makeState('   ');
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new SendCurrentMessage(), makeEnv());
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('sendCurrentMessage_withText_clearsComposerAndEmitsSendEffect', 0, () => {
      const state: ChatUiState = makeState('  hello world  ');
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new SendCurrentMessage(), makeEnv());
      expect(result.state.composerText).assertEqual('');
      expect(result.effects.length).assertEqual(1);
      const effect: ChatEffect = result.effects[0];
      expect(effect.kind).assertEqual('sendTextMessage');
      const send: SendTextMessage = effect as SendTextMessage;
      expect(send.chatId).assertEqual(42);
      expect(send.text).assertEqual('hello world');
    });

    it('onMessageSendFailed_setsErrorMessage_keepsComposerCleared', 0, () => {
      const state: ChatUiState = makeState('');
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OnMessageSendFailed(AppErrors.tdlib('bad_request', 'TDLib rejected the request', false)),
        makeEnv()
      );
      expect(result.state.errorMessage).assertEqual('TDLib rejected the request');
      expect(result.state.composerText).assertEqual('');
      expect(result.effects.length).assertEqual(0);
    });
  });
}
