/**
 * feature/settings — 隐私设置映射层单测（SELF-102）。
 *
 * 覆盖 TDLib `userPrivacySettingRules` ↔ 页面档位的双向映射：
 * 1. 单条简单规则 → 对应档位；
 * 2. 带例外名单（多条规则）→ custom，绝不冒充成其中第一条的档位；
 * 3. 空规则 → nobody（TDLib 不把「没有人」落成规则）；
 * 4. rulesForChoice 只会产生单条规则，且与 choiceFromRules 往返一致；
 * 5. 点击循环档位与可写判定；
 * 6. 8 个设置项的键序与 setting 对象映射（防止写回时张冠李戴）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  TdJsonRaw,
  TdUserPrivacySettingRule,
  UserPrivacySettingRules,
  UserPrivacySettingRuleAllowAll,
  UserPrivacySettingRuleAllowContacts,
  UserPrivacySettingRuleAllowPremiumUsers,
  UserPrivacySettingRuleAllowUsers,
  UserPrivacySettingRuleRestrictAll,
  UserPrivacySettingRuleRestrictUsers,
  decodeUserPrivacySettingRules,
  encodeUserPrivacySettingRules,
  encodeGetUserPrivacySettingRules,
  GetUserPrivacySettingRules
} from '@tgx/core-td-api-generated';
import {
  choiceFromRules,
  isPrivacyChoiceWritable,
  nextPrivacyChoice,
  PrivacyChoice,
  PrivacySettingItem,
  PrivacySettingKey,
  PRIVACY_SETTING_KEYS,
  privacyChoiceLabel,
  privacySettingLabel,
  rulesForChoice,
  toUserPrivacySetting
} from '../main/ets/model/PrivacySettings';

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

function ruleAllowUsers(): TdUserPrivacySettingRule {
  const rule: UserPrivacySettingRuleAllowUsers = new UserPrivacySettingRuleAllowUsers();
  rule.user_ids = [1001];
  return rule;
}

function ruleRestrictUsers(): TdUserPrivacySettingRule {
  const rule: UserPrivacySettingRuleRestrictUsers = new UserPrivacySettingRuleRestrictUsers();
  rule.user_ids = [2002];
  return rule;
}

export default function privacySettingsTest(): void {
  describe('PrivacySettingsTest', () => {
    it('choiceFromRules_mapsSingleSimpleRules', 0, () => {
      expect(choiceFromRules([ruleAllowAll()])).assertEqual('everybody');
      expect(choiceFromRules([ruleAllowPremium()])).assertEqual('premium');
      expect(choiceFromRules([ruleAllowContacts()])).assertEqual('contacts');
      expect(choiceFromRules([ruleRestrictAll()])).assertEqual('nobody');
    });

    it('choiceFromRules_treatsExceptionListsAsCustom', 0, () => {
      // 「联系人，但排除某人」不能显示成「我的联系人」——那会让人以为改动没生效。
      const exceptions: TdUserPrivacySettingRule[] = [ruleAllowContacts(), ruleRestrictUsers()];
      expect(choiceFromRules(exceptions)).assertEqual('custom');
      expect(choiceFromRules([ruleAllowUsers()])).assertEqual('custom');
    });

    it('choiceFromRules_emptyListMeansNobody', 0, () => {
      // 设备实测：show_birthdate 写入 restrictAll 后 TDLib 读回 rules=[]，
      // 即「没人能看到」不需要落库；空列表不能显示成用户看不懂的 Unknown。
      expect(choiceFromRules([])).assertEqual('nobody');
    });

    it('rulesForChoice_emitsExactlyOneSimpleRule', 0, () => {
      expect(rulesForChoice('everybody').length).assertEqual(1);
      expect(rulesForChoice('everybody')[0].type).assertEqual('userPrivacySettingRuleAllowAll');
      expect(rulesForChoice('premium')[0].type).assertEqual('userPrivacySettingRuleAllowPremiumUsers');
      expect(rulesForChoice('contacts')[0].type).assertEqual('userPrivacySettingRuleAllowContacts');
      expect(rulesForChoice('nobody')[0].type).assertEqual('userPrivacySettingRuleRestrictAll');
    });

    it('rulesForChoice_roundTripsThroughChoiceFromRules', 0, () => {
      const choices: PrivacyChoice[] = ['everybody', 'premium', 'contacts', 'nobody'];
      for (let i = 0; i < choices.length; i++) {
        expect(choiceFromRules(rulesForChoice(choices[i]))).assertEqual(choices[i]);
      }
    });

    it('choiceFromRules_survivesEncodeDecodeRoundTrip', 0, () => {
      // 过一遍生成的编解码器，证明页面档位来自真实 TDLib JSON 形状而不是手搓对象。
      const container: UserPrivacySettingRules = new UserPrivacySettingRules();
      const rules: TdUserPrivacySettingRule[] = [ruleAllowContacts(), ruleRestrictUsers()];
      container.rules = rules;
      const wire: Record<string, TdJsonRaw> = encodeUserPrivacySettingRules(container);
      expect(wire['@type']).assertEqual('userPrivacySettingRules');

      const decoded: UserPrivacySettingRules | null = decodeUserPrivacySettingRules(wire as TdJsonRaw);
      expect(decoded !== null).assertTrue();
      if (decoded !== null) {
        expect(choiceFromRules(decoded.rules)).assertEqual('custom');
      }
    });

    it('nextPrivacyChoice_cyclesThreeMainLevels', 0, () => {
      expect(nextPrivacyChoice('everybody')).assertEqual('contacts');
      expect(nextPrivacyChoice('contacts')).assertEqual('nobody');
      expect(nextPrivacyChoice('nobody')).assertEqual('everybody');
      expect(nextPrivacyChoice('premium')).assertEqual('contacts');
    });

    it('nextPrivacyChoice_resetsCustomAndUnknownToContacts', 0, () => {
      // 例外名单编辑器未拆包：自定义态点一下必须回到可写的确定档位，
      // 但循环起点选 contacts 而不是 nobody，避免一键把可见面缩到最小。
      expect(nextPrivacyChoice('custom')).assertEqual('contacts');
      expect(nextPrivacyChoice('unknown')).assertEqual('contacts');
    });

    it('isPrivacyChoiceWritable_blocksCustomAndUnknown', 0, () => {
      expect(isPrivacyChoiceWritable('everybody')).assertTrue();
      expect(isPrivacyChoiceWritable('premium')).assertTrue();
      expect(isPrivacyChoiceWritable('contacts')).assertTrue();
      expect(isPrivacyChoiceWritable('nobody')).assertTrue();
      expect(isPrivacyChoiceWritable('custom')).assertFalse();
      expect(isPrivacyChoiceWritable('unknown')).assertFalse();
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

    it('getUserPrivacySettingRules_encodesNestedSetting', 0, () => {
      const request: GetUserPrivacySettingRules = new GetUserPrivacySettingRules();
      request.setting = toUserPrivacySetting('show_phone_number');
      const payload: Record<string, TdJsonRaw> = encodeGetUserPrivacySettingRules(request);
      expect(payload['@type']).assertEqual('getUserPrivacySettingRules');
      const setting: Record<string, TdJsonRaw> = payload['setting'] as Record<string, TdJsonRaw>;
      expect(setting['@type']).assertEqual('userPrivacySettingShowPhoneNumber');
    });

    it('decodeUserPrivacySettingRules_readsRulesArray', 0, () => {
      const container: UserPrivacySettingRules = new UserPrivacySettingRules();
      container.rules = [ruleRestrictAll()];
      const decoded: UserPrivacySettingRules | null =
        decodeUserPrivacySettingRules(encodeUserPrivacySettingRules(container) as TdJsonRaw);
      expect(decoded !== null).assertTrue();
      if (decoded !== null) {
        expect(choiceFromRules(decoded.rules)).assertEqual('nobody');
      }
    });

    it('privacySettingItem_withChoiceKeepsIdentityWhenUnchanged', 0, () => {
      const item: PrivacySettingItem = new PrivacySettingItem('allow_calls', 'contacts');
      expect(item.withChoice('contacts') === item).assertTrue();
      const next: PrivacySettingItem = item.withChoice('nobody');
      expect(next !== item).assertTrue();
      expect(next.key).assertEqual('allow_calls');
      expect(next.choice).assertEqual('nobody');
      // 原对象不能被改写：UiState 是不可变快照。
      expect(item.choice).assertEqual('contacts');
    });

    it('privacyChoiceLabel_coversEveryChoice', 0, () => {
      const choices: PrivacyChoice[] = ['everybody', 'premium', 'contacts', 'nobody', 'custom', 'unknown'];
      const labels: string[] = [];
      for (let i = 0; i < choices.length; i++) {
        const label: string = privacyChoiceLabel(choices[i]);
        expect(label.length > 0).assertTrue();
        expect(labels.indexOf(label) < 0).assertTrue();
        labels.push(label);
      }
    });
  });
}
