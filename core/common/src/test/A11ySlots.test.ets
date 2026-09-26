import { describe, it, expect } from '@ohos/hypium';
import { A11Y_SLOTS } from '../main/ets/A11y';
import { Lang, SupportedLanguage } from '../main/ets/Lang';

const LANGUAGES: SupportedLanguage[] = ['en', 'zh'];

/** 带 `{0}` 的槽位：断言实参真的被填进去，而不是把占位符念给用户。 */
const WITH_ARG: string[] = ['A11yOpenProfile', 'A11yBoardCell', 'A11yBoardPack'];

export default function a11ySlotsTest(): void {
  describe('A11ySlotsTest', () => {
    it('everySlot_resolvesInBothLanguages', 0, () => {
      const lang = Lang.getInstance();
      const broken: string[] = [];
      for (let i = 0; i < A11Y_SLOTS.length; i++) {
        const key = A11Y_SLOTS[i];
        for (let j = 0; j < LANGUAGES.length; j++) {
          const text = lang.formatByKey(key, LANGUAGES[j], []);
          if (text.length === 0) {
            broken.push(`${key}:${LANGUAGES[j]}=<empty>`);
            continue;
          }
          // Lang 查不到时原样回吐 key，所以「等于 key」就是「词典里没有这一条」。
          // EN 词典的 key 本身就是英文原句（复用 `'Cancel'` 这类通用文案时两者相同），
          // 所以回吐判据只对 `A11y*` 前缀的槽位成立；ZH 侧任何槽位都必须出中文。
          if (text === key && (LANGUAGES[j] === 'zh' || key.startsWith('A11y'))) {
            broken.push(`${key}:${LANGUAGES[j]}`);
          }
        }
      }
      expect(broken.join(', ')).assertEqual('');
    });

    it('parameterizedSlots_fillTheirArgument', 0, () => {
      const lang = Lang.getInstance();
      const broken: string[] = [];
      for (let i = 0; i < WITH_ARG.length; i++) {
        const key = WITH_ARG[i];
        for (let j = 0; j < LANGUAGES.length; j++) {
          const text = lang.formatByKey(key, LANGUAGES[j], ['Alice']);
          if (text.indexOf('Alice') < 0 || text.indexOf('{0}') >= 0) {
            broken.push(`${key}:${LANGUAGES[j]}=${text}`);
          }
        }
      }
      expect(broken.join(', ')).assertEqual('');
    });
  });
}
