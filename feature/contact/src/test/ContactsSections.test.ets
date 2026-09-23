/**
 * feature/contact — ContactsSections 纯函数单元测试（CONTACT-101）。
 *
 * 覆盖：分组字母（拉丁 / 非拉丁 / 数字 / 空 / 代理对 / 符号开头）、排序键剥标点、
 * 码元序比较、相邻同字母归段与 startIndex、滚动位移、当前段判定、索引条可见性。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ContactsItem, ContactsSection } from '../main/ets/contract/ContactsUiState';
import {
  cleanContactKey,
  contactSortKey,
  compareContacts,
  sectionLetterOf,
  buildContactsSections,
  sectionScrollOffsets,
  activeSectionIndex,
  indexBarVisible
} from '../main/ets/model/ContactsSections';

function item(userId: number, displayName: string): ContactsItem {
  return new ContactsItem(userId, displayName, '', null, '', 0, '');
}

function sortedItems(names: string[]): ContactsItem[] {
  const items: ContactsItem[] = [];
  for (let i: number = 0; i < names.length; i++) {
    items.push(item(i + 1, names[i]));
  }
  items.sort(compareContacts);
  return items;
}

export default function contactsSectionsTest(): void {
  describe('ContactsSectionsTest', () => {

    it('sectionLetter_uppercasesLatinLead', 0, () => {
      expect(sectionLetterOf('be hu')).assertEqual('B');
      expect(sectionLetterOf('Alice')).assertEqual('A');
    });

    // 旧实现只认 A-Z，非拉丁名字全部塌进 '#'：越南语/西里尔/CJK 联系人页会整页只有一个
    // '#' 段。注意 'Dũng' 的首字母是普通 ASCII 'D'（变音符在 u 上），真正带伏标的
    // 'Đức' 才自成 'Đ' 段。
    it('sectionLetter_keepsNonLatinScriptsAsTheirOwnSection', 0, () => {
      expect(sectionLetterOf('Dũng')).assertEqual('D');
      expect(sectionLetterOf('Đức')).assertEqual('Đ');
      expect(sectionLetterOf('Анна')).assertEqual('А');
      expect(sectionLetterOf('伟 陈')).assertEqual('伟');
    });

    it('sectionLetter_fallsBackToHash', 0, () => {
      expect(sectionLetterOf('')).assertEqual('#');
      expect(sectionLetterOf('   ')).assertEqual('#');
      expect(sectionLetterOf('17 Slots')).assertEqual('#');
      // 落单代理对（半个 emoji）不能当字母渲染
      expect(sectionLetterOf(String.fromCharCode(0xD800))).assertEqual('#');
      expect(sectionLetterOf('\ud83d\ude00 smile')).assertEqual('😀');
    });

    it('cleanContactKey_stripsAsciiPunctuationOnly', 0, () => {
      expect(cleanContactKey('a b-c.d/e')).assertEqual('a bcde');
      expect(cleanContactKey('-Anna')).assertEqual('Anna');
      expect(cleanContactKey('123')).assertEqual('123');
      expect(cleanContactKey('Đức!')).assertEqual('Đức');
    });

    it('contactSortKey_ignoresLeadingPunctuationAndCase', 0, () => {
      expect(contactSortKey(item(1, '  -Anna '))).assertEqual('anna');
    });

    it('compareContacts_ordersByCleanedKeyInCodeUnitOrder', 0, () => {
      const items: ContactsItem[] = sortedItems(['Zoe', '-Anna', 'Bob', 'Ádám']);
      const names: string[] = [];
      for (let i: number = 0; i < items.length; i++) {
        names.push(items[i].displayName);
      }
      // '-Anna' 的键被剥成 'anna'，不再被符号挤到列表尾部；变音符字母按码元序落在
      // 基本拉丁之后（与 Android 一致：'đ' 排在 'z' 后面）。
      expect(names[0]).assertEqual('-Anna');
      expect(names[1]).assertEqual('Bob');
      expect(names[2]).assertEqual('Zoe');
      expect(names[3]).assertEqual('Ádám');
    });

    // Android 的键不转小写，'bob' 会排到 'Zoe' 之后、字母 B 被劈成两段；本端加了小写化。
    it('compareContacts_lowercaseNamesStayInTheirLetterSection', 0, () => {
      const items: ContactsItem[] = sortedItems(['Zoe', 'bob', 'alice']);
      const sections: ContactsSection[] = buildContactsSections(items);
      expect(sections.length).assertEqual(3);
      expect(sections[0].letter).assertEqual('A');
      expect(sections[1].letter).assertEqual('B');
      expect(sections[2].letter).assertEqual('Z');
    });

    it('buildContactsSections_groupsAdjacentRunsAndRecordsStartIndex', 0, () => {
      const items: ContactsItem[] = sortedItems(['Alice', 'Anderson', 'be hu', 'Đức']);
      const sections = buildContactsSections(items);
      expect(sections.length).assertEqual(3);
      expect(sections[0].letter).assertEqual('A');
      expect(sections[0].items.length).assertEqual(2);
      expect(sections[1].letter).assertEqual('B');
      expect(sections[2].letter).assertEqual('Đ');
      expect(sections[2].startIndex).assertEqual(3);
    });

    it('buildContactsSections_repeatedLetterStaysUniquelyKeyed', 0, () => {
      // 未排序输入下同一字母可能出现两段：key 必须靠 startIndex 区分，否则 ForEach 撞 key。
      const items: ContactsItem[] = [item(1, 'Alice'), item(2, 'Bob'), item(3, 'Anna')];
      const sections = buildContactsSections(items);
      expect(sections.length).assertEqual(3);
      expect(sections[0].letter).assertEqual(sections[2].letter);
      expect(sections[0].startIndex !== sections[2].startIndex).assertTrue();
    });

    it('buildContactsSections_emptyList', 0, () => {
      expect(buildContactsSections([]).length).assertEqual(0);
    });

    // 数字取自模拟器实测（3.5 密度）：单条组间距 94vp、两条组 158vp（= 28 标题 + 64×n + 2 分隔线）。
    it('sectionScroll_offsetsAccumulateHeaderRowsAndGroupGap', 0, () => {
      const items: ContactsItem[] = sortedItems(['Alice', 'Anna2', 'be hu', 'Carol']);
      const sections: ContactsSection[] = buildContactsSections(items);
      expect(sections.length).assertEqual(3);
      const offsets: number[] = sectionScrollOffsets(sections, 28, 64, 2);
      expect(offsets[0]).assertEqual(0);
      expect(offsets[1]).assertEqual(158);
      expect(offsets[2]).assertEqual(158 + 94);
    });

    it('activeSectionIndex_tracksScrollOffset', 0, () => {
      const offsets: number[] = [0, 156, 248];
      expect(activeSectionIndex(offsets, 0)).assertEqual(0);
      expect(activeSectionIndex(offsets, 100)).assertEqual(0);
      expect(activeSectionIndex(offsets, 156)).assertEqual(1);
      expect(activeSectionIndex(offsets, 200)).assertEqual(1);
      expect(activeSectionIndex(offsets, 5000)).assertEqual(2);
    });

    it('indexBarVisible_needsMoreThanOneSection', 0, () => {
      expect(indexBarVisible(buildContactsSections(sortedItems(['only one'])))).assertFalse();
      expect(indexBarVisible(buildContactsSections(sortedItems(['Alice', 'be hu'])))).assertTrue();
    });
  });
}
