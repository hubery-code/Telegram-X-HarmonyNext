/**
 * feature/chat — 相册多图九宫格排版计算（FEAT-MEDIA-002 / MSG-107）。
 *
 * 移植自 Telegram X Android 端 MosaicWrapper.java：
 * - 智能纵横比裁剪（0.66667 ~ 1.7）；
 * - 2~10 张图片按行枚举（2~4 行，每行 1~3 张，总高最贴近 4:3 比例且惩罚倒金字塔）；
 * - 行内等高计算公式：lineHeight = (layoutWidth - (count-1)*spacing) / sum(ratios)；
 * - 外围四角圆角判定（结合 hasCaption 自适应底角直角/圆角）。
 */

import { MediaAttachment } from './MediaAttachment';

export interface MosaicItemGeometry {
  readonly index: number;
  readonly width: number;
  readonly height: number;
  readonly needTopLeftRound: boolean;
  readonly needTopRightRound: boolean;
  readonly needBottomLeftRound: boolean;
  readonly needBottomRightRound: boolean;
}

export interface MosaicLine {
  readonly lineHeight: number;
  readonly items: MosaicItemGeometry[];
}

export interface MosaicLayoutResult {
  readonly width: number;
  readonly totalHeight: number;
  readonly lines: MosaicLine[];
}

function multiHeight(ratios: readonly number[], start: number, end: number, maxWidth: number, spacing: number): number {
  let sum: number = 0;
  for (let i = start; i < end; i++) {
    sum += ratios[i];
  }
  const countInLine: number = end - start;
  if (sum <= 0) {
    return 80;
  }
  return Math.max(50, (maxWidth - (countInLine - 1) * spacing) / sum);
}

/**
 * 依据 Telegram X MosaicWrapper 计算相册中 2~10 张媒体的网格布局
 */
export function calculateMosaicLayout(
  items: readonly MediaAttachment[],
  maxWidth: number = 260,
  spacing: number = 2,
  hasCaption: boolean = false
): MosaicLayoutResult {
  const count: number = items.length;
  if (count === 0) {
    return { width: 0, totalHeight: 0, lines: [] };
  }

  if (count === 1) {
    const item: MediaAttachment = items[0];
    const rawRatio: number = (item.width > 0 && item.height > 0) ? (item.width / item.height) : 1.0;
    const clampedRatio: number = Math.max(0.5, Math.min(2.0, rawRatio));
    const h: number = Math.round(maxWidth / clampedRatio);
    return {
      width: maxWidth,
      totalHeight: h,
      lines: [{
        lineHeight: h,
        items: [{
          index: 0,
          width: maxWidth,
          height: h,
          needTopLeftRound: true,
          needTopRightRound: true,
          needBottomLeftRound: !hasCaption,
          needBottomRightRound: !hasCaption
        }]
      }]
    };
  }

  // 1. 提取并裁剪纵横比（对齐 Telegram X MosaicWrapper.java:598-613）
  const rawRatios: number[] = [];
  let ratioSum: number = 0;
  for (let i = 0; i < count; i++) {
    const it: MediaAttachment = items[i];
    const r: number = (it.width > 0 && it.height > 0) ? (it.width / it.height) : 1.0;
    rawRatios.push(r);
    ratioSum += r;
  }
  const avgRatio: number = ratioSum / count;

  const croppedRatios: number[] = [];
  for (let i = 0; i < count; i++) {
    let r: number = rawRatios[i];
    if (avgRatio > 1.1) {
      r = Math.max(1.0, r);
    } else {
      r = Math.min(1.0, r);
    }
    r = Math.max(0.66667, Math.min(1.7, r));
    croppedRatios.push(r);
  }

  // 2. 枚举合法的分行候选（对齐 MosaicWrapper.java:617-657）
  const attempts: number[][] = [];

  if (count === 2) {
    if (avgRatio > 1.4) {
      attempts.push([1, 1]);
    }
    attempts.push([2]);
  } else if (count === 3) {
    attempts.push([1, 2]);
    attempts.push([2, 1]);
    if (avgRatio > 1.3) {
      attempts.push([3]);
    }
  } else if (count === 4) {
    attempts.push([2, 2]);
    if (croppedRatios[0] > 1.2) {
      attempts.push([1, 3]);
    }
    if (croppedRatios[3] > 1.2) {
      attempts.push([3, 1]);
    }
  } else {
    // 5 ~ 10 张图：枚举 2~3 行，必要时枚举 4 行（count >= 7）
    // 2 行划分
    for (let l1 = 1; l1 < count; l1++) {
      const l2 = count - l1;
      if (l1 <= 3 && l2 <= 3) {
        attempts.push([l1, l2]);
      }
    }

    // 3 行划分
    for (let l1 = 1; l1 < count - 1; l1++) {
      for (let l2 = 1; l2 < count - l1; l2++) {
        const l3 = count - l1 - l2;
        const maxL2 = avgRatio < 0.85 ? 4 : 3;
        if (l1 <= 3 && l2 <= maxL2 && l3 <= 3) {
          attempts.push([l1, l2, l3]);
        }
      }
    }

    // 4 行划分（7 张以上）
    if (count >= 7) {
      for (let l1 = 1; l1 <= 3; l1++) {
        for (let l2 = 1; l2 <= 3; l2++) {
          for (let l3 = 1; l3 <= 3; l3++) {
            const l4 = count - l1 - l2 - l3;
            if (l4 >= 1 && l4 <= 3) {
              attempts.push([l1, l2, l3, l4]);
            }
          }
        }
      }
    }
  }

  // 若无候选，安全兜底按每行至多 3 张平铺
  if (attempts.length === 0) {
    const fallback: number[] = [];
    let rem: number = count;
    while (rem > 0) {
      const take: number = Math.min(3, rem);
      fallback.push(take);
      rem -= take;
    }
    attempts.push(fallback);
  }

  // 3. 评估最佳分行（对齐 Telegram X TGMessageMedia.java:472 与 MosaicWrapper.java:659-692）
  const targetMaxHeight: number = Math.round(maxWidth * (avgRatio > 1.2 ? 0.75 : (avgRatio < 0.8 ? 1.1 : 0.85)));
  let bestAttempt: number[] = attempts[0];
  let bestHeights: number[] = [];
  let minDiff: number = Number.MAX_VALUE;

  for (let a = 0; a < attempts.length; a++) {
    const lineCounts: number[] = attempts[a];
    const heights: number[] = [];
    let offset: number = 0;
    for (let i = 0; i < lineCounts.length; i++) {
      const c: number = lineCounts[i];
      const h: number = multiHeight(croppedRatios, offset, offset + c, maxWidth, spacing);
      heights.push(h);
      offset += c;
    }

    let totalH: number = spacing * (lineCounts.length - 1);
    for (let i = 0; i < heights.length; i++) {
      totalH += heights[i];
    }

    let diff: number = Math.abs(totalH - targetMaxHeight);

    // 倒金字塔惩罚（上多下少）：Telegram X 对首行 > 次行增加 1.5 倍惩罚
    if (lineCounts.length > 1) {
      for (let i = 0; i < lineCounts.length - 1; i++) {
        if (lineCounts[i] > lineCounts[i + 1]) {
          diff *= 1.5;
          break;
        }
      }
    }

    if (diff < minDiff || bestHeights.length === 0) {
      minDiff = diff;
      bestAttempt = lineCounts;
      bestHeights = heights;
    }
  }

  // 4. 构造各行及每个图片单元几何信息
  const lines: MosaicLine[] = [];
  let itemIdx: number = 0;
  let totalHeight: number = 0;

  for (let lineIndex = 0; lineIndex < bestAttempt.length; lineIndex++) {
    const lineCount: number = bestAttempt[lineIndex];
    const lineHeight: number = Math.max(50, Math.round(bestHeights[lineIndex]));
    const isFirstLine: boolean = (lineIndex === 0);
    const isLastLine: boolean = (lineIndex === bestAttempt.length - 1);

    let lineRatioSum: number = 0;
    for (let k = 0; k < lineCount; k++) {
      lineRatioSum += croppedRatios[itemIdx + k];
    }
    const availWidth: number = maxWidth - (lineCount - 1) * spacing;
    const lineItems: MosaicItemGeometry[] = [];
    let allocatedWidth: number = 0;

    for (let k = 0; k < lineCount; k++) {
      const isFirstInLine: boolean = (k === 0);
      const isLastInLine: boolean = (k === lineCount - 1);

      const itemWidth: number = isLastInLine
        ? (availWidth - allocatedWidth)
        : Math.round(availWidth * (croppedRatios[itemIdx + k] / (lineRatioSum > 0 ? lineRatioSum : 1)));
      allocatedWidth += itemWidth;

      const needTopLeftRound: boolean = isFirstLine && isFirstInLine;
      const needTopRightRound: boolean = isFirstLine && isLastInLine;
      const needBottomLeftRound: boolean = isLastLine && isFirstInLine && !hasCaption;
      const needBottomRightRound: boolean = isLastLine && isLastInLine && !hasCaption;

      lineItems.push({
        index: itemIdx + k,
        width: itemWidth,
        height: lineHeight,
        needTopLeftRound,
        needTopRightRound,
        needBottomLeftRound,
        needBottomRightRound
      });
    }

    lines.push({
      lineHeight: lineHeight,
      items: lineItems
    });

    itemIdx += lineCount;
    totalHeight += lineHeight + (isLastLine ? 0 : spacing);
  }

  return {
    width: maxWidth,
    totalHeight: totalHeight,
    lines: lines
  };
}
