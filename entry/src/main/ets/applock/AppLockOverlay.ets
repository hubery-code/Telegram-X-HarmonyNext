/**
 * entry 装配层 — 应用锁遮罩（APPLOCK-101）。
 *
 * 覆盖在当前页面之上的整屏层：只有 `AppLockGate` 说「要密码」时才出现。
 * 它刻意放在 entry 而不是 feature 里 —— 锁的是**整个应用**，不是某一页，
 * 而 entry 是唯一的路由/装配所有者（同 DEEPLINK-102 弹窗层的定位）。
 *
 * 键盘复用 `feature/settings` 的 `PasscodeKeypad`：设置页里创建/校验密码和这里解锁
 * 必须是同一套输入行为（四位自动提交、退格、吞掉多余输入），否则两侧会各自漂移。
 *
 * ## 冷却倒计时为什么由本组件驱动
 *
 * 锁态机不持有定时器（它不该决定谁来驱动，也不该在没人看的时候一直跑）。这里在进入
 * 冷却时挂一个 1 秒 tick，退出即清理；tick 只是提醒 gate「时间到了把阶段推回去」，
 * 归零判定仍在 `AppLockGate.tick()` 里用同一个时钟算。
 */

import { Theme, ThemeManager, ThemePreference } from '@tgx/core-design-system';
import { Lang, SupportedLanguage } from '@tgx/core-common';
import { PasscodeKeypad } from '@tgx/feature-settings';
import { AppLockGate, AppLockSnapshot } from './AppLockGate';
import { appLockGate } from './AppLockWiring';

const TICK_INTERVAL_MS: number = 1000;

@Component
export struct AppLockOverlay {
  @State private visible: boolean = false;
  @State private coolingSeconds: number = 0;
  @State private notice: string = '';
  @State private submitting: boolean = false;
  @State private effectiveTheme: Theme = ThemeManager.getInstance().getEffectiveTheme();
  @State private themePreference: ThemePreference = ThemeManager.getInstance().getPreference();
  @State private effectiveLang: SupportedLanguage = 'en';

  private gate: AppLockGate | null = null;
  private unsubscribe: (() => void) | null = null;
  private unsubscribeTheme: (() => void) | null = null;
  private unsubscribeLang: (() => void) | null = null;
  private ticker: number = -1;

  aboutToAppear(): void {
    this.gate = appLockGate();
    this.effectiveLang = Lang.getInstance().getLanguage();
    const self: AppLockOverlay = this;
    this.unsubscribeTheme = ThemeManager.getInstance().subscribe((theme: Theme): void => {
      self.effectiveTheme = theme;
      self.themePreference = ThemeManager.getInstance().getPreference();
    });
    this.unsubscribeLang = Lang.getInstance().subscribe((lang: SupportedLanguage): void => {
      self.effectiveLang = lang;
    });
    const gate: AppLockGate | null = this.gate;
    if (gate !== null) {
      this.applySnapshot(gate.snapshot());
      this.unsubscribe = gate.subscribe((snapshot: AppLockSnapshot): void => {
        self.applySnapshot(snapshot);
      });
    }
  }

  aboutToDisappear(): void {
    this.stopTicker();
    if (this.unsubscribe !== null) {
      this.unsubscribe();
      this.unsubscribe = null;
    }
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
    if (this.unsubscribeLang !== null) {
      this.unsubscribeLang();
      this.unsubscribeLang = null;
    }
  }

  private applySnapshot(snapshot: AppLockSnapshot): void {
    this.visible = snapshot.stage !== 'unlocked';
    this.coolingSeconds = snapshot.coolingDownSeconds;
    this.notice = snapshot.failureKey === null ? '' : this.t(snapshot.failureKey);
    if (this.coolingSeconds > 0) {
      this.startTicker();
    } else {
      this.stopTicker();
    }
  }

  private startTicker(): void {
    if (this.ticker >= 0) {
      return;
    }
    const self: AppLockOverlay = this;
    this.ticker = setInterval((): void => {
      const gate: AppLockGate | null = self.gate;
      if (gate !== null) {
        gate.tick();
      }
    }, TICK_INTERVAL_MS);
  }

  private stopTicker(): void {
    if (this.ticker >= 0) {
      clearInterval(this.ticker);
      this.ticker = -1;
    }
  }

  private t(key: string, ...args: (string | number)[]): string {
    return Lang.getInstance().formatByKey(key, this.effectiveLang, args);
  }

  private getTheme(): Theme {
    return this.effectiveTheme;
  }

  private promptText(): string {
    if (this.coolingSeconds > 0) {
      return this.t('Too many attempts. Try again in {0}s', this.coolingSeconds);
    }
    return this.t('Enter your passcode');
  }

  private onSubmit(pin: string): void {
    const gate: AppLockGate | null = this.gate;
    if (gate === null || this.submitting) {
      return;
    }
    const self: AppLockOverlay = this;
    this.submitting = true;
    gate.submit(pin).then((): void => {
      self.submitting = false;
    });
  }

  build() {
    if (this.visible) {
      Column() {
        PasscodeKeypad({
          prompt: this.promptText(),
          notice: this.notice,
          themeMode: this.themePreference,
          busy: this.submitting,
          reveal: this.gate !== null && this.gate.passcodeVisible(),
          cancellable: false,
          onSubmit: (pin: string): void => {
            this.onSubmit(pin);
          },
          onCancel: (): void => {}
        })
      }
      .id('app-lock-overlay')
      .width('100%')
      .height('100%')
      .backgroundColor(this.getTheme().colors.background)
    }
  }
}
