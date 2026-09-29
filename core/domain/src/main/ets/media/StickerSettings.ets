/**
 * core/domain — 「贴纸与表情」的本地设置（TGS-104）。
 *
 * 对齐 Android Telegram-X `unsorted/Settings.java:411` 的
 * `SETTING_FLAG_NO_ANIMATED_STICKERS_LOOP = 1 << 3`：Android 存的是**否定位**
 * （"不循环"），默认不勾 ⇒ 默认循环。消费点是
 * `TGMessageSticker.java:121-130` 的
 * `setPlayOnce(forcePlayOnce || specialType != SPECIAL_TYPE_NONE || noLoopSetting)`，
 * 本端既没有骰子 / 动效 emoji 这类 specialType，也没有强制单次播放的入口，
 * 那三项里只剩这一位可落，所以这一位就是「贴纸演一遍就停」与「一直演」的分界。
 *
 * 本端字段存**肯定语义** `loopAnimatedStickers`（默认 true，与 Android 首装一致），
 * 取反只发生在掩码边界：`toMask()` 里那位亮着 = **不**循环。位值沿用 Android 的 `1 << 3`，
 * 将来把「大号表情」「动态表情包排序」等位并进来时不必重新解释已落盘的整数。
 *
 * 键按账号隔离（前缀 + accountKey），与省流量、自动下载策略同构 —— 三份设置各自一个偏好键，
 * 各自读写、各自失败回滚。
 */

/** 偏好存储键前缀；完整键 = 前缀 + accountKey。 */
export const STICKER_SETTINGS_STORAGE_PREFIX: string = 'stickers_';

/**
 * Android 的否定位原值（`Settings.java:411`）。低三位被本端没有的设置占着，
 * 刻意不回填 —— 空位比自造位更容易和上游对齐。
 */
export const STICKER_FLAG_NO_ANIMATED_STICKERS_LOOP: number = 1 << 3;

export class StickerSettings {
  /** 动效贴纸是否循环播放。 */
  loopAnimatedStickers: boolean;

  constructor(loopAnimatedStickers: boolean = true) {
    this.loopAnimatedStickers = loopAnimatedStickers;
  }

  /** Android 首装默认：那位「不循环」没勾上 ⇒ 循环。 */
  static defaultSettings(): StickerSettings {
    return new StickerSettings(true);
  }

  static fromMask(mask: number): StickerSettings {
    if (!Number.isFinite(mask) || mask < 0) {
      return StickerSettings.defaultSettings();
    }
    const value: number = Math.floor(mask);
    return new StickerSettings((value & STICKER_FLAG_NO_ANIMATED_STICKERS_LOOP) === 0);
  }

  toMask(): number {
    return this.loopAnimatedStickers ? 0 : STICKER_FLAG_NO_ANIMATED_STICKERS_LOOP;
  }

  /** 不可变改位；调用方（reducer）拿返回值整体替换状态。 */
  withLoopEnabled(loop: boolean): StickerSettings {
    return new StickerSettings(loop);
  }

  clone(): StickerSettings {
    return new StickerSettings(this.loopAnimatedStickers);
  }

  equals(other: StickerSettings | null): boolean {
    if (other === null) {
      return false;
    }
    return this.loopAnimatedStickers === other.loopAnimatedStickers;
  }
}

/**
 * 播放侧的最终判定。`null`（还没读盘）按 Android 的默认档走 = 循环：
 * 读盘失败就把用户的贴纸停在末帧，是那种「设置页说开着、屏幕上却没动」的错。
 */
export function stickerLoopEnabled(settings: StickerSettings | null): boolean {
  return settings === null ? true : settings.loopAnimatedStickers;
}

/** 设置读写面；实现方负责按账号隔离与落盘（entry 装配层）。 */
export interface StickerSettingsStore {
  /** 读取；读不到/失败返回 null，调用方回落默认且不回写。 */
  load(): StickerSettings | null;

  /** 写入；返回是否成功（失败时 UI 回滚到盘上的真值）。 */
  save(settings: StickerSettings): boolean;
}
