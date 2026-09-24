/**
 * feature/chat — 全屏查看器的缩放与位移几何（MEDIA-VIEWER-101 / FEAT-P2-006）。
 *
 * 只做纯数学：给定图像像素尺寸、视口（vp）与当前 scale/offset，算出贴合矩形、
 * 缩放上下限和夹紧后的位移；ArkUI 侧只负责把结果写进 `.scale()` / `.translate()`。
 *
 * 对齐 Telegram X `MediaCellView`：
 * - 初始态等比贴合（`SCALE_TYPE_CENTER_INSIDE`）；
 * - 缩放区间 [1, maxScale]，`maxScale` 由**图像真实像素**与屏幕密度决定，
 *   而不是一个写死的 3.5 —— 一张 4000px 的照片放大到 1:1 才谈得上「看清」，
 *   而一张 320px 的缩略图放大到 3× 只是糊；
 * - 拖动不得把内容拖出视口（`PAN_LIMIT_INSIDE`）；
 * - 双击落在 1:1 像素档，夹在 [2×, maxScale]。
 */

export interface ViewerRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

export interface ViewerOffset {
  readonly x: number;
  readonly y: number;
}

/** 最小缩放：等比贴合，整张图都在画面里。 */
export const VIEWER_MIN_SCALE: number = 1.0;
/**
 * 1:1 像素之后再给的余量。1.5 是「看得清还想再凑近一点」的经验值，
 * 再大就只是在放大插值出来的马赛克。
 */
export const VIEWER_NATIVE_HEADROOM: number = 1.5;
/** 缩放硬上限，防止超长图算出几十倍的 scale 把合成层压垮。 */
export const VIEWER_MAX_SCALE_CAP: number = 8.0;
/** 双击至少放大到 2×，也是「1:1 像素算不出来时」的兜底倍率。 */
export const VIEWER_DOUBLE_TAP_SCALE: number = 2.0;
/** 图像尺寸未知时的兜底上限（沿用旧实现，读不到尺寸不该让人缩不了放）。 */
export const VIEWER_FALLBACK_MAX_SCALE: number = 3.5;
/** 长图判定阈值：高 > 2×宽（TGX 气泡 `MIN_RATIO = 0.5` 同一档比例）。 */
export const VIEWER_TALL_RATIO: number = 2.0;

function isSaneSize(value: number): boolean {
  return Number.isFinite(value) && value > 0;
}

/**
 * 等比贴合（`ImageFit.Contain`）后内容在视口内的矩形，单位 vp。
 * 尺寸缺失时退化为「铺满视口」，与 ArkUI 对空尺寸的处理一致。
 */
export function viewerContentRect(
  imageWidth: number,
  imageHeight: number,
  viewportWidth: number,
  viewportHeight: number
): ViewerRect {
  if (!isSaneSize(imageWidth) || !isSaneSize(imageHeight) ||
    !isSaneSize(viewportWidth) || !isSaneSize(viewportHeight)) {
    return { x: 0, y: 0, width: viewportWidth, height: viewportHeight };
  }
  const ratio: number = imageWidth / imageHeight;
  let w: number = viewportWidth;
  let h: number = viewportWidth / ratio;
  if (h > viewportHeight) {
    h = viewportHeight;
    w = viewportHeight * ratio;
  }
  return { x: (viewportWidth - w) / 2, y: (viewportHeight - h) / 2, width: w, height: h };
}

/**
 * 1:1 像素倍率：让 1 个图像像素正好落在 1 个物理像素上。
 *
 * `contentWidth` 是 scale=1 时内容的 vp 宽（见 `viewerContentRect`），
 * `densityPxPerVp` 即 `display.getDefaultDisplaySync().densityPixels`。
 * 这就是「照片上的小字终于能读」的那一档，
 * 所以双击要落在它上面，而不是落在一个凭手感写的 2×。
 */
export function viewerNativeScale(
  imageWidth: number,
  contentWidth: number,
  densityPxPerVp: number
): number {
  if (!isSaneSize(imageWidth) || !isSaneSize(contentWidth) || !isSaneSize(densityPxPerVp)) {
    return VIEWER_DOUBLE_TAP_SCALE;
  }
  return imageWidth / (contentWidth * densityPxPerVp);
}

/**
 * 缩放上限：先到 1:1 像素，再乘余量。
 *
 * 尺寸算不出来时退回旧的写死值 —— 读不到尺寸不该让人缩不了放。
 */
export function viewerMaxScale(
  imageWidth: number,
  contentWidth: number,
  densityPxPerVp: number
): number {
  if (!isSaneSize(imageWidth) || !isSaneSize(contentWidth) || !isSaneSize(densityPxPerVp)) {
    return VIEWER_FALLBACK_MAX_SCALE;
  }
  const target: number = viewerNativeScale(imageWidth, contentWidth, densityPxPerVp) * VIEWER_NATIVE_HEADROOM;
  // 至少留 2×：小图（贴纸、缩略图兜底）也得能凑近看。
  return Math.min(VIEWER_MAX_SCALE_CAP, Math.max(VIEWER_DOUBLE_TAP_SCALE, target));
}

/** 把任意输入（含 NaN / 越界）夹紧到 [min, max]。 */
export function clampViewerScale(scale: number, maxScale: number): number {
  if (!Number.isFinite(scale)) {
    return VIEWER_MIN_SCALE;
  }
  const upper: number = Math.max(VIEWER_MIN_SCALE, maxScale);
  if (scale < VIEWER_MIN_SCALE) {
    return VIEWER_MIN_SCALE;
  }
  if (scale > upper) {
    return upper;
  }
  return scale;
}

/**
 * 双击目标倍率：1:1 像素，夹在 [2×, maxScale]。
 *
 * 小图（native < 2）也至少放大 2× 才看得出是在放大；超大图不会超过上限。
 */
export function viewerDoubleTapScale(maxScale: number, nativeScale: number): number {
  const wanted: number = Math.max(VIEWER_DOUBLE_TAP_SCALE, nativeScale);
  return clampViewerScale(wanted, maxScale);
}

/**
 * 位移夹紧（`PAN_LIMIT_INSIDE`）：内容比视口大的那一轴上，边缘不得进入视口；
 * 比视口小的那一轴只能居中（返回 0）。
 */
export function clampViewerOffset(
  offsetX: number,
  offsetY: number,
  scale: number,
  content: ViewerRect,
  viewportWidth: number,
  viewportHeight: number
): ViewerOffset {
  return {
    x: clampAxis(offsetX, content.width * scale, viewportWidth),
    y: clampAxis(offsetY, content.height * scale, viewportHeight)
  };
}

function clampAxis(offset: number, scaledSize: number, viewportSize: number): number {
  const limit: number = (scaledSize - viewportSize) / 2;
  if (!Number.isFinite(offset) || limit <= 0) {
    return 0;
  }
  if (offset > limit) {
    return limit;
  }
  if (offset < -limit) {
    return -limit;
  }
  return offset;
}

/**
 * 换倍率时保持焦点不动：让 `focal`（相对视口中心，vp）下方的那个内容点
 * 在 `newScale` 下仍然落在 `focal` 上。
 *
 * 内容中心 = 视口中心 + offset，所以 focal 处的未缩放内容坐标
 * `u = (focal - offset) / oldScale`，新位移 = `focal - u * newScale`。
 */
export function viewerOffsetForZoom(
  focalX: number,
  focalY: number,
  offsetX: number,
  offsetY: number,
  oldScale: number,
  newScale: number
): ViewerOffset {
  if (!Number.isFinite(oldScale) || oldScale <= 0) {
    return { x: offsetX, y: offsetY };
  }
  const factor: number = newScale / oldScale;
  return {
    x: focalX - (focalX - offsetX) * factor,
    y: focalY - (focalY - offsetY) * factor
  };
}

/** 长图：高宽比超过阈值时，贴合态下横向只占一小条，必须能放大 + 纵向拖动。 */
export function isTallImage(imageWidth: number, imageHeight: number): boolean {
  if (!isSaneSize(imageWidth) || !isSaneSize(imageHeight)) {
    return false;
  }
  return imageHeight / imageWidth > VIEWER_TALL_RATIO;
}
