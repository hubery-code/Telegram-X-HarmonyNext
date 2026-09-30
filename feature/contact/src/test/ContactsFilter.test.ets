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

function itemWithUsernames(displayName: string, usernames: string[]): ContactsItem {
  return new ContactsItem(1, displayName, usernames.length > 0 ? usernames[0] : '', null, '', 0, '', '', usernames);
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

    it('contactMatchesQuery_matchesMultipleActiveUsernamesAndAtPrefix', 0, () => {
      const multi = itemWithUsernames('Alice', ['alice_primary', 'alice_secondary']);
      // 1. 带 @ 前缀
      expect(contactMatchesQuery(multi, '@alice')).assertTrue();
      expect(contactMatchesQuery(multi, '@alice_sec')).assertTrue();
      expect(contactMatchesQuery(multi, '@none')).assertFalse();
      // 2. 不带 @ 前缀匹配次级用户名
      expect(contactMatchesQuery(multi, 'alice_sec')).assertTrue();
      // 3. 次级用户名中间片段不命中
      expect(contactMatchesQuery(multi, 'secondary')).assertFalse();
    });

    it('contactMatchesQuery_emptyQueryMatchesEverything', 0, () => {
      expect(contactMatchesQuery(item('Alice'), '   ')).assertTrue();
      expect(contactMatchesQuery(item(''), '')).assertTrue();
    });

    it('formatContactPhone_formatsE164CountryCodes', 0, () => {
      // +86 (中国大陆)
      expect(formatContactPhone('8613812345678')).assertEqual('+86 138 1234 5678');
      // +1 (美国/加拿大)
      expect(formatContactPhone('14155552671')).assertEqual('+1 (415) 555-2671');
      // +7 (俄罗斯)
      expect(formatContactPhone('79991234567')).assertEqual('+7 (999) 123-45-67');
      // +44 (英国)
      expect(formatContactPhone('447741417158')).assertEqual('+44 7741 417158');
      expect(formatContactPhone('+44 7741 417158')).assertEqual('+44 7741 417158');
      // +852 (中国香港)
      expect(formatContactPhone('85298765432')).assertEqual('+852 9876 5432');
      // +886 (中国台湾)
      expect(formatContactPhone('886912345678')).assertEqual('+886 912 345 678');
      // +81 (日本)
      expect(formatContactPhone('819012345678')).assertEqual('+81 90 1234 5678');
      // +82 (韩国)
      expect(formatContactPhone('821012345678')).assertEqual('+82 10 1234 5678');
      // +49 (德国 12位)
      expect(formatContactPhone('491511234567')).assertEqual('+49 151 123 4567');
      // +33 (法国)
      expect(formatContactPhone('33612345678')).assertEqual('+33 6 12 34 56 78');
      // +65 (新加坡)
      expect(formatContactPhone('6591234567')).assertEqual('+65 9123 4567');
    });

    it('formatContactPhone_fallbackKeepsDigitsAndForcesPlus', 0, () => {
      expect(formatContactPhone('(447) 741-4171')).assertEqual('+4477414171');
      expect(formatContactPhone('99912345')).assertEqual('+99912345');
    });

    it('formatContactPhone_returnsEmptyWhenNoDigits', 0, () => {
      expect(formatContactPhone('')).assertEqual('');
      expect(formatContactPhone(null)).assertEqual('');
      expect(formatContactPhone('n/a')).assertEqual('');
    });
  });
}
