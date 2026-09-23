/**
 * feature/contact — 搜索匹配与号码格式化纯函数单测（CONTACT-102）。
 *
 * 覆盖：`anyWordStartsWith` 与 Android `Strings.anyWordStartsWith` 的逐条等价
 * （整体前缀 / 词首 / 忽略大小写 / 换行分隔 / 中间片段不命中）、
 * `contactMatchesQuery` 的用户名前缀与空查询、`formatContactPhone` 的剥非数字与补 `+`。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ContactsItem } from '../main/ets/contract/ContactsUiState';
import { anyWordStartsWith, contactMatchesQuery } from '../main/ets/model/ContactsFilter';
import { formatContactPhone } from '../main/ets/model/ContactPhone';

function item(displayName: string, username: string = ''): ContactsItem {
  return new ContactsItem(1, displayName, username, null, '', 0, '');
}

export default function contactsFilterTest(): void {
  describe('ContactsFilterTest', () => {

    it('anyWordStartsWith_wholeStringPrefix', 0, () => {
      expect(anyWordStartsWith('be hu', 'be h')).assertTrue();
      expect(anyWordStartsWith('be hu', 'be hu')).assertTrue();
      expect(anyWordStartsWith('be hu', 'be hu x')).assertFalse();
    });

    it('anyWordStartsWith_secondWordPrefix', 0, () => {
      expect(anyWordStartsWith('Alice Anderson', 'and')).assertTrue();
      expect(anyWordStartsWith('Alice Anderson', 'Anderson')).assertTrue();
      // 词首比较带整个前缀：'A a' 不是任何词的开头
      expect(anyWordStartsWith('Alice Anderson', 'A a')).assertFalse();
    });

    /** 这是本次改动的动机：旧的子串匹配会把中间片段也算命中。 */
    it('anyWordStartsWith_doesNotMatchMidWordFragment', 0, () => {
      expect(anyWordStartsWith('Zhu Feng', 'hu')).assertFalse();
      expect(anyWordStartsWith('Zhu Feng', 'Fen')).assertTrue();
      expect(anyWordStartsWith('alpha_user', 'user')).assertFalse();
    });

    it('anyWordStartsWith_isCaseInsensitive', 0, () => {
      expect(anyWordStartsWith('Alice Anderson', 'ALICE')).assertTrue();
      expect(anyWordStartsWith('Alice Anderson', 'andER')).assertTrue();
      expect(anyWordStartsWith('ALICE', 'alice')).assertTrue();
    });

    it('anyWordStartsWith_splitsOnNewlineToo', 0, () => {
      expect(anyWordStartsWith('first\nsecond', 'sec')).assertTrue();
      expect(anyWordStartsWith('first\nsecond', 'irst')).assertFalse();
    });

    it('anyWordStartsWith_emptyPrefixMatchesAlways', 0, () => {
      // Android `regionMatches` 长度为 0 直接命中；空查询由上层短路，不进这里
      expect(anyWordStartsWith('anything', '')).assertTrue();
    });

    it('contactMatchesQuery_trimsQueryAndMatchesUsernamePrefix', 0, () => {
      expect(contactMatchesQuery(item('Alice', 'alice_x'), '  ali  ')).assertTrue();
      expect(contactMatchesQuery(item('Alice', 'alice_x'), 'alice_x')).assertTrue();
      expect(contactMatchesQuery(item('Alice', 'alice_x'), 'x')).assertFalse();
    });

    it('contactMatchesQuery_emptyQueryMatchesEverything', 0, () => {
      expect(contactMatchesQuery(item('Alice'), '   ')).assertTrue();
      expect(contactMatchesQuery(item(''), '')).assertTrue();
    });

    it('formatContactPhone_keepsDigitsAndForcesPlus', 0, () => {
      // 实测本账号 TDLib 回包不带 '+'，补号是有意义的一步
      expect(formatContactPhone('447741417158')).assertEqual('+447741417158');
      expect(formatContactPhone('+44 7741 417158')).assertEqual('+447741417158');
      expect(formatContactPhone('(447) 741-4171')).assertEqual('+4477414171');
    });

    it('formatContactPhone_returnsEmptyWhenNoDigits', 0, () => {
      expect(formatContactPhone('')).assertEqual('');
      expect(formatContactPhone(null)).assertEqual('');
      expect(formatContactPhone('n/a')).assertEqual('');
    });
  });
}
