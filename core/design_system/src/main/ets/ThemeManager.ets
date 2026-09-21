/**
 * Global theme management contract (SET-102 / FEAT-UI-001).
 *
 * Provides:
 * - ThemePreference: 'system' | 'light' | 'dark'
 * - ThemeManager: runtime theme coordinator supporting preference switching,
 *   system color mode tracking, reactive listener subscriptions, and pure
 *   resolution of effective Theme instances.
 * - 100% Kit-free pure ArkTS domain logic.
 */

import { DarkTheme, LightTheme, Theme, ThemeMode, ThemePreference, createTheme } from './Theme';
import { CHAT_FONT_SIZE_DEFAULT, clampChatFontSize } from './FontScale';

export { ThemePreference };
export type ThemeListener = (theme: Theme) => void;

/**
 * Pure function: resolve effective ThemeMode ('light' | 'dark') from preference and system mode.
 */
export function resolveThemeMode(
  preference: ThemePreference,
  systemMode: ThemeMode = 'light'
): ThemeMode {
  if (preference === 'light' || preference === 'dark') {
    return preference;
  }
  return systemMode === 'dark' ? 'dark' : 'light';
}

/**
 * Pure function: resolve effective Theme instance from preference, system mode,
 * optional font scale, and optional chat font size.
 */
export function resolveTheme(
  preference: ThemePreference,
  systemMode: ThemeMode = 'light',
  fontScale: number = 1.0,
  chatFontSize: number = CHAT_FONT_SIZE_DEFAULT
): Theme {
  const mode: ThemeMode = resolveThemeMode(preference, systemMode);
  if (fontScale === 1.0 && chatFontSize === CHAT_FONT_SIZE_DEFAULT) {
    return mode === 'dark' ? DarkTheme : LightTheme;
  }
  return createTheme(mode, fontScale, chatFontSize);
}

export class ThemeManager {
  private static instance: ThemeManager | null = null;

  private preference: ThemePreference = 'system';
  private systemMode: ThemeMode = 'light';
  private fontScale: number = 1.0;
  private chatFontSize: number = CHAT_FONT_SIZE_DEFAULT;
  private currentTheme: Theme = LightTheme;
  private readonly listeners: ThemeListener[] = [];

  constructor(
    initialPreference: ThemePreference = 'system',
    initialSystemMode: ThemeMode = 'light',
    initialFontScale: number = 1.0,
    initialChatFontSize: number = CHAT_FONT_SIZE_DEFAULT
  ) {
    this.preference = initialPreference;
    this.systemMode = initialSystemMode;
    this.fontScale = initialFontScale;
    this.chatFontSize = clampChatFontSize(initialChatFontSize);
    this.currentTheme = resolveTheme(
      this.preference,
      this.systemMode,
      this.fontScale,
      this.chatFontSize
    );
  }

  static getInstance(): ThemeManager {
    if (ThemeManager.instance === null) {
      ThemeManager.instance = new ThemeManager();
    }
    return ThemeManager.instance;
  }

  /**
   * Resets the singleton instance (useful for unit test isolation).
   */
  static resetInstance(): void {
    if (ThemeManager.instance !== null) {
      ThemeManager.instance.reset();
    }
  }

  getPreference(): ThemePreference {
    return this.preference;
  }

  setPreference(preference: ThemePreference): void {
    if (this.preference === preference) {
      return;
    }
    this.preference = preference;
    this.updateEffectiveTheme();
  }

  getSystemMode(): ThemeMode {
    return this.systemMode;
  }

  setSystemMode(mode: ThemeMode): void {
    if (this.systemMode === mode) {
      return;
    }
    this.systemMode = mode;
    if (this.preference === 'system') {
      this.updateEffectiveTheme();
    }
  }

  /**
   * Alias for setSystemMode for compatibility with system color mode callbacks.
   */
  setSystemColorMode(mode: ThemeMode): void {
    this.setSystemMode(mode);
  }

  getFontScale(): number {
    return this.fontScale;
  }

  setFontScale(scale: number): void {
    if (this.fontScale === scale) {
      return;
    }
    this.fontScale = scale;
    this.updateEffectiveTheme();
  }

  /** FEAT-UI-002 / SET-105：当前聊天字号（sp，恒为合法档位）。 */
  getChatFontSize(): number {
    return this.chatFontSize;
  }

  /**
   * 设置聊天字号。输入会被吸附到最近的合法档位——TGX `setChatFontSize` 是
   * 严格拒绝非法值（返回 false），这里选择吸附，使跨版本持久化数据不会因
   * 档位表变化而丢失用户设置。
   */
  setChatFontSize(fontSize: number): void {
    const next: number = clampChatFontSize(fontSize);
    if (this.chatFontSize === next) {
      return;
    }
    this.chatFontSize = next;
    this.updateEffectiveTheme();
  }

  getTheme(): Theme {
    return this.currentTheme;
  }

  getEffectiveTheme(): Theme {
    return this.currentTheme;
  }

  getEffectiveMode(): ThemeMode {
    return this.currentTheme.mode;
  }

  resolveTheme(preference: ThemePreference, systemMode?: ThemeMode): Theme {
    return resolveTheme(
      preference,
      systemMode !== undefined ? systemMode : this.systemMode,
      this.fontScale,
      this.chatFontSize
    );
  }

  resolveThemeMode(preference: ThemePreference, systemMode?: ThemeMode): ThemeMode {
    return resolveThemeMode(
      preference,
      systemMode !== undefined ? systemMode : this.systemMode
    );
  }

  subscribe(listener: ThemeListener, notifyImmediately: boolean = false): () => void {
    this.listeners.push(listener);
    if (notifyImmediately) {
      listener(this.currentTheme);
    }
    return (): void => {
      this.unsubscribe(listener);
    };
  }

  unsubscribe(listener: ThemeListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  reset(): void {
    this.preference = 'system';
    this.systemMode = 'light';
    this.fontScale = 1.0;
    this.chatFontSize = CHAT_FONT_SIZE_DEFAULT;
    this.listeners.length = 0;
    this.currentTheme = resolveTheme('system', 'light', 1.0, CHAT_FONT_SIZE_DEFAULT);
  }

  private updateEffectiveTheme(): void {
    const nextTheme: Theme = resolveTheme(
      this.preference,
      this.systemMode,
      this.fontScale,
      this.chatFontSize
    );
    this.currentTheme = nextTheme;
    this.notifyListeners();
  }

  private notifyListeners(): void {
    const snapshot: ThemeListener[] = this.listeners.slice();
    for (let i = 0; i < snapshot.length; i++) {
      snapshot[i](this.currentTheme);
    }
  }
}

export const themeManager: ThemeManager = ThemeManager.getInstance();
