/**
 * feature/settings — 设备管理与活跃会话时间格式化单测（DEVICES-101 / FEAT-P2-008）。
 *
 * 覆盖：
 * 1. formatSessionDate 在线状态（0 或负数时间戳）；
 * 2. 刚刚（< 60秒）中英双语；
 * 3. 分钟前（< 1小时）中英双语；
 * 4. 同年及跨年绝对时间格式化；
 * 5. ActiveSessionItem 模型对象装配完整性。
 */

import { describe, it, expect } from '@ohos/hypium';
import { formatSessionDate } from '../main/ets/pages/DevicesSubPage';
import { ActiveSessionItem } from '../main/ets/model/ActiveSessionItem';

export default function devicesSubPageTest(): void {
  describe('DevicesSubPageTest', () => {
    it('formatSessionDate_onlineWhenZeroOrNegative', 0, () => {
      expect(formatSessionDate(0, false)).assertEqual('Online');
      expect(formatSessionDate(0, true)).assertEqual('在线');
      expect(formatSessionDate(-100, false)).assertEqual('Online');
      expect(formatSessionDate(-100, true)).assertEqual('在线');
    });

    it('formatSessionDate_justNowUnderSixtySeconds', 0, () => {
      const nowSec = Math.floor(Date.now() / 1000);
      const recentSec = nowSec - 15;
      expect(formatSessionDate(recentSec, false)).assertEqual('Just now');
      expect(formatSessionDate(recentSec, true)).assertEqual('刚刚');
    });

    it('formatSessionDate_minutesAgoUnderOneHour', 0, () => {
      const nowSec = Math.floor(Date.now() / 1000);
      const tenMinsAgoSec = nowSec - 600;
      expect(formatSessionDate(tenMinsAgoSec, false)).assertEqual('10 min ago');
      expect(formatSessionDate(tenMinsAgoSec, true)).assertEqual('10 分钟前');
    });

    it('formatSessionDate_pastDateFormatting', 0, () => {
      // 过去特定固定时间戳：2020-05-15 12:30:00 UTC
      const date2020 = new Date(2020, 4, 15, 12, 30, 0);
      const timestamp2020 = Math.floor(date2020.getTime() / 1000);

      const zhFormatted = formatSessionDate(timestamp2020, true);
      const enFormatted = formatSessionDate(timestamp2020, false);

      expect(zhFormatted.includes('2020年5月15日')).assertTrue();
      expect(enFormatted.includes('May 15, 2020')).assertTrue();
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
