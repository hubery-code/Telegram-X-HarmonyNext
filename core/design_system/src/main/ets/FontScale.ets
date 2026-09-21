import { TextStyle, TypographyTokens, TYPOGRAPHY_TOKEN_NAMES } from './Typography';

/**
 * Font-scale adaptation. HarmonyOS exposes the system font size via
 * `display.getDefaultDisplaySync()` / configuration update callbacks;
 * the platform layer will feed the raw scale into this module. Pure math here.
 */

/** Supported range, matching HarmonyOS font-size settings behavior. */
export const FONT_SCALE_MIN: number = 0.85;
export const FONT_SCALE_MAX: number = 2.0;

/**
 * Absolute floor for scaled text. Below ~11vp body text becomes hard to
 * read even when the user asked for smaller text, so never go under this.
 */
export const MIN_READABLE_FONT_SIZE: number = 11;

/** Clamp an arbitrary (possibly untrusted platform) scale into the supported range. */
export function clampFontScale(scale: number): number {
  if (Number.isNaN(scale)) {
    return 1.0;
  }
  if (scale < FONT_SCALE_MIN) {
    return FONT_SCALE_MIN;
  }
  if (scale > FONT_SCALE_MAX) {
    return FONT_SCALE_MAX;
  }
  return scale;
}

/** Round to 1 decimal place to keep generated values stable in snapshots. */
function round1(value: number): number {
  return Math.round(value * 10) / 10;
}

/**
 * Scale one text style. Line height scales by the same factor but never
 * drops below the (also scaled, then floored) font size.
 */
export function scaleTextStyle(style: TextStyle, fontScale: number): TextStyle {
  const scale = clampFontScale(fontScale);
  const fontSize = Math.max(round1(style.fontSize * scale), MIN_READABLE_FONT_SIZE);
  const lineHeight = Math.max(round1(style.lineHeight * scale), fontSize);
  return {
    fontSize: fontSize,
    lineHeight: lineHeight,
    fontWeight: style.fontWeight
  };
}

/** Scale every style in the type scale, preserving names and weights. */
export function scaleTypography(tokens: TypographyTokens, fontScale: number): TypographyTokens {
  const scaled = {} as TypographyTokens;
  for (const name of TYPOGRAPHY_TOKEN_NAMES) {
    scaled[name] = scaleTextStyle(tokens[name], fontScale);
  }
  return scaled;
}

/* ------------------------------------------------------------------ *
 * 聊天字号（FEAT-UI-002 / SET-105）
 *
 * 与 `FontScale` 上面那套「系统字体缩放」是两条正交的旋钮：
 *   - fontScale   ：系统字号，0.85–2.0 连续倍率，作用全站；
 *   - chatFontSize：聊天消息字号，离散档位（sp），**只作用于消息内容文字**。
 * 档位值与 Telegram X `Settings.CHAT_FONT_SIZES` 逐值对齐，行为（含
 * 默认值与重置语义）亦对齐，便于 Parity 比对。
 * ------------------------------------------------------------------ */

/** 合法档位（sp）。与 TGX `Settings.CHAT_FONT_SIZES` 完全一致，顺序不可改。 */
export const CHAT_FONT_SIZE_STEPS: number[] = [12, 13, 14, 15, 16, 18, 20, 22, 24, 26];

/** 默认档位（sp），对齐 TGX `CHAT_FONT_SIZE_DEFAULT`。 */
export const CHAT_FONT_SIZE_DEFAULT: number = 15;

/** 最小 / 最大档位（sp），对齐 TGX `CHAT_FONT_SIZE_MIN` / `_MAX`。 */
export const CHAT_FONT_SIZE_MIN: number = CHAT_FONT_SIZE_STEPS[0];
export const CHAT_FONT_SIZE_MAX: number = CHAT_FONT_SIZE_STEPS[CHAT_FONT_SIZE_STEPS.length - 1];

/**
 * 把任意输入（可能是旧版本存的、或外部传入的脏值）吸附到最近的合法档位。
 * TGX 的 `isGoodChatFontSize` 是严格拒绝，这里选择吸附——持久化数据跨版本
 * 升级时不会因为档位表变化而丢掉用户设置。
 *
 * 参数收 `number | string`：该值在 AppStorage 里按字符串约定存放（`entry` 的
 * 装配层与 `feature_settings` 的 reducer 两侧都写 `${size}`，与跨进程/跨存储层的
 * 文本表示保持一致）。若不在这里做一次显式收敛，`Number.isFinite('26')` 会返回
 * false（它不做强制转换），合法档位会被误判成脏值、静默回落默认档。
 */
export function clampChatFontSize(fontSize: number | string): number {
  let value: number = Number.NaN;
  if (typeof fontSize === 'number') {
    value = fontSize;
  } else if (typeof fontSize === 'string' && fontSize.trim().length > 0) {
    // 空串/纯空白视为缺值 → NaN → 回落默认档，而不是被 Number('') === 0 骗成「最小档」。
    value = Number(fontSize);
  }
  if (Number.isNaN(value) || !Number.isFinite(value)) {
    return CHAT_FONT_SIZE_DEFAULT;
  }
  if (value <= CHAT_FONT_SIZE_MIN) {
    return CHAT_FONT_SIZE_MIN;
  }
  if (value >= CHAT_FONT_SIZE_MAX) {
    return CHAT_FONT_SIZE_MAX;
  }
  let best: number = CHAT_FONT_SIZE_DEFAULT;
  let bestDelta: number = Number.POSITIVE_INFINITY;
  for (let i = 0; i < CHAT_FONT_SIZE_STEPS.length; i++) {
    const step: number = CHAT_FONT_SIZE_STEPS[i];
    const delta: number = Math.abs(step - value);
    if (delta < bestDelta) {
      bestDelta = delta;
      best = step;
    }
  }
  return best;
}

/**
 * 恢复入口：从 AppStorage / 持久化层拿到的原始值 → 合法档位。
 * 单独成函数是因为「存储层往返」与「运行期脏值」是两回事：前者必须先做类型
 * 收敛，后者交给 `clampChatFontSize` 吸附。缺值（undefined / null）直接落默认档。
 */
export function parseChatFontSize(raw: number | string | undefined | null): number {
  if (raw === undefined || raw === null) {
    return CHAT_FONT_SIZE_DEFAULT;
  }
  return clampChatFontSize(raw);
}

/** 字号值 → 档位下标（设置页高亮当前档用）。非法值回落到默认档下标。 */
export function chatFontSizeIndex(fontSize: number): number {
  return CHAT_FONT_SIZE_STEPS.indexOf(clampChatFontSize(fontSize));
}

/** 档位下标 → 字号值（sp）。越界回落到默认档。 */
export function chatFontSizeAt(index: number): number {
  if (index < 0 || index >= CHAT_FONT_SIZE_STEPS.length) {
    return CHAT_FONT_SIZE_DEFAULT;
  }
  return CHAT_FONT_SIZE_STEPS[index];
}

/**
 * 相对默认档的缩放比。用于需要按比例联动、但语义上不属于字号的量
 * （例如行高、内边距的轻微跟随）。
 */
export function chatFontScaleOf(fontSize: number): number {
  return clampChatFontSize(fontSize) / CHAT_FONT_SIZE_DEFAULT;
}

/**
 * 消息内容文字的实际字号。
 *
 * 以现有排版 token 值为基准按聊天字号**倍率**等比缩放，再叠加相对偏移（偏移
 * 语义对齐 TGX `TGMessage` 的 `setTextSizeDiff`：署名/时间戳 −1~−2、反应 −4），
 * 最后守住 `MIN_READABLE_FONT_SIZE` 下限。
 *
 * 为什么用倍率而不是 TGX 那样的「绝对字号 + 偏移」：鸿蒙侧消息文字取自 9 档
 * 排版 token（body / subheadline / caption / footnote…），直接换成绝对字号会
 * 抹平 token 之间的层级差；倍率则保留层级，且默认档（15）倍率为 1.0，默认
 * 视觉与改造前逐像素一致。
 */
export function chatTextSizeOf(base: number, fontSize: number, diff: number = 0): number {
  const scaled: number = base * chatFontScaleOf(fontSize) + diff;
  return Math.max(Math.round(scaled * 10) / 10, MIN_READABLE_FONT_SIZE);
}

