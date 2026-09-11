import { describe, it, expect } from '@ohos/hypium';
import {
  ChatTypeBasicGroup,
  ChatTypePrivate,
  ChatTypeSupergroup,
  MessageSenderChat,
  MessageSenderUser,
  TdMessageSender,
  User
} from '@tgx/core-td-api-generated';
import {
  avatarLettersForName,
  chatKindOf,
  nameColorForIndex,
  NAME_PALETTE,
  resolveSenderInfo,
  SenderInfo,
  SenderInfoDeps
} from '../main/ets/model/SenderInfo';

function makeUser(userId: number, firstName: string, lastName: string = ''): User {
  const user = new User();
  user.id = userId;
  user.first_name = firstName;
  user.last_name = lastName;
  return user;
}

function makeSenderUser(userId: number): MessageSenderUser {
  const sender = new MessageSenderUser();
  sender.user_id = userId;
  return sender;
}

function makeSenderChat(chatId: number): MessageSenderChat {
  const sender = new MessageSenderChat();
  sender.chat_id = chatId;
  return sender;
}

/** 记录 requestUser 调用的假依赖。 */
class FakeDeps implements SenderInfoDeps {
  users: Map<number, User> = new Map();
  requestedIds: number[] = [];

  lookupUser(userId: number): User | null {
    const user: User | undefined = this.users.get(userId);
    return user !== undefined ? user : null;
  }

  requestUser(userId: number): void {
    this.requestedIds.push(userId);
  }
}

export default function senderInfoTest() {
  describe('SenderInfoTest', () => {
    it('chatKindOf_mapsChatTypes', 0, () => {
      expect(chatKindOf(new ChatTypePrivate())).assertEqual('private');
      expect(chatKindOf(new ChatTypeBasicGroup())).assertEqual('group');
      const group = new ChatTypeSupergroup();
      group.is_channel = false;
      expect(chatKindOf(group)).assertEqual('group');
      const channel = new ChatTypeSupergroup();
      channel.is_channel = true;
      expect(chatKindOf(channel)).assertEqual('channel');
      expect(chatKindOf(null)).assertEqual('unknown');
    });

    it('privateChat_noSenderInfo', 0, () => {
      const deps = new FakeDeps();
      deps.users.set(7, makeUser(7, 'Alice'));
      const info: SenderInfo =
        resolveSenderInfo(false, 'private', makeSenderUser(7), deps);
      expect(info.name).assertEqual('');
      expect(info.colorIndex).assertEqual(-1);
      expect(deps.requestedIds.length).assertEqual(0);
    });

    it('outgoingMessage_noSenderInfo', 0, () => {
      const deps = new FakeDeps();
      deps.users.set(7, makeUser(7, 'Alice'));
      const info: SenderInfo =
        resolveSenderInfo(true, 'group', makeSenderUser(7), deps);
      expect(info.name).assertEqual('');
      expect(info.colorIndex).assertEqual(-1);
      expect(deps.requestedIds.length).assertEqual(0);
    });

    it('senderChat_noSenderInfo', 0, () => {
      // 频道身份发帖：署名留空（频道名已在导航栏）。
      const deps = new FakeDeps();
      const info: SenderInfo =
        resolveSenderInfo(false, 'group', makeSenderChat(100), deps);
      expect(info.name).assertEqual('');
      expect(info.colorIndex).assertEqual(-1);
      expect(deps.requestedIds.length).assertEqual(0);
    });

    it('groupHitCache_resolvesNameAndColor', 0, () => {
      const deps = new FakeDeps();
      deps.users.set(7, makeUser(7, 'Alice', 'Wong'));
      const info: SenderInfo =
        resolveSenderInfo(false, 'group', makeSenderUser(7), deps);
      expect(info.name).assertEqual('Alice Wong');
      expect(info.colorIndex).assertEqual(7 % 7);
      expect(deps.requestedIds.length).assertEqual(0);
    });

    it('groupCacheMiss_returnsEmptyAndRequestsUser', 0, () => {
      const deps = new FakeDeps();
      const info: SenderInfo =
        resolveSenderInfo(false, 'group', makeSenderUser(42), deps);
      expect(info.name).assertEqual('');
      expect(info.colorIndex).assertEqual(-1);
      expect(deps.requestedIds.length).assertEqual(1);
      expect(deps.requestedIds[0]).assertEqual(42);
    });

    it('groupUserWithBlankName_returnsEmpty', 0, () => {
      const deps = new FakeDeps();
      deps.users.set(9, makeUser(9, '', ''));
      const info: SenderInfo =
        resolveSenderInfo(false, 'group', makeSenderUser(9), deps);
      expect(info.name).assertEqual('');
      expect(info.colorIndex).assertEqual(-1);
      expect(deps.requestedIds.length).assertEqual(0);
    });

    it('nullSender_noSenderInfo', 0, () => {
      const deps = new FakeDeps();
      const sender: TdMessageSender | null = null;
      const info: SenderInfo = resolveSenderInfo(false, 'group', sender, deps);
      expect(info.name).assertEqual('');
      expect(deps.requestedIds.length).assertEqual(0);
    });

    it('nameColorForIndex_wrapsIntoPalette', 0, () => {
      expect(NAME_PALETTE.length).assertEqual(7);
      expect(nameColorForIndex(0)).assertEqual(NAME_PALETTE[0]);
      expect(nameColorForIndex(6)).assertEqual(NAME_PALETTE[6]);
      expect(nameColorForIndex(7)).assertEqual(NAME_PALETTE[0]);
    });

    it('avatarLettersForName_extractsInitials', 0, () => {
      expect(avatarLettersForName('Alice Wong')).assertEqual('AW');
      expect(avatarLettersForName('alice')).assertEqual('A');
      expect(avatarLettersForName('  ')).assertEqual('?');
    });
  });
}
