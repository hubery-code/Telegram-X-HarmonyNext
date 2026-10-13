/**
 * core/domain — ChatHeaderCache 单元测试（CHATHEADER-102）。
 */

import { describe, it, expect, beforeEach } from '@ohos/hypium';
import { ChatHeaderCache, ChatHeaderSnapshot } from '../../main/ets/chat/ChatHeaderCache';

export default function chatHeaderCacheTest(): void {
  describe('ChatHeaderCache', (): void => {
    beforeEach((): void => {
      ChatHeaderCache.clear();
    });

    it('get_returnsNullWhenEmpty', 0, (): void => {
      expect(ChatHeaderCache.get('acc1', 1001)).assertNull();
    });

    it('put_and_get_storesSnapshotByAccountAndChatId', 0, (): void => {
      const snapshot: ChatHeaderSnapshot = {
        memberCount: 500,
        onlineMemberCount: 25,
        isChannel: false,
        chatKind: 'group',
        supergroupId: 101,
        basicGroupId: 0
      };

      ChatHeaderCache.put('acc1', 1001, snapshot);
      const res: ChatHeaderSnapshot | null = ChatHeaderCache.get('acc1', 1001);
      expect(res).not().assertNull();
      if (res !== null) {
        expect(res.memberCount).assertEqual(500);
        expect(res.onlineMemberCount).assertEqual(25);
        expect(res.chatKind).assertEqual('group');
        expect(res.supergroupId).assertEqual(101);
      }

      // 账号隔离
      expect(ChatHeaderCache.get('acc2', 1001)).assertNull();
      // 会话隔离
      expect(ChatHeaderCache.get('acc1', 1002)).assertNull();
    });

    it('updateMemberCount_createsOrUpdatesPreservingOnlineCount', 0, (): void => {
      ChatHeaderCache.updateOnlineMemberCount('acc1', 1001, 30);
      ChatHeaderCache.updateMemberCount('acc1', 1001, 600);

      const res: ChatHeaderSnapshot | null = ChatHeaderCache.get('acc1', 1001);
      expect(res).not().assertNull();
      if (res !== null) {
        expect(res.memberCount).assertEqual(600);
        expect(res.onlineMemberCount).assertEqual(30);
      }

      // 负数或 0 忽略
      ChatHeaderCache.updateMemberCount('acc1', 1001, 0);
      ChatHeaderCache.updateMemberCount('acc1', 1001, -5);
      const unchanged: ChatHeaderSnapshot | null = ChatHeaderCache.get('acc1', 1001);
      expect(unchanged?.memberCount).assertEqual(600);
    });

    it('updateOnlineMemberCount_ignoresZeroOrNegativeToKeepAlive', 0, (): void => {
      ChatHeaderCache.updateMemberCount('acc1', 1001, 600);
      ChatHeaderCache.updateOnlineMemberCount('acc1', 1001, 45);

      // TDLib 在关闭会话时推送 0，不应冲掉缓存中的真值
      ChatHeaderCache.updateOnlineMemberCount('acc1', 1001, 0);
      ChatHeaderCache.updateOnlineMemberCount('acc1', 1001, -1);

      const res: ChatHeaderSnapshot | null = ChatHeaderCache.get('acc1', 1001);
      expect(res?.onlineMemberCount).assertEqual(45);
    });

    it('clear_withAccountKey_cleansOnlyThatAccount', 0, (): void => {
      ChatHeaderCache.updateMemberCount('acc1', 1001, 100);
      ChatHeaderCache.updateMemberCount('acc2', 1001, 200);

      ChatHeaderCache.clear('acc1');
      expect(ChatHeaderCache.get('acc1', 1001)).assertNull();
      expect(ChatHeaderCache.get('acc2', 1001)?.memberCount).assertEqual(200);
    });

    it('remove_removesSpecificChat', 0, (): void => {
      ChatHeaderCache.updateMemberCount('acc1', 1001, 100);
      ChatHeaderCache.updateMemberCount('acc1', 1002, 200);

      ChatHeaderCache.remove('acc1', 1001);
      expect(ChatHeaderCache.get('acc1', 1001)).assertNull();
      expect(ChatHeaderCache.get('acc1', 1002)?.memberCount).assertEqual(200);
    });
  });
}
