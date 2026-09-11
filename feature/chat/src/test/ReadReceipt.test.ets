import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ChatUiState } from '../main/ets/contract/ChatUiState';
import { MessageItem, MessageSendState } from '../main/ets/model/MessageItem';
import {
  incomingIdUpTo,
  isOutgoingMessageRead,
  ReadReportThrottle
} from '../main/ets/model/ReadReceipt';
import {
  OnVisibleRangeChanged,
  TapFailedMessage
} from '../main/ets/contract/ChatIntent';
import {
  ChatEffect,
  ReportMessagesRead,
  ResendMessage
} from '../main/ets/contract/ChatEffect';
import { chatReducer } from '../main/ets/reducer/ChatReducer';

function makeItem(messageId: number, isOutgoing: boolean, sendState: MessageSendState = 'none'): MessageItem {
  return new MessageItem(messageId, 'm', 1000, isOutgoing, '', sendState, true, false, null, '');
}

function makeEnv(): ReducerEnv {
  const env: ReducerEnv = {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('req-test-')
  };
  return env;
}

function makeStateWith(messages: readonly MessageItem[]): ChatUiState {
  return new ChatUiState(42, 'chat', messages, false, true, null, '', null, null);
}

export default function readReceiptTest() {
  describe('ReadReceiptTest', () => {
    it('isOutgoingMessageRead_idBoundaries', 0, () => {
      // 水位 100：id 小于/等于水位已读，大于未读；incoming 与水位 0 恒未读。
      expect(isOutgoingMessageRead(true, 99, 100)).assertTrue();
      expect(isOutgoingMessageRead(true, 100, 100)).assertTrue();
      expect(isOutgoingMessageRead(true, 101, 100)).assertFalse();
      expect(isOutgoingMessageRead(false, 50, 100)).assertFalse();
      expect(isOutgoingMessageRead(true, 50, 0)).assertFalse();
    });

    it('incomingIdUpTo_emptyAndNegativeIndex_safe', 0, () => {
      expect(incomingIdUpTo([], 0)).assertEqual(0);
      expect(incomingIdUpTo([makeItem(1, false)], -1)).assertEqual(0);
    });

    it('incomingIdUpTo_picksMaxIncomingWithinRange', 0, () => {
      const items: MessageItem[] = [
        makeItem(10, false),
        makeItem(11, true),
        makeItem(12, false),
        makeItem(13, true),
        makeItem(14, false)
      ];
      // 全范围：最后一条 incoming 是 14。
      expect(incomingIdUpTo(items, 4)).assertEqual(14);
      // 只入屏到 index 2：12 之后的不算。
      expect(incomingIdUpTo(items, 2)).assertEqual(12);
      // index 越界 clamp 到列表末尾。
      expect(incomingIdUpTo(items, 99)).assertEqual(14);
      // 子范围 [11 out, 12 in, 13 out] 末尾向前扫 → 12。
      expect(incomingIdUpTo(items.slice(1, 4), 2)).assertEqual(12);
      // 范围内全是 outgoing → 0。
      expect(incomingIdUpTo([makeItem(1, true), makeItem(2, true)], 1)).assertEqual(0);
    });

    it('readReportThrottle_onlyIncreases', 0, () => {
      const items: MessageItem[] = [makeItem(10, false), makeItem(12, false), makeItem(14, false)];
      const throttle = new ReadReportThrottle();
      expect(throttle.poll(items, 2)).assertEqual(14);
      // 相同目标不再上报。
      expect(throttle.poll(items, 2)).assertEqual(0);
      // 更小的可视范围（往前滚）不上报。
      expect(throttle.poll(items, 0)).assertEqual(0);
      expect(throttle.lastReportedId).assertEqual(14);
      // 新到更大的 incoming id 才再次上报。
      const grew: MessageItem[] = items.concat([makeItem(20, false)]);
      expect(throttle.poll(grew, 3)).assertEqual(20);
      expect(throttle.lastReportedId).assertEqual(20);
    });

    it('readReportThrottle_outgoingOnly_neverReports', 0, () => {
      const items: MessageItem[] = [makeItem(1, true), makeItem(2, true)];
      const throttle = new ReadReportThrottle();
      expect(throttle.poll(items, 1)).assertEqual(0);
      expect(throttle.poll([], 0)).assertEqual(0);
      expect(throttle.lastReportedId).assertEqual(0);
    });

    it('onVisibleRangeChanged_emitsReportForMaxIncomingInRange', 0, () => {
      const state: ChatUiState = makeStateWith([
        makeItem(10, false),
        makeItem(11, true),
        makeItem(12, false)
      ]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnVisibleRangeChanged(1), makeEnv());
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(1);
      const effect: ReportMessagesRead = result.effects[0] as ReportMessagesRead;
      expect(effect.kind).assertEqual('reportMessagesRead');
      expect(effect.chatId).assertEqual(42);
      expect(effect.messageId).assertEqual(10);
    });

    it('onVisibleRangeChanged_noIncoming_noEffect', 0, () => {
      const state: ChatUiState = makeStateWith([makeItem(1, true), makeItem(2, true)]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnVisibleRangeChanged(1), makeEnv());
      expect(result.effects.length).assertEqual(0);
    });

    it('tapFailedMessage_failedMessage_emitsResend', 0, () => {
      const state: ChatUiState = makeStateWith([makeItem(7, true, 'failed')]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new TapFailedMessage(7), makeEnv());
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(1);
      const effect: ResendMessage = result.effects[0] as ResendMessage;
      expect(effect.kind).assertEqual('resendMessage');
      expect(effect.chatId).assertEqual(42);
      expect(effect.messageId).assertEqual(7);
    });

    it('tapFailedMessage_nonFailedOrUnknown_isNoOp', 0, () => {
      const state: ChatUiState = makeStateWith([makeItem(7, true, 'none'), makeItem(8, true, 'pending')]);
      const sent: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new TapFailedMessage(7), makeEnv());
      expect(sent.effects.length).assertEqual(0);
      const pending: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new TapFailedMessage(8), makeEnv());
      expect(pending.effects.length).assertEqual(0);
      const unknown: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new TapFailedMessage(999), makeEnv());
      expect(unknown.effects.length).assertEqual(0);
    });
  });
}
