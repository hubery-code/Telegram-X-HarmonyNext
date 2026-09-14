/**
 * platform/ports — FakeClipboard 与 FakeToast 单元测试（ARCH-001）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { FakeClipboard } from '../main/ets/fakes/FakeClipboard';
import { FakeToast } from '../main/ets/fakes/FakeToast';

export default function fakeClipboardAndToastTest() {
  describe('FakeClipboardAndToastTest', () => {
    it('FakeClipboard_setAndGet_succeeds', 0, async () => {
      const clipboard: FakeClipboard = new FakeClipboard();
      expect(await clipboard.getPlainText()).assertNull();
      expect(clipboard.getCount).assertEqual(1);
      expect(clipboard.setCount).assertEqual(0);

      await clipboard.setPlainText('hello telegram x');
      expect(clipboard.setCount).assertEqual(1);
      expect(await clipboard.getPlainText()).assertEqual('hello telegram x');
      expect(clipboard.getCount).assertEqual(2);

      clipboard.clear();
      expect(await clipboard.getPlainText()).assertNull();
      expect(clipboard.setCount).assertEqual(0);
      expect(clipboard.getCount).assertEqual(1);
    });

    it('FakeToast_recordsMessages_succeeds', 0, () => {
      const toast: FakeToast = new FakeToast();
      expect(toast.lastToast).assertNull();
      expect(toast.toasts.length).assertEqual(0);

      toast.showToast('Link copied to clipboard', 1500);
      expect(toast.toasts.length).assertEqual(1);
      expect(toast.lastToast).assertEqual('Link copied to clipboard');
      expect(toast.toasts[0].message).assertEqual('Link copied to clipboard');
      expect(toast.toasts[0].durationMs).assertEqual(1500);

      toast.showToast('Copied to clipboard');
      expect(toast.toasts.length).assertEqual(2);
      expect(toast.lastToast).assertEqual('Copied to clipboard');
      expect(toast.toasts[1].durationMs).assertEqual(2000);

      toast.clear();
      expect(toast.toasts.length).assertEqual(0);
      expect(toast.lastToast).assertNull();
    });
  });
}
