/**
 * core/domain — 会话头部元数据缓存与在线人数 Keep-Alive（CHATHEADER-102）。
 *
 * 解决会话重进时群/频道头部副标题从「空」或「仅成员数」到「成员数+在线人数」的双重闪烁问题：
 * - 缓存条目：按 accountKey + chatId 隔离，维护 memberCount、onlineMemberCount、chatKind、supergroupId、basicGroupId；
 * - 在线人数 Keep-Alive：TDLib 在 closeChat() 时会主动推送 online_member_count = 0，
 *   若直采该值会导致重新进入会话时丢失上一轮已知的在线人数；
 *   本缓存仅在 onlineMemberCount > 0 时刷新真值，保持重进会话首帧即可渲染完整的「成员数, 在线人数」；
 * - 纯 ArkTS / 100% Kit-free。
 */

export interface ChatHeaderSnapshot {
  memberCount: number;
  onlineMemberCount: number;
  isChannel: boolean;
  chatKind?: string;
  supergroupId?: number;
  basicGroupId?: number;
}

export class ChatHeaderCache {
  private static readonly snapshots: Map<string, ChatHeaderSnapshot> = new Map();

  private static key(accountKey: string, chatId: number): string {
    return `${accountKey}:${chatId}`;
  }

  public static get(accountKey: string, chatId: number): ChatHeaderSnapshot | null {
    const found: ChatHeaderSnapshot | undefined = ChatHeaderCache.snapshots.get(ChatHeaderCache.key(accountKey, chatId));
    return found !== undefined ? found : null;
  }

  public static put(accountKey: string, chatId: number, snapshot: ChatHeaderSnapshot): void {
    ChatHeaderCache.snapshots.set(ChatHeaderCache.key(accountKey, chatId), snapshot);
  }

  public static updateMemberCount(accountKey: string, chatId: number, memberCount: number): void {
    if (memberCount <= 0) {
      return;
    }
    const k: string = ChatHeaderCache.key(accountKey, chatId);
    const existing: ChatHeaderSnapshot | undefined = ChatHeaderCache.snapshots.get(k);
    if (existing !== undefined) {
      existing.memberCount = memberCount;
    } else {
      ChatHeaderCache.snapshots.set(k, {
        memberCount: memberCount,
        onlineMemberCount: 0,
        isChannel: false
      });
    }
  }

  public static updateOnlineMemberCount(accountKey: string, chatId: number, onlineMemberCount: number): void {
    if (onlineMemberCount <= 0) {
      return;
    }
    const k: string = ChatHeaderCache.key(accountKey, chatId);
    const existing: ChatHeaderSnapshot | undefined = ChatHeaderCache.snapshots.get(k);
    if (existing !== undefined) {
      existing.onlineMemberCount = onlineMemberCount;
    } else {
      ChatHeaderCache.snapshots.set(k, {
        memberCount: 0,
        onlineMemberCount: onlineMemberCount,
        isChannel: false
      });
    }
  }

  public static remove(accountKey: string, chatId: number): void {
    ChatHeaderCache.snapshots.delete(ChatHeaderCache.key(accountKey, chatId));
  }

  public static clear(accountKey?: string): void {
    if (accountKey === undefined || accountKey.length === 0) {
      ChatHeaderCache.snapshots.clear();
      return;
    }
    const prefix: string = `${accountKey}:`;
    const keysToDelete: string[] = [];
    ChatHeaderCache.snapshots.forEach((_val: ChatHeaderSnapshot, k: string) => {
      if (k.startsWith(prefix)) {
        keysToDelete.push(k);
      }
    });
    for (let i = 0; i < keysToDelete.length; i++) {
      ChatHeaderCache.snapshots.delete(keysToDelete[i]);
    }
  }
}
