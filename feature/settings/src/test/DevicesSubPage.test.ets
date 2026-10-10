/**
 * feature/settings — 设备管理与活跃会话时间格式化单测（DEVICES-101 / FEAT-P2-008）。
 *
 * 覆盖：
 * 1. formatSessionDate 在线状态（0 或负数时间戳）；
 * 2. 刚刚（< 60秒）中英双语；
 * 3. 分钟前（< 1小时）中英双语；
 * 4. 同年及跨年绝对时间格式化（形态走 `DateFormat`，不是页面自己拼）；
 * 5. ActiveSessionItem 模型对象装配完整性；
 * 6. 设备行副标题的档位键（单数/复数/零会话，中英两档实际取词）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Lang, SupportedLanguage } from '@tgx/core-common';
import { formatSessionDate } from '../main/ets/pages/DevicesSubPage';
import { ActiveSessionItem, devicesRowSubtitleKey } from '../main/ets/model/ActiveSessionItem';

const EN: SupportedLanguage = 'en';
const ZH: SupportedLanguage = 'zh';
const lang: Lang = Lang.getInstance();

export default function devicesSubPageTest(): void {
  describe('DevicesSubPageTest', () => {
    it('formatSessionDate_onlineWhenZeroOrNegative', 0, () => {
      expect(formatSessionDate(0, EN, '24h')).assertEqual('Online');
      expect(formatSessionDate(0, ZH, '24h')).assertEqual('在线');
      expect(formatSessionDate(-100, EN, '24h')).assertEqual('Online');
      expect(formatSessionDate(-100, ZH, '12h')).assertEqual('在线');
    });

    it('formatSessionDate_justNowUnderSixtySeconds', 0, () => {
      const nowSec = Math.floor(Date.now() / 1000);
      const recentSec = nowSec - 15;
      expect(formatSessionDate(recentSec, EN, '24h')).assertEqual('Just now');
      expect(formatSessionDate(recentSec, ZH, '24h')).assertEqual('刚刚');
    });

    it('formatSessionDate_minutesAgoUnderOneHour', 0, () => {
      const nowSec = Math.floor(Date.now() / 1000);
      const tenMinsAgoSec = nowSec - 600;
      expect(formatSessionDate(tenMinsAgoSec, EN, '24h')).assertEqual('10 min ago');
      expect(formatSessionDate(tenMinsAgoSec, ZH, '12h')).assertEqual('10 分钟前');
    });

    it('formatSessionDate_pastDateFormatting', 0, () => {
      // 过去特定固定时间戳：2020-05-15 12:30:00 本地时间
      const date2020 = new Date(2020, 4, 15, 12, 30, 0);
      const timestamp2020 = Math.floor(date2020.getTime() / 1000);

      const zhFormatted = formatSessionDate(timestamp2020, ZH, '24h');
      const enFormatted = formatSessionDate(timestamp2020, EN, '24h');

      expect(zhFormatted).assertEqual('2020年5月15日 12:30');
      // 英文日期本身带逗号，时刻用 `at` 连接而不是第三个逗号。
      expect(enFormatted).assertEqual('May 15, 2020 at 12:30');

      // I18N-DATE-102：整行形态都跟着时制档走（12 点是 12 而不是 0 或 24）。
      expect(formatSessionDate(timestamp2020, EN, '12h')).assertEqual('May 15, 2020 at 12:30 PM');
      expect(formatSessionDate(timestamp2020, ZH, '12h')).assertEqual('2020年5月15日 下午12:30');
    });

    it('devicesRowSubtitleKey_zeroSessionsKeepsTitleWithoutNumber', 0, () => {
      const zero: (string | number)[] = [];
      expect(devicesRowSubtitleKey(0)).assertEqual('Active Sessions');
      // 调用点对三档统一传 count，0 档的 key 不含 {0}，多余实参必须被忽略。
      expect(lang.formatByKey(devicesRowSubtitleKey(0), EN, zero)).assertEqual('Active Sessions');
    });

    it('devicesRowSubtitleKey_singularAndPluralEnglishForms', 0, () => {
      const one: (string | number)[] = [1];
      const three: (string | number)[] = [3];
      expect(devicesRowSubtitleKey(1)).assertEqual('{0} active session');
      expect(devicesRowSubtitleKey(3)).assertEqual('{0} active sessions');
      expect(lang.formatByKey(devicesRowSubtitleKey(1), EN, one)).assertEqual('1 active session');
      expect(lang.formatByKey(devicesRowSubtitleKey(3), EN, three)).assertEqual('3 active sessions');
      // 中文不分单复数，两档出同一句；跨语言只差措辞，字段集一致。
      expect(lang.formatByKey(devicesRowSubtitleKey(1), ZH, one)).assertEqual('1 个活跃会话');
      expect(lang.formatByKey(devicesRowSubtitleKey(3), ZH, three)).assertEqual('3 个活跃会话');
    });

    it('activeSessionItem_fieldsIntegrity', 0, () => {
      const item: ActiveSessionItem = {
        id: 'sess_123',
        isCurrent: true,
        deviceModel: 'HUAWEI Mate 60 Pro',
        platform: 'HarmonyOS NEXT',
        applicationName: 'Telegram X',
        applicationVersion: '0.26.8',
        ipAddress: '192.168.1.1',
        location: 'Shenzhen, China',
        lastActiveDate: 0
      };

      expect(item.id).assertEqual('sess_123');
      expect(item.isCurrent).assertTrue();
      expect(item.deviceModel).assertEqual('HUAWEI Mate 60 Pro');
      expect(item.platform).assertEqual('HarmonyOS NEXT');
      expect(item.applicationName).assertEqual('Telegram X');
      expect(item.applicationVersion).assertEqual('0.26.8');
      expect(item.ipAddress).assertEqual('192.168.1.1');
      expect(item.location).assertEqual('Shenzhen, China');
      expect(item.lastActiveDate).assertEqual(0);
    });
  });
}
