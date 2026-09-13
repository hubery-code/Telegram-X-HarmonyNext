import { describe, it, expect, beforeEach } from '@ohos/hypium';
import {
  ChatListProjection,
  chatListEquals,
  compareChatOrder,
  isChatPinnedInList
} from '../../main/ets/chatlist/ChatListProjection';
import { ChatRegistry } from '../../main/ets/chatlist/ChatRegistry';
import { Chat, ChatListMain, ChatListArchive, ChatPosition } from '@tgx/core-td-api-generated';

/** 造一个只带 positions 的 Chat（isChatPinnedInList 只读 positions）。 */
function makeChatWithPositions(id: number, positions: ChatPosition[]): Chat {
  const chat = new Chat();
  chat.id = id;
  chat.positions = positions;
  return chat;
}

/** 造一个位置。 */
function makePosition(list: ChatListMain | ChatListArchive, order: string, isPinned: boolean): ChatPosition {
  const pos = new ChatPosition();
  pos.list = list;
  pos.order = order;
  pos.is_pinned = isPinned;
  return pos;
}

export default function chatListProjectionTest() {
  describe('ChatListProjection', (): void => {
    
    it('compareChatOrder should sort correctly', 0, (): void => {
      // Order DESC, ID DESC
      // a is greater order, should return < 0 (i.e. -1)
      expect(compareChatOrder("10", 1, "5", 1)).assertEqual(-1);
      expect(compareChatOrder("5", 1, "10", 1)).assertEqual(1);
      
      // Same order, A has greater id -> A should be before B (-1)
      expect(compareChatOrder("5", 2, "5", 1)).assertEqual(-1);
      expect(compareChatOrder("5", 1, "5", 2)).assertEqual(1);
      
      // Exact same
      expect(compareChatOrder("5", 1, "5", 1)).assertEqual(0);
      
      // BigInt larger than number
      expect(compareChatOrder("9223372036854775807", 1, "9223372036854775806", 2)).assertEqual(-1);
    });

    it('chatListEquals works', 0, (): void => {
      const main1 = new ChatListMain();
      const main2 = new ChatListMain();
      const archive = new ChatListArchive();
      
      expect(chatListEquals(main1, main2)).assertTrue();
      expect(chatListEquals(main1, archive)).assertFalse();
      expect(chatListEquals(main1, null)).assertFalse();
    });

    // ---- MSG-108 置顶态判定（FEAT-CHAT-002）----

    it('isChatPinnedInList reads is_pinned from the matching list position', 0, (): void => {
      const main = new ChatListMain();
      const chat = makeChatWithPositions(7, [makePosition(main, '100', true)]);
      expect(isChatPinnedInList(chat, main)).assertTrue();
    });

    it('isChatPinnedInList returns false for an unpinned position', 0, (): void => {
      const main = new ChatListMain();
      const chat = makeChatWithPositions(7, [makePosition(main, '100', false)]);
      expect(isChatPinnedInList(chat, main)).assertFalse();
    });

    it('isChatPinnedInList ignores positions belonging to another list', 0, (): void => {
      // 只有归档区的置顶位置时，主列表查询必须为 false（不能跨列表误判）
      const main = new ChatListMain();
      const archive = new ChatListArchive();
      const chat = makeChatWithPositions(7, [makePosition(archive, '100', true)]);
      expect(isChatPinnedInList(chat, main)).assertFalse();
      expect(isChatPinnedInList(chat, archive)).assertTrue();
    });

    it('isChatPinnedInList returns false when the chat has no position at all', 0, (): void => {
      const main = new ChatListMain();
      const chat = makeChatWithPositions(7, []);
      expect(isChatPinnedInList(chat, main)).assertFalse();
    });

    it('isChatPinnedInList picks the right entry among several positions', 0, (): void => {
      const main = new ChatListMain();
      const archive = new ChatListArchive();
      const chat = makeChatWithPositions(7, [
        makePosition(archive, '500', true),
        makePosition(main, '100', false)
      ]);
      // 主列表这条未置顶；不能因为归档那条置顶就误判为已置顶
      expect(isChatPinnedInList(chat, main)).assertFalse();
      expect(isChatPinnedInList(chat, archive)).assertTrue();
    });

  });
}
