/**
 * feature/chat — 查看器缩放/位移几何单测（MEDIA-VIEWER-101）。
 *
 * 模拟器上的 uitest 注入不了双指捏合，所以缩放区间、焦点保持、位移夹紧这些
 * 只能靠纯函数用例证明；页面侧只保留「把结果写进 transform」的部分。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  VIEWER_DOUBLE_TAP_SCALE,
  VIEWER_FALLBACK_MAX_SCALE,
  VIEWER_MAX_SCALE_CAP,
  ViewerOffset,
  ViewerRect,
  clampViewerOffset,
  clampViewerScale,
  isTallImage,
  viewerContentRect,
  viewerDoubleTapScale,
  viewerMaxScale,
  viewerNativeScale,
  viewerOffsetForZoom
} from '../main/ets/model/ViewerTransform';

const VP_W: number = 360;
const VP_H: number = 780;
const DENSITY: number = 3.5;

export default function viewerTransformTest() {
  describe('ViewerTransformTest', () => {

    it('contentRect_landscapeFitsWidthAndCenters', 0, () => {
      const r: ViewerRect = viewerContentRect(4000, 3000, VP_W, VP_H);
      expect(r.width).assertEqual(VP_W);
      expect(Math.round(r.height)).assertEqual(270);
      expect(r.x).assertEqual(0);
      expect(Math.round(r.y)).assertEqual(255);
    });

    it('contentRect_tallImageFitsHeightAndNarrows', 0, () => {
      const r: ViewerRect = viewerContentRect(1000, 6000, VP_W, VP_H);
      expect(r.height).assertEqual(VP_H);
      expect(Math.round(r.width)).assertEqual(130);
      expect(Math.round(r.x)).assertEqual(115);
      expect(r.y).assertEqual(0);
    });

    it('contentRect_degradesToViewportWhenSizeUnknown', 0, () => {
      const r: ViewerRect = viewerContentRect(0, 0, VP_W, VP_H);
      expect(r.width).assertEqual(VP_W);
      expect(r.height).assertEqual(VP_H);
    });

    it('nativeScale_isOneImagePixelPerPhysicalPixel', 0, () => {
      // 4000px 铺满 360vp（=1260 物理像素）→ 1:1 要 4000/1260 倍
      const native: number = viewerNativeScale(4000, VP_W, DENSITY);
      expect(Math.round(native * 1000) / 1000).assertEqual(3.175);
    });

    it('maxScale_isNativePlusHeadroom', 0, () => {
      const native: number = viewerNativeScale(4000, VP_W, DENSITY);
      const max: number = viewerMaxScale(4000, VP_W, DENSITY);
      expect(Math.abs(max - native * 1.5) < 0.001).assertTrue();
    });

    it('maxScale_cappedForHugeImages', 0, () => {
      expect(viewerMaxScale(40000, VP_W, DENSITY)).assertEqual(VIEWER_MAX_SCALE_CAP);
    });

    it('maxScale_keepsTwoXFloorForSmallImages', 0, () => {
      // 320px 的显示档铺满 360vp：native < 1，仍要能放大到 2× 才看得出是在放大
      expect(viewerMaxScale(320, VP_W, DENSITY)).assertEqual(VIEWER_DOUBLE_TAP_SCALE);
    });

    it('maxScale_fallsBackWhenSizeUnknown', 0, () => {
      expect(viewerMaxScale(0, VP_W, DENSITY)).assertEqual(VIEWER_FALLBACK_MAX_SCALE);
      expect(viewerMaxScale(4000, 0, DENSITY)).assertEqual(VIEWER_FALLBACK_MAX_SCALE);
      expect(viewerMaxScale(4000, VP_W, 0)).assertEqual(VIEWER_FALLBACK_MAX_SCALE);
    });

    it('clampScale_pinsToRange', 0, () => {
      expect(clampViewerScale(0.2, 5)).assertEqual(1.0);
      expect(clampViewerScale(9, 5)).assertEqual(5);
      expect(clampViewerScale(Number.NaN, 5)).assertEqual(1.0);
      // maxScale 算出小于 1 时也不能让人缩到看不见
      expect(clampViewerScale(2, 0.5)).assertEqual(1.0);
    });

    it('doubleTapTarget_landsOnOneToOneForLargePhoto', 0, () => {
      const native: number = viewerNativeScale(4000, VP_W, DENSITY);
      const target: number = viewerDoubleTapScale(viewerMaxScale(4000, VP_W, DENSITY), native);
      expect(Math.abs(target - native) < 0.001).assertTrue();
    });

    it('doubleTapTarget_neverBelowFloorAndNeverAboveCap', 0, () => {
      expect(viewerDoubleTapScale(8, 0.4)).assertEqual(VIEWER_DOUBLE_TAP_SCALE);
      expect(viewerDoubleTapScale(1.4, 6)).assertEqual(1.4);
    });

    it('clampOffset_keepsContentInsideWhenZoomed', 0, () => {
      const content: ViewerRect = viewerContentRect(4000, 3000, VP_W, VP_H);
      const limitX: number = (content.width * 3 - VP_W) / 2;
      const limitY: number = (content.height * 3 - VP_H) / 2;
      expect(limitX).assertEqual(360);
      expect(limitY).assertEqual(15);
      const far: ViewerOffset = clampViewerOffset(99999, -99999, 3, content, VP_W, VP_H);
      expect(far.x).assertEqual(limitX);
      expect(far.y).assertEqual(-limitY);
      expect(clampViewerOffset(10, 0, 3, content, VP_W, VP_H).x).assertEqual(10);
    });

    it('clampOffset_forcesCenterOnAxisSmallerThanViewport', 0, () => {
      const content: ViewerRect = viewerContentRect(4000, 3000, VP_W, VP_H);
      // scale=1 时高 270 < 视口 780：纵向不许拖出黑边
      const o: ViewerOffset = clampViewerOffset(40, 40, 1, content, VP_W, VP_H);
      expect(o.x).assertEqual(0);
      expect(o.y).assertEqual(0);
    });

    it('clampOffset_zeroesNaN', 0, () => {
      const content: ViewerRect = viewerContentRect(4000, 3000, VP_W, VP_H);
      expect(clampViewerOffset(Number.NaN, Number.NaN, 3, content, VP_W, VP_H).x).assertEqual(0);
    });

    it('offsetForZoom_pinsFocalPoint', 0, () => {
      // 焦点在视口中心右 100vp：1× → 3× 后那个内容点仍要落在 100vp
      const o: ViewerOffset = viewerOffsetForZoom(100, -60, 0, 0, 1, 3);
      expect(o.x).assertEqual(-200);
      expect(o.y).assertEqual(120);
      const beforeU: number = (100 - 0) / 1;
      const afterU: number = (100 - o.x) / 3;
      expect(Math.abs(beforeU - afterU) < 0.0001).assertTrue();
    });

    it('offsetForZoom_isIdentityWithoutValidOldScale', 0, () => {
      const o: ViewerOffset = viewerOffsetForZoom(50, 50, 7, 9, 0, 2);
      expect(o.x).assertEqual(7);
      expect(o.y).assertEqual(9);
    });

    it('isTallImage_flagsOnlyReallyTall', 0, () => {
      expect(isTallImage(1080, 4000)).assertTrue();
      expect(isTallImage(1080, 2000)).assertFalse();
      expect(isTallImage(0, 4000)).assertFalse();
    });
  });
}
