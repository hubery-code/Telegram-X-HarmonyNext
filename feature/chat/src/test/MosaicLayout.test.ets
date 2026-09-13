import { describe, it, expect } from '@ohos/hypium';
import { MediaAttachment } from '../main/ets/model/MediaAttachment';
import { calculateMosaicLayout, MosaicLayoutResult } from '../main/ets/model/MosaicLayout';

function makePhoto(width: number, height: number, fileId: number = 100): MediaAttachment {
  return new MediaAttachment(
    'photo',
    fileId,
    null,
    null,
    width,
    height,
    0,
    false,
    false,
    0,
    '',
    [],
    false
  );
}

export default function mosaicLayoutTest() {
  describe('MosaicLayoutTest', () => {

    it('returns empty result for 0 items', 0, () => {
      const res: MosaicLayoutResult = calculateMosaicLayout([], 256, 2, false);
      expect(res.lines.length).assertEqual(0);
      expect(res.width).assertEqual(0);
      expect(res.totalHeight).assertEqual(0);
    });

    it('calculates layout for single item', 0, () => {
      const p = makePhoto(800, 600);
      const res: MosaicLayoutResult = calculateMosaicLayout([p], 256, 2, false);
      expect(res.lines.length).assertEqual(1);
      expect(res.lines[0].items.length).assertEqual(1);
      expect(res.lines[0].items[0].width).assertEqual(256);
      expect(res.lines[0].items[0].needTopLeftRound).assertTrue();
      expect(res.lines[0].items[0].needTopRightRound).assertTrue();
      expect(res.lines[0].items[0].needBottomLeftRound).assertTrue();
      expect(res.lines[0].items[0].needBottomRightRound).assertTrue();
    });

    it('single item with caption has flat bottom corners', 0, () => {
      const p = makePhoto(800, 600);
      const res: MosaicLayoutResult = calculateMosaicLayout([p], 256, 2, true);
      expect(res.lines[0].items[0].needBottomLeftRound).assertFalse();
      expect(res.lines[0].items[0].needBottomRightRound).assertFalse();
    });

    it('calculates 2 items in 1 line of 2 or 2 lines', 0, () => {
      const items = [makePhoto(800, 600, 1), makePhoto(800, 600, 2)];
      const res: MosaicLayoutResult = calculateMosaicLayout(items, 256, 2, false);
      expect(res.lines.length > 0).assertTrue();
      let totalItems = 0;
      for (let i = 0; i < res.lines.length; i++) {
        totalItems += res.lines[i].items.length;
      }
      expect(totalItems).assertEqual(2);
    });

    it('calculates 3 items into 2 lines (1+2 or 2+1)', 0, () => {
      const items = [makePhoto(800, 800, 1), makePhoto(800, 800, 2), makePhoto(800, 800, 3)];
      const res: MosaicLayoutResult = calculateMosaicLayout(items, 256, 2, false);
      expect(res.lines.length).assertEqual(2);
      const c0 = res.lines[0].items.length;
      const c1 = res.lines[1].items.length;
      expect((c0 === 1 && c1 === 2) || (c0 === 2 && c1 === 1)).assertTrue();
    });

    it('calculates 4 items into 2x2 grid', 0, () => {
      const items = [
        makePhoto(800, 800, 1),
        makePhoto(800, 800, 2),
        makePhoto(800, 800, 3),
        makePhoto(800, 800, 4)
      ];
      const res: MosaicLayoutResult = calculateMosaicLayout(items, 256, 2, false);
      expect(res.lines.length).assertEqual(2);
      expect(res.lines[0].items.length).assertEqual(2);
      expect(res.lines[1].items.length).assertEqual(2);
    });

    it('calculates 6 items into 2 lines of 3 (3x2 grid)', 0, () => {
      const items = [
        makePhoto(800, 800, 1),
        makePhoto(800, 800, 2),
        makePhoto(800, 800, 3),
        makePhoto(800, 800, 4),
        makePhoto(800, 800, 5),
        makePhoto(800, 800, 6)
      ];
      const res: MosaicLayoutResult = calculateMosaicLayout(items, 256, 2, false);
      expect(res.lines.length).assertEqual(2);
      expect(res.lines[0].items.length).assertEqual(3);
      expect(res.lines[1].items.length).assertEqual(3);

      // Verify corner rounding: top-left & top-right on first line, bottom-left & bottom-right on last line
      expect(res.lines[0].items[0].needTopLeftRound).assertTrue();
      expect(res.lines[0].items[0].needTopRightRound).assertFalse();
      expect(res.lines[0].items[2].needTopRightRound).assertTrue();

      expect(res.lines[1].items[0].needBottomLeftRound).assertTrue();
      expect(res.lines[1].items[2].needBottomRightRound).assertTrue();
      // middle items should have no round corners
      expect(res.lines[0].items[1].needTopLeftRound).assertFalse();
      expect(res.lines[0].items[1].needTopRightRound).assertFalse();
      expect(res.lines[1].items[1].needBottomLeftRound).assertFalse();
      expect(res.lines[1].items[1].needBottomRightRound).assertFalse();
    });

    it('calculates 9 items into 3 lines of 3 (3x3 grid)', 0, () => {
      const items: MediaAttachment[] = [];
      for (let i = 0; i < 9; i++) {
        items.push(makePhoto(800, 800, 10 + i));
      }
      const res: MosaicLayoutResult = calculateMosaicLayout(items, 256, 2, true);
      expect(res.lines.length).assertEqual(3);
      expect(res.lines[0].items.length).assertEqual(3);
      expect(res.lines[1].items.length).assertEqual(3);
      expect(res.lines[2].items.length).assertEqual(3);

      // hasCaption = true: bottom row items should NOT have bottom rounding
      expect(res.lines[2].items[0].needBottomLeftRound).assertFalse();
      expect(res.lines[2].items[2].needBottomRightRound).assertFalse();
      expect(res.lines[0].items[0].needTopLeftRound).assertTrue();
      expect(res.lines[0].items[2].needTopRightRound).assertTrue();
    });

  });
}
