import { describe, it, expect, beforeEach } from '@ohos/hypium';
import { ChatListProjection, chatListEquals, compareChatOrder } from '../../main/ets/chatlist/ChatListProjection';
import { ChatRegistry } from '../../main/ets/chatlist/ChatRegistry';
import { Chat, ChatListMain, ChatListArchive, ChatPosition } from '@tgx/core-td-api-generated';

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

  });
}
