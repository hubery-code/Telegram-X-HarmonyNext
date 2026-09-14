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
 * Pure function: resolve effective Theme instance from preference, system mode, and optional font scale.
 */
export function resolveTheme(
  preference: ThemePreference,
  systemMode: ThemeMode = 'light',
  fontScale: number = 1.0
): Theme {
  const mode: ThemeMode = resolveThemeMode(preference, systemMode);
  if (fontScale === 1.0) {
    return mode === 'dark' ? DarkTheme : LightTheme;
  }
  return createTheme(mode, fontScale);
}

export class ThemeManager {
  private static instance: ThemeManager | null = null;

  private preference: ThemePreference = 'system';
  private systemMode: ThemeMode = 'light';
  private fontScale: number = 1.0;
  private currentTheme: Theme = LightTheme;
  private readonly listeners: ThemeListener[] = [];

  constructor(
    initialPreference: ThemePreference = 'system',
    initialSystemMode: ThemeMode = 'light',
    initialFontScale: number = 1.0
  ) {
    this.preference = initialPreference;
    this.systemMode = initialSystemMode;
    this.fontScale = initialFontScale;
    this.currentTheme = resolveTheme(this.preference, this.systemMode, this.fontScale);
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
      this.fontScale
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
    this.listeners.length = 0;
    this.currentTheme = resolveTheme('system', 'light', 1.0);
  }

  private updateEffectiveTheme(): void {
    const nextTheme: Theme = resolveTheme(this.preference, this.systemMode, this.fontScale);
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
