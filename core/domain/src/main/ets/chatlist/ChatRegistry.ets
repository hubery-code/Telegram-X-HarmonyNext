import { Chat } from '@tgx/core-td-api-generated';

/**
 * 全局的会话注册表，存放单账号下的所有 Chat 对象实体。
 * 由 Domain 层维护并作为单一事实源。
 */
export class ChatRegistry {
  private chats: Map<number, Chat> = new Map();

  getChat(chatId: number): Chat | undefined {
    return this.chats.get(chatId);
  }

  putChat(chat: Chat): void {
    this.chats.set(chat.id, chat);
  }

  removeChat(chatId: number): void {
    this.chats.delete(chatId);
  }

  clear(): void {
    this.chats.clear();
  }
}
