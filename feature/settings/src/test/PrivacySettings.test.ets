/**
 * feature/settings — 隐私模型层单测（SELF-102 键序 + PRIVACY-101 规则列表语义）。
 *
 * 覆盖的是「读得准、改不坏」两件事：
 * 1. 解析：单条简单规则 → 对应档位；带例外名单仍是主档位 + 名单，不再被归成不可写的 custom；
 *    空列表 = nobody（设备实测：写 restrictAll 后 TDLib 读回 rules=[]）；
 * 2. 终结性：allowAll / restrictAll 之后的规则不参与判定；
 * 3. 改档：例外名单原样保留（这是本包最关键的一条语义，旧版会抹掉）；bots 规则不动；
 * 4. 例外名单：全量替换、插到列表最前、另一侧同名 id 被摘掉；
 * 5. dirty 判定：privacyRulesEqual 按序列化结果比，不按引用；
 * 6. 行数据：例外名单里解析不到名字的人保留为占位行，群成员只计人数；
 * 7. 8 个设置项的键序与 setting 对象映射（防止写回时张冠李戴）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
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
  privacyRowLabel,
  privacySettingLabel,
  toUserPrivacySetting
} from '../main/ets/model/PrivacySettings';
import {
  PrivacyMode,
  PrivacyRulesView,
  parsePrivacyRules,
  privacyAlwaysAllowCount,
  privacyModeLabel,
  privacyNeedAlwaysAllow,
  privacyNeedNeverAllow,
  privacyNeverAllowCount,
  privacyRulesForMode,
  privacyRulesWithAllowUsers,
  privacyRulesWithRestrictUsers
} from '../main/ets/model/PrivacyRules';
import {
  PrivacyContactRow,
  PrivacyDetailState,
  PrivacyExceptionRow,
  PrivacyExceptionsView,
  privacyContactsWithPicked,
  privacyExceptionRows,
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

function contact(userId: number, title: string): PrivacyContactRow {
  return new PrivacyContactRow(userId, title, false);
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
      expect(privacyAlwaysAllowCount(view)).assertEqual(3);
      expect(privacyNeverAllowCount(view)).assertEqual(2);
      expect(view.plusChatIds.length).assertEqual(2);
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
      const next: TdUserPrivacySettingRule[] = privacyRulesWithAllowUsers(
        [ruleAllowUsers([999]), ruleAllowContacts(), ruleRestrictAll()], [1001, 1002]
      );
      expect(next[0].type).assertEqual('userPrivacySettingRuleAllowUsers');
      expect(idsOf(next[0]).join(',')).assertEqual('1001,1002');
      expect(next.length).assertEqual(3);
    });

    it('rulesWithAllowUsers_stripsSamePeopleFromOtherSide', 0, () => {
      // 同一个人不能既总是允许又从不允许。
      const next: TdUserPrivacySettingRule[] = privacyRulesWithAllowUsers(
        [ruleRestrictUsers([1001, 2002]), ruleAllowContacts(), ruleRestrictAll()], [1001]
      );
      expect(next[0].type).assertEqual('userPrivacySettingRuleAllowUsers');
      expect(next[1].type).assertEqual('userPrivacySettingRuleRestrictUsers');
      expect(idsOf(next[1]).join(',')).assertEqual('2002');
      expect(next.length).assertEqual(4);
    });

    it('rulesWithAllowUsers_dropsEmptiedOppositeRule', 0, () => {
      const next: TdUserPrivacySettingRule[] = privacyRulesWithAllowUsers(
        [ruleRestrictUsers([1001]), ruleAllowContacts(), ruleRestrictAll()], [1001]
      );
      expect(next.length).assertEqual(3);
      expect(next[0].type).assertEqual('userPrivacySettingRuleAllowUsers');
      expect(next[1].type).assertEqual('userPrivacySettingRuleAllowContacts');
    });

    it('rulesWithAllowUsers_emptyPickMeansNoException', 0, () => {
      const next: TdUserPrivacySettingRule[] = privacyRulesWithAllowUsers(
        [ruleAllowUsers([1001]), ruleAllowContacts(), ruleRestrictAll()], []
      );
      expect(next.length).assertEqual(2);
      expect(next[0].type).assertEqual('userPrivacySettingRuleAllowContacts');
    });

    it('exceptionRewrite_doesNotMutateSavedSnapshot', 0, () => {
      // 旧列表还挂在 savedRules 上；就地改 user_ids 会把「有没有未保存的编辑」抹平。
      const original: TdUserPrivacySettingRule[] = [
        ruleRestrictUsers([1001, 2002]), ruleAllowContacts(), ruleRestrictAll()
      ];
      const snapshot: TdUserPrivacySettingRule[] = original.slice();
      privacyRulesWithAllowUsers(original, [1001]);
      expect(idsOf(original[0]).join(',')).assertEqual('1001,2002');
      expect(privacyRulesEqual(original, snapshot)).assertTrue();
    });

    it('rulesWithRestrictUsers_isMirrorImage', 0, () => {
      const next: TdUserPrivacySettingRule[] = privacyRulesWithRestrictUsers(
        [ruleAllowUsers([1001, 2002]), ruleAllowContacts(), ruleRestrictAll()], [1001]
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

    it('rulesEqual_comparesByContentNotReference', 0, () => {
      expect(privacyRulesEqual([], [])).assertTrue();
      expect(privacyRulesEqual([ruleAllowUsers([1, 2])], [ruleAllowUsers([1, 2])])).assertTrue();
      expect(privacyRulesEqual([ruleAllowUsers([1, 2])], [ruleAllowUsers([2, 1])])).assertFalse();
      expect(privacyRulesEqual([ruleAllowAll()], [ruleRestrictAll()])).assertFalse();
      expect(privacyRulesEqual([ruleAllowAll()], [])).assertFalse();
    });

    it('detailState_isDirtyOnlyAfterLocalEdits', 0, () => {
      const loaded: PrivacyDetailState = PrivacyDetailState.forLoaded(
        'show_bio', [ruleAllowContacts(), ruleRestrictAll()], []
      );
      expect(loaded.isDirty()).assertFalse();
      const edited: PrivacyDetailState = loaded.copyWith({
        rules: privacyRulesWithAllowUsers(loaded.rules, [1001])
      });
      expect(edited.isDirty()).assertTrue();
      // 原快照不能被改写：UiState 是不可变快照。
      expect(loaded.isDirty()).assertFalse();
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
        [contact(1001, 'Ada'), contact(2002, 'Lin')]
      );
      expect(view.showAlwaysRow).assertTrue();
      expect(view.showNeverRow).assertTrue();
      expect(view.alwaysRows.length).assertEqual(1);
      expect(view.alwaysRows[0].title).assertEqual('Ada');
      expect(view.neverRows[0].title).assertEqual('Lin');
    });

    it('exceptionsView_everybodyHasNoAlwaysRow', 0, () => {
      const view: PrivacyExceptionsView = privacyExceptionsView(
        [ruleRestrictUsers([2002]), ruleAllowAll()],
        [contact(2002, 'Lin')]
      );
      expect(view.showAlwaysRow).assertFalse();
      expect(view.showNeverRow).assertTrue();
    });

    it('exceptionRows_keepPlaceholderForUnresolvedIds', 0, () => {
      // 名单里确实有这个人，静默删行等于谎报服务端状态。
      const rows: PrivacyExceptionRow[] = privacyExceptionRows([1001, 4004], [contact(1001, 'Ada')]);
      expect(rows.length).assertEqual(2);
      expect(rows[0].title).assertEqual('Ada');
      expect(rows[1].title).assertEqual('Unknown User');
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

    it('contactRow_withSelected_isIdentityWhenUnchanged', 0, () => {
      const row: PrivacyContactRow = new PrivacyContactRow(1001, 'Ada', true);
      expect(row.withSelected(true) === row).assertTrue();
      const next: PrivacyContactRow = row.withSelected(false);
      expect(next !== row).assertTrue();
      expect(next.selected).assertFalse();
      expect(row.selected).assertTrue();
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
      container.rules = contactsExceptUsers();
      const wire: Record<string, TdJsonRaw> = encodeUserPrivacySettingRules(container);
      expect(wire['@type']).assertEqual('userPrivacySettingRules');

      const decoded: UserPrivacySettingRules | null =
        decodeUserPrivacySettingRules(wire as TdJsonRaw);
      expect(decoded !== null).assertTrue();
      if (decoded !== null) {
        const view: PrivacyRulesView = parsePrivacyRules(decoded.rules);
        expect(view.mode).assertEqual('contacts');
        expect(view.minusUserIds[0]).assertEqual(2002);
      }
    });
  });
}
