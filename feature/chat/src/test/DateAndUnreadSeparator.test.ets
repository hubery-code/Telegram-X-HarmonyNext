import { describe, it, expect } from '@ohos/hypium';
import { MessageItem } from '../main/ets/model/MessageItem';
import { isSameDay, formatDateHeader } from '../main/ets/coordinator/ChatCoordinator';

class TestMsgStub {
  id: number;
  outgoing: boolean;

  constructor(id: number, outgoing: boolean) {
    this.id = id;
    this.outgoing = outgoing;
  }
}

export default function dateAndUnreadSeparatorTest() {
  describe('DateAndUnreadSeparatorTest', () => {
    it('isSameDay_sameDayDifferentTime_returnsTrue', 0, () => {
      // 2026-09-11 10:00:00 vs 2026-09-11 23:59:59
      const t1: number = new Date(2026, 8, 11, 10, 0, 0).getTime();
      const t2: number = new Date(2026, 8, 11, 23, 59, 59).getTime();
      expect(isSameDay(t1, t2)).assertTrue();
    });

    it('isSameDay_differentDay_returnsFalse', 0, () => {
      const t1: number = new Date(2026, 8, 11, 23, 59, 59).getTime();
      const t2: number = new Date(2026, 8, 12, 0, 0, 1).getTime();
      expect(isSameDay(t1, t2)).assertFalse();
    });

    it('isSameDay_differentYear_returnsFalse', 0, () => {
      const t1: number = new Date(2025, 8, 11, 12, 0, 0).getTime();
      const t2: number = new Date(2026, 8, 11, 12, 0, 0).getTime();
      expect(isSameDay(t1, t2)).assertFalse();
    });

    it('formatDateHeader_currentYear_formatsMonthDay', 0, () => {
      const currentYear: number = new Date().getFullYear();
      const t: number = new Date(currentYear, 8, 11).getTime(); // 9月11日
      expect(formatDateHeader(t)).assertEqual('9月11日');
    });

    it('formatDateHeader_differentYear_formatsYearMonthDay', 0, () => {
      const pastYear: number = 2020;
      const t: number = new Date(pastYear, 0, 15).getTime(); // 2020年1月15日
      expect(formatDateHeader(t)).assertEqual('2020年1月15日');
    });

    it('MessageItem_defaultValues_areFalseAndEmpty', 0, () => {
      const item: MessageItem = new MessageItem(1, 'test', 1000, false, 'User');
      expect(item.showDateHeader).assertFalse();
      expect(item.dateHeaderText).assertEqual('');
      expect(item.showUnreadSeparator).assertFalse();
    });

    it('MessageItem_explicitValues_areRetained', 0, () => {
      const item: MessageItem = new MessageItem(
        2,
        'hello',
        2000,
        false,
        'Alice',
        'none',
        true,
        false,
        null,
        '',
        [],
        -1,
        false,
        null,
        '',
        -1,
        null,
        false,
        true,
        '9月11日',
        true
      );
      expect(item.showDateHeader).assertTrue();
      expect(item.dateHeaderText).assertEqual('9月11日');
      expect(item.showUnreadSeparator).assertTrue();
    });

    it('dateHeader_insertionAtDayBoundaries', 0, () => {
      const d1Morning: number = new Date(2026, 8, 10, 8, 0).getTime();
      const d1Evening: number = new Date(2026, 8, 10, 20, 0).getTime();
      const d2Morning: number = new Date(2026, 8, 11, 9, 0).getTime();
      const timestamps: number[] = [d1Morning, d1Evening, d2Morning];

      const showHeaders: boolean[] = [];
      for (let i = 0; i < timestamps.length; i++) {
        if (i === 0) {
          showHeaders.push(true);
        } else {
          showHeaders.push(!isSameDay(timestamps[i - 1], timestamps[i]));
        }
      }

      expect(showHeaders[0]).assertTrue();
      expect(showHeaders[1]).assertFalse();
      expect(showHeaders[2]).assertTrue();
    });

    it('unreadSeparator_assignedOnlyToFirstIncomingUnread', 0, () => {
      const lastReadInbox: number = 10;
      const msgs: TestMsgStub[] = [
        new TestMsgStub(10, false),
        new TestMsgStub(20, true),
        new TestMsgStub(30, false),
        new TestMsgStub(40, false)
      ];

      let firstUnreadId: number | null = null;
      for (let i = 0; i < msgs.length; i++) {
        if (!msgs[i].outgoing && msgs[i].id > lastReadInbox) {
          firstUnreadId = msgs[i].id;
          break;
        }
      }

      expect(firstUnreadId).assertEqual(30);

      const hasSeparator: boolean[] = msgs.map((m: TestMsgStub) => firstUnreadId !== null && m.id === firstUnreadId);
      expect(hasSeparator[0]).assertFalse();
      expect(hasSeparator[1]).assertFalse();
      expect(hasSeparator[2]).assertTrue();
      expect(hasSeparator[3]).assertFalse();
    });
  });
}
