/**
 * feature/chat — 转发多选集合与目标选择器纯函数单测（MSG-106）。
 *
 * 覆盖：
 * 1. toggleMessageSelection：增删、恒升序、无重复、不可变（入参不被改动）；
 * 2. isMessageSelected / clearSelection；
 * 3. retainExistingSelection：剔除已消失的消息，无变化返回原引用；
 * 4. matchesForwardQuery：大小写不敏感、空查询恒匹配、去首尾空白。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  clearSelection,
  isMessageSelected,
  retainExistingSelection,
  toggleMessageSelection
} from '../main/ets/model/ForwardSelection';
import { ForwardTarget, matchesForwardQuery } from '../main/ets/model/ForwardTarget';

export default function forwardSelectionTest() {
  describe('ForwardSelectionTest', () => {
    it('toggleMessageSelection_addsAndRemoves', 0, () => {
      let selected: number[] = [];
      selected = toggleMessageSelection(selected, 10);
      expect(isMessageSelected(selected, 10)).assertTrue();
      expect(selected.length).assertEqual(1);

      selected = toggleMessageSelection(selected, 10);
      expect(isMessageSelected(selected, 10)).assertFalse();
      expect(selected.length).assertEqual(0);
    });

    it('toggleMessageSelection_keepsAscendingOrderRegardlessOfTapOrder', 0, () => {
      let selected: number[] = [];
      selected = toggleMessageSelection(selected, 30);
      selected = toggleMessageSelection(selected, 10);
      selected = toggleMessageSelection(selected, 20);
      // TDLib forwardMessages 要求严格递增，选择集合直接可用，无需再排序
      expect(selected[0]).assertEqual(10);
      expect(selected[1]).assertEqual(20);
      expect(selected[2]).assertEqual(30);
    });

    it('toggleMessageSelection_doesNotMutateInput', 0, () => {
      const original: number[] = [10, 20];
      const added: number[] = toggleMessageSelection(original, 30);
      expect(original.length).assertEqual(2);
      expect(added.length).assertEqual(3);

      const removed: number[] = toggleMessageSelection(original, 10);
      expect(original.length).assertEqual(2);
      expect(original[0]).assertEqual(10);
      expect(removed.length).assertEqual(1);
      expect(removed[0]).assertEqual(20);
    });

    it('clearSelection_returnsEmptyArray', 0, () => {
      expect(clearSelection().length).assertEqual(0);
    });

    it('retainExistingSelection_dropsMissingIds', 0, () => {
      const pruned: readonly number[] = retainExistingSelection(
        [10, 20, 30],
        (messageId: number): boolean => messageId !== 20
      );
      expect(pruned.length).assertEqual(2);
      expect(pruned[0]).assertEqual(10);
      expect(pruned[1]).assertEqual(30);
    });

    it('retainExistingSelection_returnsSameRefWhenNothingDropped', 0, () => {
      const original: number[] = [10, 20];
      const pruned: readonly number[] = retainExistingSelection(original, (): boolean => true);
      expect(pruned === original).assertTrue();
    });

    it('matchesForwardQuery_isCaseInsensitiveAndBlankMatchesAll', 0, () => {
      expect(matchesForwardQuery('Alice', '')).assertTrue();
      expect(matchesForwardQuery('Alice', '   ')).assertTrue();
      expect(matchesForwardQuery('Alice', 'ali')).assertTrue();
      expect(matchesForwardQuery('Alice', 'ALI')).assertTrue();
      expect(matchesForwardQuery('Alice', 'bob')).assertFalse();
      expect(matchesForwardQuery('EI CLUB', ' club ')).assertTrue();
    });

    it('forwardTarget_marksSourceChat', 0, () => {
      const source: ForwardTarget = new ForwardTarget(7, 'Chat', '#FF000000', 'C', true);
      const other: ForwardTarget = new ForwardTarget(7, 'Chat', '#FF000000', 'C');
      expect(source.isSourceChat).assertTrue();
      expect(other.isSourceChat).assertFalse();
    });
  });
}
