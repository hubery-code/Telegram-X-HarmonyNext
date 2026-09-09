import { describe, it, expect } from '@ohos/hypium';
import { ChatRegistry } from '../../main/ets/chatlist/ChatRegistry';
import { Chat } from '@tgx/core-td-api-generated';

export default function chatRegistryTest() {
  describe('ChatRegistry', (): void => {
    it('should store and retrieve chats', 0, (): void => {
      const registry = new ChatRegistry();
      const chat = new Chat();
      chat.id = 12345;
      chat.title = 'Test Chat';
      
      registry.putChat(chat);
      const retrieved = registry.getChat(12345);
      
      expect(retrieved).not().assertUndefined();
      expect(retrieved?.title).assertEqual('Test Chat');
      
      registry.removeChat(12345);
      expect(registry.getChat(12345)).assertUndefined();
    });
  });
}
