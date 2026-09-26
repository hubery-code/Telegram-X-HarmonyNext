/**
 * feature/settings — 隐私模型层单测（SELF-102 键序 + PRIVACY-101 规则列表语义 + PRIVACY-102 会话成员例外）。
 *
 * 覆盖的是「读得准、改不坏」两件事：
 * 1. 解析：单条简单规则 → 对应档位；带例外名单仍是主档位 + 名单，不再被归成不可写的 custom；
 *    空列表 = nobody（设备实测：写 restrictAll 后 TDLib 读回 rules=[]）；
 * 2. 终结性：allowAll / restrictAll 之后的规则不参与判定；
 * 3. 改档：例外名单原样保留（这是本包最关键的一条语义，旧版会抹掉）；bots 规则不动；
 * 4. 例外名单：人和会话各自全量替换、另一侧同名 id 被摘掉，两条例外规则的**插入位置不同**；
 * 5. 人数口径：会话按**成员数**计，不是按会话条数（Android `getPlusTotalCount`）；
 * 6. dirty 判定：privacyRulesEqual 按序列化结果比，不按引用；
 * 7. 候选行：频道不可进选择器，成员数读不到时记 0（页面据此不编文案）；
 * 8. 逐项门禁：「通过手机号发现我」没有「没有人」档也没有例外名单，「最后上线时间」两行读「分享给谁」；
 * 9. 8 个设置项的键序与 setting 对象映射（防止写回时张冠李戴）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  Chat,
  ChatTypeBasicGroup,
  ChatTypePrivate,
  ChatTypeSupergroup,
  TdJsonRaw,
  TdUserPrivacySettingRule,
  UserPrivacySettingRules,
  UserPrivacySettingRuleAllowAll,
  UserPrivacySettingRuleAllowBots,
  UserPrivacySettingRuleAllowChatMembers,
  UserPrivacySettingRuleAllowContacts,
  UserPrivacySettingRuleAllowPremiumUsers,
  UserPrivacySettingRuleAllowUsers,
  UserPrivacySettingRuleRestrictAll,
  UserPrivacySettingRuleRestrictChatMembers,
  UserPrivacySettingRuleRestrictUsers,
  decodeUserPrivacySettingRules,
  encodeUserPrivacySettingRules,
  encodeGetUserPrivacySettingRules,
  GetUserPrivacySettingRules
} from '@tgx/core-td-api-generated';
import {
  PrivacySettingItem,
  PrivacySettingKey,
  PRIVACY_SETTING_KEYS,
  privacyAlwaysAllowLabel,
  privacyNeedNobodyOption,
  privacyNeedExceptions,
  privacyNeverAllowLabel,
  privacyNeedsPremiumRow,
  privacyNeedsReadDateRow,
  privacyPremiumForMode,
  privacyRowLabel,
  privacySettingLabel,
  toUserPrivacySetting
} from '../main/ets/model/PrivacySettings';
import {
  PrivacyMode,
  PrivacyRulesView,
  parsePrivacyRules,
  privacyAlwaysAllowCount,
  privacyMembersOf,
  privacyModeLabel,
  privacyNeedAlwaysAllow,
  privacyNeedNeverAllow,
  privacyNeedsHideReadTime,
  privacyNeverAllowCount,
  privacyRulesForMode,
  privacyRulesWithAllowExceptions,
  privacyRulesWithPremium,
  privacyRulesWithRestrictExceptions
} from '../main/ets/model/PrivacyRules';
import {
  PrivacyChatRow,
  PrivacyContactRow,
  PrivacyDetailState,
  PrivacyExceptionsView,
  privacyChatsWithPicked,
  privacyChatMemberCounts,
  privacyChatRows,
  privacyChatSelectable,
  privacyContactsWithPicked,
  privacyExceptionsView,
  privacyRulesEqual
} from '../main/ets/model/PrivacyDetail';

function ruleAllowAll(): TdUserPrivacySettingRule {
  return new UserPrivacySettingRuleAllowAll();
}

function ruleAllowContacts(): TdUserPrivacySettingRule {
  return new UserPrivacySettingRuleAllowContacts();
}

function ruleAllowPremium(): TdUserPrivacySettingRule {
  return new UserPrivacySettingRuleAllowPremiumUsers();
}

function ruleRestrictAll(): TdUserPrivacySettingRule {
  return new UserPrivacySettingRuleRestrictAll();
}

function ruleAllowBots(): TdUserPrivacySettingRule {
  return new UserPrivacySettingRuleAllowBots();
}

function ruleAllowUsers(ids: number[]): TdUserPrivacySettingRule {
  const rule: UserPrivacySettingRuleAllowUsers = new UserPrivacySettingRuleAllowUsers();
  rule.user_ids = ids;
  return rule;
}

function ruleRestrictUsers(ids: number[]): TdUserPrivacySettingRule {
  const rule: UserPrivacySettingRuleRestrictUsers = new UserPrivacySettingRuleRestrictUsers();
  rule.user_ids = ids;
  return rule;
}

function ruleAllowChatMembers(ids: number[]): TdUserPrivacySettingRule {
  const rule: UserPrivacySettingRuleAllowChatMembers =
    new UserPrivacySettingRuleAllowChatMembers();
  rule.chat_ids = ids;
  return rule;
}

function ruleRestrictChatMembers(ids: number[]): TdUserPrivacySettingRule {
  const rule: UserPrivacySettingRuleRestrictChatMembers =
    new UserPrivacySettingRuleRestrictChatMembers();
  rule.chat_ids = ids;
  return rule;
}

/** 「我的联系人，但排除某人」——TDLib 真实会读回来的形状。 */
function contactsExceptUsers(): TdUserPrivacySettingRule[] {
  return [ruleRestrictUsers([2002]), ruleAllowContacts(), ruleRestrictAll()];
}

function typesOf(rules: TdUserPrivacySettingRule[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < rules.length; i++) {
    out.push(rules[i].type);
  }
  return out;
}

function idsOf(rule: TdUserPrivacySettingRule): number[] {
  if (rule.type === 'userPrivacySettingRuleAllowUsers') {
    return (rule as UserPrivacySettingRuleAllowUsers).user_ids;
  }
  if (rule.type === 'userPrivacySettingRuleRestrictUsers') {
    return (rule as UserPrivacySettingRuleRestrictUsers).user_ids;
  }
  return [];
}

function chatIdsOf(rule: TdUserPrivacySettingRule): number[] {
  if (rule.type === 'userPrivacySettingRuleAllowChatMembers') {
    return (rule as UserPrivacySettingRuleAllowChatMembers).chat_ids;
  }
  if (rule.type === 'userPrivacySettingRuleRestrictChatMembers') {
    return (rule as UserPrivacySettingRuleRestrictChatMembers).chat_ids;
  }
  return [];
}

function contact(userId: number, title: string): PrivacyContactRow {
  return new PrivacyContactRow(userId, title, false);
}

function chatRow(chatId: number, title: string, memberCount: number): PrivacyChatRow {
  return new PrivacyChatRow(chatId, title, memberCount, false);
}

function basicGroupChat(chatId: number, title: string): Chat {
  const chat: Chat = new Chat();
  chat.id = chatId;
  chat.title = title;
  chat.type_ = new ChatTypeBasicGroup();
  return chat;
}

function supergroupChat(chatId: number, title: string, isChannel: boolean): Chat {
  const chat: Chat = new Chat();
  chat.id = chatId;
  chat.title = title;
  const type: ChatTypeSupergroup = new ChatTypeSupergroup();
  type.is_channel = isChannel;
  chat.type_ = type;
  return chat;
}

function privateChat(chatId: number): Chat {
  const chat: Chat = new Chat();
  chat.id = chatId;
  chat.type_ = new ChatTypePrivate();
  return chat;
}

function counts(pairs: PrivacyChatRow[]): Map<number, number> {
  return privacyChatMemberCounts(pairs);
}

export default function privacySettingsTest(): void {
  describe('PrivacySettingsTest', () => {
    it('parse_mapsSingleSimpleRules', 0, () => {
      expect(parsePrivacyRules([ruleAllowAll()]).mode).assertEqual('everybody');
      expect(parsePrivacyRules([ruleAllowContacts()]).mode).assertEqual('contacts');
      expect(parsePrivacyRules([ruleAllowPremium(), ruleAllowContacts()]).mode).assertEqual('contacts');
      expect(parsePrivacyRules([ruleRestrictAll()]).mode).assertEqual('nobody');
    });

    it('parse_keepsMainModeWithExceptionLists', 0, () => {
      // 旧版把这种列表归成不可写的 custom；PRIVACY-101 之后主档位照读，例外名单单独呈现。
      const view: PrivacyRulesView = parsePrivacyRules(contactsExceptUsers());
      expect(view.mode).assertEqual('contacts');
      expect(view.minusUserIds.length).assertEqual(1);
      expect(view.minusUserIds[0]).assertEqual(2002);
      expect(view.plusUserIds.length).assertEqual(0);
    });

    it('parse_readsPremiumAsFlagNotMode', 0, () => {
      expect(parsePrivacyRules([ruleAllowPremium()]).plusPremium).assertTrue();
      expect(parsePrivacyRules([ruleAllowPremium()]).mode).assertEqual('nobody');
      expect(parsePrivacyRules([ruleAllowPremium(), ruleAllowContacts()]).plusPremium).assertTrue();
    });

    it('parse_emptyListMeansNobody', 0, () => {
      // 设备实测：show_birthdate 写入 restrictAll 后 TDLib 读回 rules=[]。
      expect(parsePrivacyRules([]).mode).assertEqual('nobody');
    });

    it('parse_terminalRulesStopTheScan', 0, () => {
      // allowAll 之后的规则 TDLib 永不匹配到，所以既不能翻转档位，也不算进例外名单：
      // 这一条 restrictUsers 是历史残留，页面上它本来就不生效，跟着一起归零才是真话。
      expect(parsePrivacyRules([ruleAllowAll(), ruleRestrictUsers([2002])]).mode)
        .assertEqual('everybody');
      expect(parsePrivacyRules([ruleAllowAll(), ruleRestrictUsers([2002])]).minusUserIds.length)
        .assertEqual(0);
      // 但终结性只翻转「没读过主档位」的情况：`[allowContacts, restrictAll]` 是「我的联系人」
      // 的标准形状（先放行联系人，其余人落到 restrictAll），不能被读成「没有人」。
      expect(parsePrivacyRules([ruleAllowContacts(), ruleRestrictAll()]).mode)
        .assertEqual('contacts');
      expect(parsePrivacyRules([ruleRestrictUsers([2002]), ruleRestrictAll()]).mode)
        .assertEqual('nobody');
    });

    it('parse_countsChatMemberExceptionsSeparately', 0, () => {
      const view: PrivacyRulesView = parsePrivacyRules([
        ruleAllowUsers([1001]),
        ruleAllowChatMembers([7001, 7002]),
        ruleRestrictUsers([2002]),
        ruleRestrictChatMembers([8001]),
        ruleAllowContacts(),
        ruleRestrictAll()
      ]);
      // 没有成员数时会话按 0 计：宁可少报也不按「条数」编一个人数。
      expect(privacyAlwaysAllowCount(view, new Map<number, number>())).assertEqual(1);
      expect(privacyNeverAllowCount(view, new Map<number, number>())).assertEqual(1);
      expect(view.plusChatIds.length).assertEqual(2);
      expect(view.minusChatIds.length).assertEqual(1);
    });

    it('rulesForMode_keepsExceptionLists', 0, () => {
      // 本包最关键的一条语义：从「我的联系人」切到「所有人」不能抹掉「从不允许」名单。
      const next: TdUserPrivacySettingRule[] = privacyRulesForMode(
        contactsExceptUsers(), 'everybody', false
      );
      expect(next.length).assertEqual(2);
      expect(next[0].type).assertEqual('userPrivacySettingRuleRestrictUsers');
      expect(next[1].type).assertEqual('userPrivacySettingRuleAllowAll');
    });

    it('rulesForMode_keepsChatMemberExceptions', 0, () => {
      const next: TdUserPrivacySettingRule[] = privacyRulesForMode(
        [ruleRestrictChatMembers([8001]), ruleAllowContacts(), ruleRestrictAll()],
        'everybody', false
      );
      expect(typesOf(next).join('>')).assertEqual(
        'userPrivacySettingRuleRestrictChatMembers>userPrivacySettingRuleAllowAll'
      );
    });

    it('rulesForMode_rebuildsGeneralRulesAtTheEnd', 0, () => {
      const contacts: TdUserPrivacySettingRule[] = privacyRulesForMode(
        [ruleAllowUsers([1001])], 'contacts', true
      );
      expect(typesOf(contacts).join('>')).assertEqual(
        'userPrivacySettingRuleAllowUsers>userPrivacySettingRuleAllowPremiumUsers' +
        '>userPrivacySettingRuleAllowContacts>userPrivacySettingRuleRestrictAll'
      );
    });

    it('rulesForMode_sendsEmptyListForNobodyWithoutExceptions', 0, () => {
      // TDLib 对「没有人」读回的就是空列表；例外名单非空时才要显式 restrictAll 兜底。
      expect(privacyRulesForMode([ruleAllowContacts(), ruleRestrictAll()], 'nobody', false).length)
        .assertEqual(0);
      const kept: TdUserPrivacySettingRule[] = privacyRulesForMode(
        contactsExceptUsers(), 'nobody', false
      );
      expect(kept[kept.length - 1].type).assertEqual('userPrivacySettingRuleRestrictAll');
    });

    it('rulesForMode_leavesBotsRuleInPlace', 0, () => {
      // 有意偏离 Android：本端界面没有 bots 行，改档时重写它等于在看不见的维度上下副作用。
      const next: TdUserPrivacySettingRule[] = privacyRulesForMode(
        [ruleAllowBots(), ruleAllowContacts(), ruleRestrictAll()], 'everybody', false
      );
      expect(next[0].type).assertEqual('userPrivacySettingRuleAllowBots');
    });

    it('rulesWithAllowUsers_replacesAndMovesToFront', 0, () => {
      const next: TdUserPrivacySettingRule[] = privacyRulesWithAllowExceptions(
        [ruleAllowUsers([999]), ruleAllowContacts(), ruleRestrictAll()], [1001, 1002], []
      );
      expect(next[0].type).assertEqual('userPrivacySettingRuleAllowUsers');
      expect(idsOf(next[0]).join(',')).assertEqual('1001,1002');
      expect(next.length).assertEqual(3);
    });

    it('rulesWithAllowUsers_stripsSamePeopleFromOtherSide', 0, () => {
      // 同一个人不能既总是允许又从不允许。
      const next: TdUserPrivacySettingRule[] = privacyRulesWithAllowExceptions(
        [ruleRestrictUsers([1001, 2002]), ruleAllowContacts(), ruleRestrictAll()], [1001], []
      );
      expect(next[0].type).assertEqual('userPrivacySettingRuleAllowUsers');
      expect(next[1].type).assertEqual('userPrivacySettingRuleRestrictUsers');
      expect(idsOf(next[1]).join(',')).assertEqual('2002');
      expect(next.length).assertEqual(4);
    });

    it('rulesWithAllowUsers_dropsEmptiedOppositeRule', 0, () => {
      const next: TdUserPrivacySettingRule[] = privacyRulesWithAllowExceptions(
        [ruleRestrictUsers([1001]), ruleAllowContacts(), ruleRestrictAll()], [1001], []
      );
      expect(next.length).assertEqual(3);
      expect(next[0].type).assertEqual('userPrivacySettingRuleAllowUsers');
      expect(next[1].type).assertEqual('userPrivacySettingRuleAllowContacts');
    });

    it('rulesWithAllowUsers_emptyPickMeansNoException', 0, () => {
      const next: TdUserPrivacySettingRule[] = privacyRulesWithAllowExceptions(
        [ruleAllowUsers([1001]), ruleAllowContacts(), ruleRestrictAll()], [], []
      );
      expect(next.length).assertEqual(2);
      expect(next[0].type).assertEqual('userPrivacySettingRuleAllowContacts');
    });

    /**
     * PRIVACY-102 的核心：两条例外规则的**插入位置不同**（Android 830-861 与 900-905 各自一套）。
     * allowChatMembers 要排在主档位之前、但允许排在 allowContacts 之后（TDLib 逐条判定，
     * 联系人规则不命中陌生人时仍会走到它）；用户名单永远在最前。
     */
    it('rulesWithAllowExceptions_insertsChatRuleBeforeTerminalGeneralRule', 0, () => {
      const next: TdUserPrivacySettingRule[] = privacyRulesWithAllowExceptions(
        [ruleAllowUsers([1001]), ruleAllowContacts(), ruleRestrictAll()], [1001], [7001]
      );
      expect(typesOf(next).join('>')).assertEqual(
        'userPrivacySettingRuleAllowUsers>userPrivacySettingRuleAllowContacts' +
        '>userPrivacySettingRuleAllowChatMembers>userPrivacySettingRuleRestrictAll'
      );
      expect(chatIdsOf(next[2]).join(',')).assertEqual('7001');
    });

    it('rulesWithRestrictExceptions_insertsChatRuleRightAfterUserRule', 0, () => {
      // restrict 侧的索引判定把 premium/bots/chatMembers 都当 general，于是只有 users 类规则让位。
      const next: TdUserPrivacySettingRule[] = privacyRulesWithRestrictExceptions(
        [ruleAllowUsers([1001]), ruleAllowContacts(), ruleRestrictAll()], [], [8001]
      );
      expect(typesOf(next).join('>')).assertEqual(
        'userPrivacySettingRuleAllowUsers>userPrivacySettingRuleRestrictChatMembers' +
        '>userPrivacySettingRuleAllowContacts>userPrivacySettingRuleRestrictAll'
      );
    });

    it('rulesWithAllowExceptions_keepsOppositeChatRuleDirection', 0, () => {
      // 名单里同一个群从「从不允许」搬到「总是允许」：对侧只剩没被勾选的那个，方向不变。
      const next: TdUserPrivacySettingRule[] = privacyRulesWithAllowExceptions(
        [ruleRestrictChatMembers([7001, 8001]), ruleAllowContacts(), ruleRestrictAll()],
        [], [7001]
      );
      expect(next[0].type).assertEqual('userPrivacySettingRuleRestrictChatMembers');
      expect(chatIdsOf(next[0]).join(',')).assertEqual('8001');
      expect(next[2].type).assertEqual('userPrivacySettingRuleAllowChatMembers');
      expect(chatIdsOf(next[2]).join(',')).assertEqual('7001');
    });

    it('rulesWithAllowUsers_dropsEmptiedOppositeChatRule', 0, () => {
      const next: TdUserPrivacySettingRule[] = privacyRulesWithAllowExceptions(
        [ruleRestrictChatMembers([7001]), ruleAllowContacts(), ruleRestrictAll()], [], [7001]
      );
      expect(typesOf(next).join('>')).assertEqual(
        'userPrivacySettingRuleAllowContacts>userPrivacySettingRuleAllowChatMembers' +
        '>userPrivacySettingRuleRestrictAll'
      );
    });

    it('exceptionRewrite_doesNotMutateSavedSnapshot', 0, () => {
      // 旧列表还挂在 savedRules 上；就地改 user_ids 会把「有没有未保存的编辑」抹平。
      const original: TdUserPrivacySettingRule[] = [
        ruleRestrictUsers([1001, 2002]), ruleRestrictChatMembers([7001, 8001]),
        ruleAllowContacts(), ruleRestrictAll()
      ];
      const snapshot: TdUserPrivacySettingRule[] = original.slice();
      privacyRulesWithAllowExceptions(original, [1001], [7001]);
      expect(idsOf(original[0]).join(',')).assertEqual('1001,2002');
      expect(chatIdsOf(original[1]).join(',')).assertEqual('7001,8001');
      expect(privacyRulesEqual(original, snapshot)).assertTrue();
    });

    it('rulesWithRestrictUsers_isMirrorImage', 0, () => {
      const next: TdUserPrivacySettingRule[] = privacyRulesWithRestrictExceptions(
        [ruleAllowUsers([1001, 2002]), ruleAllowContacts(), ruleRestrictAll()], [1001], []
      );
      expect(next[0].type).assertEqual('userPrivacySettingRuleRestrictUsers');
      expect(idsOf(next[0]).join(',')).assertEqual('1001');
      expect(idsOf(next[1]).join(',')).assertEqual('2002');
    });

    it('needAlwaysAllow_andNeedNeverAllow_followMode', 0, () => {
      expect(privacyNeedAlwaysAllow([ruleAllowContacts(), ruleRestrictAll()])).assertTrue();
      expect(privacyNeedNeverAllow(parsePrivacyRules([ruleAllowContacts(), ruleRestrictAll()])))
        .assertTrue();
      // nobody 档下「从不允许」无意义；everybody 档下只剩「从不允许」。
      expect(privacyNeedNeverAllow(parsePrivacyRules([]))).assertFalse();
      expect(privacyNeedAlwaysAllow([ruleAllowAll()])).assertFalse();
      expect(privacyNeedNeverAllow(parsePrivacyRules([ruleAllowAll()]))).assertTrue();
      // restrictChatMembers 先于主档位出现时，它属于「从不允许」那一侧，always 行仍要在。
      expect(privacyNeedAlwaysAllow([ruleRestrictChatMembers([8001]), ruleAllowAll()])).assertTrue();
    });

    it('membersOf_sumsMemberCountsAndTreatsUnknownAsZero', 0, () => {
      // Android `getPlusTotalCount`：一条 300 人的群就是 300，不是 1。
      const map: Map<number, number> = counts([chatRow(7001, 'El CLUB', 300), chatRow(7002, 'x', 0)]);
      expect(privacyMembersOf([7001, 7002, 9999], map)).assertEqual(300);
      expect(privacyMembersOf([], map)).assertEqual(0);
    });

    it('alwaysAllowCount_addsUsersAndChatMembers', 0, () => {
      const view: PrivacyRulesView = parsePrivacyRules([
        ruleAllowUsers([1001, 1002]),
        ruleAllowChatMembers([7001, 7002]),
        ruleAllowContacts(),
        ruleRestrictAll()
      ]);
      const map: Map<number, number> = counts([chatRow(7001, 'El CLUB', 300), chatRow(7002, 'small', 5)]);
      expect(privacyAlwaysAllowCount(view, map)).assertEqual(307);
      expect(privacyNeverAllowCount(view, map)).assertEqual(0);
    });

    it('rulesEqual_comparesByContentNotReference', 0, () => {
      expect(privacyRulesEqual([], [])).assertTrue();
      expect(privacyRulesEqual([ruleAllowUsers([1, 2])], [ruleAllowUsers([1, 2])])).assertTrue();
      expect(privacyRulesEqual([ruleAllowUsers([1, 2])], [ruleAllowUsers([2, 1])])).assertFalse();
      expect(privacyRulesEqual([ruleAllowAll()], [ruleRestrictAll()])).assertFalse();
      expect(privacyRulesEqual([ruleAllowAll()], [])).assertFalse();
      // 会话例外同一条口径：类型相同、id 顺序不同也算变化。
      expect(privacyRulesEqual(
        [ruleAllowChatMembers([7001, 7002])], [ruleAllowChatMembers([7001, 7002])]
      )).assertTrue();
      expect(privacyRulesEqual(
        [ruleAllowChatMembers([7001])], [ruleRestrictChatMembers([7001])]
      )).assertFalse();
    });

    it('detailState_isDirtyOnlyAfterLocalEdits', 0, () => {
      const loaded: PrivacyDetailState = PrivacyDetailState.forLoaded(
        'show_bio', [ruleAllowContacts(), ruleRestrictAll()], [], []
      );
      expect(loaded.isDirty()).assertFalse();
      const edited: PrivacyDetailState = loaded.copyWith({
        rules: privacyRulesWithAllowExceptions(loaded.rules, [], [7001])
      });
      expect(edited.isDirty()).assertTrue();
      // 原快照不能被改写：UiState 是不可变快照。
      expect(loaded.isDirty()).assertFalse();
      // 会话候选不进 dirty 判定：只是读到了人，没有改规则。
      expect(loaded.copyWith({ chats: [chatRow(7001, 'El CLUB', 300)] }).isDirty()).assertFalse();
    });

    it('modeLabel_usesMergedPremiumLabel', 0, () => {
      const modes: PrivacyMode[] = ['everybody', 'contacts', 'nobody'];
      for (let i = 0; i < modes.length; i++) {
        expect(privacyModeLabel(modes[i], false).length > 0).assertTrue();
      }
      expect(privacyModeLabel('contacts', true)).assertEqual('My Contacts & Premium');
      expect(privacyModeLabel('contacts', false)).assertEqual('My Contacts');
    });

    it('exceptionsView_labelsBothSidesByPosition', 0, () => {
      const view: PrivacyExceptionsView = privacyExceptionsView(
        [ruleAllowUsers([1001]), ruleRestrictUsers([2002]), ruleAllowContacts(), ruleRestrictAll()],
        []
      );
      expect(view.showAlwaysRow).assertTrue();
      expect(view.showNeverRow).assertTrue();
      expect(view.alwaysCount).assertEqual(1);
      expect(view.neverCount).assertEqual(1);
    });

    it('exceptionsView_countsChatMembers', 0, () => {
      // 一行「3 个用户」里可能是 1 个人 + 一个 2 人群：口径必须是成员数。
      const view: PrivacyExceptionsView = privacyExceptionsView(
        [
          ruleAllowUsers([1001]),
          ruleAllowChatMembers([7001]),
          ruleRestrictChatMembers([8001]),
          ruleAllowContacts(),
          ruleRestrictAll()
        ],
        [chatRow(7001, 'El CLUB', 2), chatRow(8001, 'other', 0)]
      );
      expect(view.alwaysCount).assertEqual(3);
      expect(view.neverCount).assertEqual(0);
    });

    it('exceptionsView_everybodyHasNoAlwaysRow', 0, () => {
      const view: PrivacyExceptionsView = privacyExceptionsView(
        [ruleRestrictUsers([2002]), ruleAllowAll()], []
      );
      expect(view.showAlwaysRow).assertFalse();
      expect(view.showNeverRow).assertTrue();
    });

    it('chatRows_skipChannelsAndPrivateChats', 0, () => {
      // Android 的选择器带 FLAG_NO_CHANNELS：「会话成员」只对群成立。
      const rows: PrivacyChatRow[] = privacyChatRows(
        [
          basicGroupChat(7001, '小群'),
          supergroupChat(7002, '大群', false),
          supergroupChat(7003, '公告频道', true),
          privateChat(7004)
        ],
        counts([chatRow(7001, '小群', 4)]),
        [7002]
      );
      expect(rows.length).assertEqual(2);
      expect(rows[0].title).assertEqual('小群');
      expect(rows[0].memberCount).assertEqual(4);
      expect(rows[0].selected).assertFalse();
      expect(rows[1].chatId).assertEqual(7002);
      // 成员数读不到就是 0，页面据此不出人数副标题。
      expect(rows[1].memberCount).assertEqual(0);
      expect(rows[1].selected).assertTrue();
    });

    it('chatTitle_fallsBackWhenUnresolved', 0, () => {
      expect(privacyChatRows([basicGroupChat(7001, '  ')], new Map<number, number>(), [])[0].title)
        .assertEqual('Unknown Chat');
    });

    it('chatSelectable_needsAType', 0, () => {
      const untitled: Chat = new Chat();
      untitled.id = 7001;
      expect(privacyChatSelectable(untitled)).assertFalse();
      expect(privacyChatSelectable(basicGroupChat(0, 'x'))).assertFalse();
      expect(privacyChatSelectable(basicGroupChat(7001, 'x'))).assertTrue();
      expect(privacyChatSelectable(supergroupChat(7002, 'x', false))).assertTrue();
      expect(privacyChatSelectable(supergroupChat(7003, 'x', true))).assertFalse();
    });

    it('contactRows_rebuildSelectionFromPickedIds', 0, () => {
      // 选择器的勾选态只有一个来源：pickedUserIds → row.selected。
      const source: PrivacyContactRow[] = [contact(1001, 'Ada'), contact(2002, 'Lin')];
      const rows: PrivacyContactRow[] = privacyContactsWithPicked(source, [2002]);
      expect(rows.length).assertEqual(2);
      expect(rows[0].selected).assertFalse();
      expect(rows[1].selected).assertTrue();

      const cleared: PrivacyContactRow[] = privacyContactsWithPicked(rows, []);
      expect(cleared[1].selected).assertFalse();
      // 未勾选的行原对象复用（withSelected 同值即返回 this），页面键因此稳定。
      expect(cleared[0] === source[0]).assertTrue();
    });

    it('chatRows_rebuildSelectionWithoutLosingMemberCount', 0, () => {
      const source: PrivacyChatRow[] = [chatRow(7001, 'El CLUB', 300)];
      const rows: PrivacyChatRow[] = privacyChatsWithPicked(source, [7001]);
      expect(rows[0].selected).assertTrue();
      expect(rows[0].memberCount).assertEqual(300);
      // 同值即复用，ForEach 的键才稳定。
      expect(privacyChatsWithPicked(rows, [7001])[0] === rows[0]).assertTrue();
      // 勾选变了才新建：换回来的行仍然带着成员数（不重新请求 group）。
      const cleared: PrivacyChatRow[] = privacyChatsWithPicked(rows, []);
      expect(cleared[0] === source[0]).assertFalse();
      expect(cleared[0].selected).assertFalse();
      expect(cleared[0].memberCount).assertEqual(300);
      expect(privacyChatsWithPicked(source, [])[0] === source[0]).assertTrue();
    });

    it('contactRow_withSelected_isIdentityWhenUnchanged', 0, () => {
      const row: PrivacyContactRow = new PrivacyContactRow(1001, 'Ada', true);
      expect(row.withSelected(true) === row).assertTrue();
      const next: PrivacyContactRow = row.withSelected(false);
      expect(next !== row).assertTrue();
      expect(next.selected).assertFalse();
      expect(row.selected).assertTrue();
    });

    it('findingByPhone_hasNoNobodyModeAndNoExceptions', 0, () => {
      // Android `needNobodyOption()` / `needExceptions()`：禁止「没人能通过号码找到我」无意义，
      // 因此这一项既没有第三档也没有例外名单 —— 其余 7 项两者齐备。
      expect(privacyNeedNobodyOption('allow_find_by_phone')).assertFalse();
      expect(privacyNeedExceptions('allow_find_by_phone')).assertFalse();
      for (let i = 0; i < PRIVACY_SETTING_KEYS.length; i++) {
        const key: PrivacySettingKey = PRIVACY_SETTING_KEYS[i];
        if (key === 'allow_find_by_phone') {
          continue;
        }
        expect(privacyNeedNobodyOption(key)).assertTrue();
        expect(privacyNeedExceptions(key)).assertTrue();
      }
    });

    it('lastSeen_exceptionRowsReadAsShareWith', 0, () => {
      expect(privacyAlwaysAllowLabel('show_last_seen')).assertEqual('Always Share With');
      expect(privacyNeverAllowLabel('show_last_seen')).assertEqual('Never Share With');
      expect(privacyAlwaysAllowLabel('show_bio')).assertEqual('Always Allow');
      expect(privacyNeverAllowLabel('show_bio')).assertEqual('Never Allow');
    });

    it('privacySettingKeys_areEightDistinctRows', 0, () => {
      expect(PRIVACY_SETTING_KEYS.length).assertEqual(8);
      const seen: string[] = [];
      for (let i = 0; i < PRIVACY_SETTING_KEYS.length; i++) {
        const key: PrivacySettingKey = PRIVACY_SETTING_KEYS[i];
        expect(seen.indexOf(key) < 0).assertTrue();
        seen.push(key);
        // 每行都必须有(setting 对象 / 标题 / 档位文案)，否则页面上会是空行。
        expect(toUserPrivacySetting(key).type.length > 0).assertTrue();
        expect(privacySettingLabel(key).length > 0).assertTrue();
      }
    });

    it('toUserPrivacySetting_mapsEachKeyToItsOwnSetting', 0, () => {
      expect(toUserPrivacySetting('show_last_seen').type).assertEqual('userPrivacySettingShowStatus');
      expect(toUserPrivacySetting('show_phone_number').type).assertEqual('userPrivacySettingShowPhoneNumber');
      expect(toUserPrivacySetting('show_profile_photo').type).assertEqual('userPrivacySettingShowProfilePhoto');
      expect(toUserPrivacySetting('show_bio').type).assertEqual('userPrivacySettingShowBio');
      expect(toUserPrivacySetting('show_birthdate').type).assertEqual('userPrivacySettingShowBirthdate');
      expect(toUserPrivacySetting('allow_calls').type).assertEqual('userPrivacySettingAllowCalls');
      expect(toUserPrivacySetting('allow_chat_invites').type).assertEqual('userPrivacySettingAllowChatInvites');
      expect(toUserPrivacySetting('allow_find_by_phone').type)
        .assertEqual('userPrivacySettingAllowFindingByPhoneNumber');
    });

    it('rowLabel_nullWhenNotLoaded', 0, () => {
      // 没读到就是没读到，不能退成一个猜出来的默认档。
      expect(privacyRowLabel(null)).assertEqual('Unknown');
      expect(privacyRowLabel(new PrivacySettingItem('show_bio', null))).assertEqual('Unknown');
      expect(privacyRowLabel(new PrivacySettingItem('show_bio', parsePrivacyRules([]))))
        .assertEqual('Nobody');
    });

    it('getUserPrivacySettingRules_encodesNestedSetting', 0, () => {
      const request: GetUserPrivacySettingRules = new GetUserPrivacySettingRules();
      request.setting = toUserPrivacySetting('show_phone_number');
      const payload: Record<string, TdJsonRaw> = encodeGetUserPrivacySettingRules(request);
      expect(payload['@type']).assertEqual('getUserPrivacySettingRules');
      const setting: Record<string, TdJsonRaw> = payload['setting'] as Record<string, TdJsonRaw>;
      expect(setting['@type']).assertEqual('userPrivacySettingShowPhoneNumber');
    });

    it('decode_survivesEncodeRoundTripWithExceptions', 0, () => {
      // 过一遍生成的编解码器，证明解析吃的是真实 TDLib JSON 形状而不是手搓对象。
      const container: UserPrivacySettingRules = new UserPrivacySettingRules();
      container.rules = [
        ruleAllowUsers([1001]),
        ruleAllowChatMembers([7001]),
        ruleRestrictUsers([2002]),
        ruleAllowContacts(),
        ruleRestrictAll()
      ];
      const wire: Record<string, TdJsonRaw> = encodeUserPrivacySettingRules(container);
      expect(wire['@type']).assertEqual('userPrivacySettingRules');

      const decoded: UserPrivacySettingRules | null =
        decodeUserPrivacySettingRules(wire as TdJsonRaw);
      expect(decoded !== null).assertTrue();
      if (decoded !== null) {
        const view: PrivacyRulesView = parsePrivacyRules(decoded.rules);
        expect(view.mode).assertEqual('contacts');
        expect(view.minusUserIds[0]).assertEqual(2002);
        expect(view.plusChatIds[0]).assertEqual(7001);
      }
    });

    // ---- PRIVACY-103 附加开关行 ----

    it('premiumRule_insertedBeforeFirstModeRule', 0, () => {
      // premium 是修饰规则：排在 allowContacts 之后就永远轮不到它先命中。
      const next: TdUserPrivacySettingRule[] = privacyRulesWithPremium(
        [ruleAllowUsers([1001]), ruleAllowContacts(), ruleRestrictAll()],
        true
      );
      expect(typesOf(next).join(',')).assertEqual([
        'userPrivacySettingRuleAllowUsers',
        'userPrivacySettingRuleAllowPremiumUsers',
        'userPrivacySettingRuleAllowContacts',
        'userPrivacySettingRuleRestrictAll'
      ].join(','));
    });

    it('premiumRule_movedNotDuplicatedAndKeepsExceptions', 0, () => {
      // 已有 premium 但位置错（排在主档位之后）：再勾一次不能出现第二条，例外名单要原样留着。
      const next: TdUserPrivacySettingRule[] = privacyRulesWithPremium(
        [ruleAllowContacts(), ruleRestrictAll(), ruleAllowPremium(), ruleAllowChatMembers([7001])],
        true
      );
      expect(typesOf(next).join(',')).assertEqual([
        'userPrivacySettingRuleAllowPremiumUsers',
        'userPrivacySettingRuleAllowContacts',
        'userPrivacySettingRuleRestrictAll',
        'userPrivacySettingRuleAllowChatMembers'
      ].join(','));
      expect(chatIdsOf(next[3])[0]).assertEqual(7001);
    });

    it('premiumRule_toggleOffRemovesOnlyThatRule', 0, () => {
      const withPremium: TdUserPrivacySettingRule[] =
        [ruleRestrictUsers([2002]), ruleAllowPremium(), ruleAllowContacts(), ruleRestrictAll()];
      const off: TdUserPrivacySettingRule[] = privacyRulesWithPremium(withPremium, false);
      expect(off.length).assertEqual(3);
      expect(typesOf(off).join(',')).assertEqual([
        'userPrivacySettingRuleRestrictUsers',
        'userPrivacySettingRuleAllowContacts',
        'userPrivacySettingRuleRestrictAll'
      ].join(','));
      // 取消勾选不该动别人：再关一次是恒等。
      expect(privacyRulesEqual(privacyRulesWithPremium(off, false), off)).assertTrue();
    });

    it('premiumRule_appendsWhenNoModeRuleAtAll', 0, () => {
      // 列表里没有主档位规则（Android `globalIndex == -1` 分支）：追加到末尾。
      const next: TdUserPrivacySettingRule[] =
        privacyRulesWithPremium([ruleAllowUsers([1001])], true);
      expect(typesOf(next).join(',')).assertEqual([
        'userPrivacySettingRuleAllowUsers',
        'userPrivacySettingRuleAllowPremiumUsers'
      ].join(','));
    });

    it('premiumRule_emptyList', 0, () => {
      // 「没有人」档在 TDLib 里就是空列表，勾 Premium 只能得到一条 premium 规则。
      expect(typesOf(privacyRulesWithPremium([], true)).join(','))
        .assertEqual('userPrivacySettingRuleAllowPremiumUsers');
      expect(privacyRulesWithPremium([], false).length).assertEqual(0);
    });

    it('premiumRow_onlyOnChatInvites', 0, () => {
      // Android 只在 AllowChatInvites 上给这一行；其余项点了也产不出 premium 规则。
      expect(privacyNeedsPremiumRow('allow_chat_invites')).assertTrue();
      for (let i = 0; i < PRIVACY_SETTING_KEYS.length; i++) {
        const key: PrivacySettingKey = PRIVACY_SETTING_KEYS[i];
        expect(privacyNeedsPremiumRow(key)).assertEqual(key === 'allow_chat_invites');
      }
    });

    it('readDateRow_onlyOnLastSeen', 0, () => {
      expect(privacyNeedsReadDateRow('show_last_seen')).assertTrue();
      for (let i = 0; i < PRIVACY_SETTING_KEYS.length; i++) {
        const key: PrivacySettingKey = PRIVACY_SETTING_KEYS[i];
        expect(privacyNeedsReadDateRow(key)).assertEqual(key === 'show_last_seen');
      }
    });

    it('readDateRow_hiddenUnderEverybodyWithoutExceptions', 0, () => {
      // 「所有人」档下没人看不到你的上线时间，这条开关无意义；例外名单非空时仍要出。
      expect(privacyNeedsHideReadTime(parsePrivacyRules([ruleAllowAll()]))).assertFalse();
      expect(privacyNeedsHideReadTime(
        parsePrivacyRules([ruleRestrictUsers([2002]), ruleAllowAll()])
      )).assertTrue();
      expect(privacyNeedsHideReadTime(parsePrivacyRules([ruleAllowContacts()]))).assertTrue();
      expect(privacyNeedsHideReadTime(parsePrivacyRules([]))).assertTrue();
    });

    it('modeChange_ownsPremiumFlagPerKey', 0, () => {
      // 改档时 premium 归谁：Android 只有 AllowChatInvites + 目标档「我的联系人」才置真，
      // 其余一律为假 —— 所以在别的项上改档等于把它已有的 premium 规则摘掉。
      expect(privacyPremiumForMode('allow_chat_invites', 'contacts')).assertTrue();
      expect(privacyPremiumForMode('allow_chat_invites', 'everybody')).assertFalse();
      expect(privacyPremiumForMode('allow_chat_invites', 'nobody')).assertFalse();
      expect(privacyPremiumForMode('show_last_seen', 'contacts')).assertFalse();
      expect(privacyPremiumForMode('show_bio', 'contacts')).assertFalse();
    });

    it('detailState_showReadDateNotDirty', 0, () => {
      // 它不在规则列表里，所以「有没有未保存的编辑」不能把它算进去 —— 否则离开页面会
      // 多发一次 setUserPrivacySettingRules，而这一项根本没改。
      const loaded: PrivacyDetailState = PrivacyDetailState.forLoaded(
        'show_last_seen',
        [ruleAllowContacts()],
        [],
        [],
        true
      );
      expect(loaded.showReadDate).assertTrue();
      expect(loaded.isDirty()).assertFalse();
      const flipped: PrivacyDetailState = loaded.copyWith({ showReadDate: false });
      expect(flipped.showReadDate).assertFalse();
      expect(flipped.isDirty()).assertFalse();
      expect(PrivacyDetailState.forLoading('show_last_seen').showReadDate === null).assertTrue();
    });
  });
}
