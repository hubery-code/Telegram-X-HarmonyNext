/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * feature/settings — 「屏幕锁定」子页（APPLOCK-101）。
 *
 * 对标 Telegram X：入口在 Privacy 页（`SettingsPrivacyController.java:111-112` →
 * `TdlibUi.openPasscodeSetup`），页面三行 —— 开关、自动锁定档、修改密码。
 * 本端把入口放在自己的「隐私和安全」子页里，行样式沿用同一套卡片。
 *
 * 键盘不在本页实现，而是 `PasscodeKeypad` 覆盖层：流程走到哪一步由
 * `uiState.passcodeFlow` 决定（判据在 reducer），本页只负责把阶段翻成文案。
 * 这样锁屏遮罩（entry）能复用同一个键盘组件，而不必先打开设置页。
 */

import { Theme, ThemeManager, LightTheme } from '@tgx/core-design-system';
import { A11y, a11y, Lang, SupportedLanguage } from '@tgx/core-common';
import {
  APP_LOCK_ERROR_CORRUPT,
  APP_LOCK_ERROR_STORE,
  APP_LOCK_ERROR_WRONG,
  APP_LOCK_NOTICE_INVALID,
  APP_LOCK_NOTICE_MISMATCH,
  APP_LOCK_NOTICE_REMOVED,
  APP_LOCK_NOTICE_SAVED,
  AutoLockChoice,
  autoLockLabelKey,
  passcodeStagePrompt
} from '@tgx/core-domain';
import { SettingsUiState } from '../contract/SettingsUiState';
import {
  CancelPasscodeFlow,
  ChangePasscodeRequested,
  CycleAutoLockChoice,
  PasscodeSubmitted,
  SettingsIntent,
  TogglePasscodeRequested
} from '../contract/SettingsIntent';
import { PasscodeKeypad } from './PasscodeKeypad';

/** 提示/报错文案表：Lang key 全部来自 core/domain 常量，避免两处拼写漂移。 */
const NOTICE_KEYS: string[] = [
  APP_LOCK_NOTICE_INVALID,
  APP_LOCK_NOTICE_MISMATCH,
  APP_LOCK_NOTICE_SAVED,
  APP_LOCK_NOTICE_REMOVED,
  APP_LOCK_ERROR_WRONG,
  APP_LOCK_ERROR_STORE,
  APP_LOCK_ERROR_CORRUPT
];

@Component
export struct PasscodeSubPage {
  @Prop @Watch('onUiStateChanged') uiState: SettingsUiState = SettingsUiState.initial();
  onDispatch: (intent: SettingsIntent) => void = (): void => {};
  onBack: () => void = (): void => {};

  @State private effectiveTheme: Theme = LightTheme;
  @State private effectiveLang: SupportedLanguage = 'en';

  private unsubscribeTheme: (() => void) | null = null;
  private unsubscribeLang: (() => void) | null = null;

  aboutToAppear(): void {
    this.updateEffectiveTheme();
    this.effectiveLang = Lang.getInstance().getLanguage();
    const self: PasscodeSubPage = this;
    this.unsubscribeTheme = ThemeManager.getInstance().subscribe((_theme: Theme): void => {
      self.updateEffectiveTheme();
    });
    this.unsubscribeLang = Lang.getInstance().subscribe((lang: SupportedLanguage): void => {
      self.effectiveLang = lang;
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
    if (this.unsubscribeLang !== null) {
      this.unsubscribeLang();
      this.unsubscribeLang = null;
    }
  }

  onUiStateChanged(): void {
    this.updateEffectiveTheme();
    this.effectiveLang = Lang.getInstance().getLanguage();
  }

  private updateEffectiveTheme(): void {
    this.effectiveTheme = ThemeManager.getInstance().resolveTheme(this.uiState.themeMode);
  }

  private getTheme(): Theme {
    return this.effectiveTheme;
  }

  private t(key: string, ...args: (string | number)[]): string {
    const langCode: SupportedLanguage =
      this.uiState.languageCode === 'zh' || this.effectiveLang === 'zh' ? 'zh' : 'en';
    return Lang.getInstance().formatByKey(key, langCode, args);
  }

  private noticeText(): string {
    const notice: string | null = this.uiState.passcodeNotice;
    if (notice === null || NOTICE_KEYS.indexOf(notice) < 0) {
      return '';
    }
    return this.t(notice);
  }

  build() {
    Stack() {
      Column() {
        this.HeaderView()

        Scroll() {
          Column() {
            this.PasscodeCardView()
            this.HintView()
          }
          .width('100%')
          .padding({
            left: this.getTheme().spacing.screenInset,
            right: this.getTheme().spacing.screenInset,
            bottom: this.getTheme().spacing.xxl
          })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getTheme().colors.background)

      if (this.uiState.passcodeFlow !== 'idle') {
        PasscodeKeypad({
          prompt: this.t(passcodeStagePrompt(this.uiState.passcodeFlow)),
          notice: this.noticeText(),
          themeMode: this.uiState.themeMode,
          busy: this.uiState.isUpdatingPasscode,
          cancellable: true,
          onSubmit: (pin: string): void => {
            this.onDispatch(new PasscodeSubmitted(pin));
          },
          onCancel: (): void => {
            this.onDispatch(new CancelPasscodeFlow());
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  HeaderView() {
    Row() {
      Image($r('app.media.ic_back'))
        .width(24)
        .height(24)
        .fillColor(this.getTheme().colors.accent)
        .margin({ right: this.getTheme().spacing.md })
      .accessibilityText(a11y(A11y.BACK))
        .onClick((): void => {
          this.onBack();
        })

      Text(this.t('Screen Lock'))
        .fontSize(this.getTheme().typography.largeTitle.fontSize)
        .fontWeight(this.getTheme().typography.largeTitle.fontWeight)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.getTheme().spacing.screenInset,
      right: this.getTheme().spacing.screenInset,
      top: this.getTheme().spacing.lg,
      bottom: this.getTheme().spacing.md
    })
  }

  @Builder
  PasscodeCardView() {
    Column() {
      this.ToggleRowView()

      Divider()
        .color(this.getTheme().colors.divider)
        .margin({ top: this.getTheme().spacing.xs, bottom: this.getTheme().spacing.xs })

      this.AutoLockRowView()

      if (this.uiState.passcodeIsSet) {
        Divider()
          .color(this.getTheme().colors.divider)
          .margin({ top: this.getTheme().spacing.xs, bottom: this.getTheme().spacing.xs })

        this.ChangeRowView()
      }
    }
    .width('100%')
    .padding({
      left: this.getTheme().spacing.md,
      right: this.getTheme().spacing.md,
      top: this.getTheme().spacing.xs,
      bottom: this.getTheme().spacing.xs
    })
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
  }

  @Builder
  ToggleRowView() {
    Row() {
      Text(this.t('Screen Lock'))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)

      this.BusyIndicator()

      Text(this.uiState.passcodeIsSet ? this.t('On') : this.t('Off'))
        .fontSize(this.getTheme().typography.subheadline.fontSize)
        .fontColor(this.getTheme().colors.textSecondary)
        .id('passcode-toggle-state')
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.onDispatch(new TogglePasscodeRequested());
    })
  }

  @Builder
  AutoLockRowView() {
    Row() {
      Text(this.t('Auto-Lock'))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)

      Text(this.autoLockLabel(this.uiState.autoLockChoice))
        .fontSize(this.getTheme().typography.subheadline.fontSize)
        .fontColor(this.getTheme().colors.textSecondary)
        .id('passcode-autolock-state')
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.onDispatch(new CycleAutoLockChoice());
    })
  }

  @Builder
  ChangeRowView() {
    Row() {
      Text(this.t('Change Passcode'))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.onDispatch(new ChangePasscodeRequested());
    })
  }

  @Builder
  BusyIndicator() {
    if (this.uiState.isUpdatingPasscode) {
      LoadingProgress()
        .width(18)
        .height(18)
        .color(this.getTheme().colors.accent)
        .margin({ right: this.getTheme().spacing.sm })
    }
  }

  @Builder
  HintView() {
    Column() {
      Text(this.noticeText())
        .fontSize(this.getTheme().typography.footnote.fontSize)
        .fontColor(this.getTheme().colors.destructive)
        .width('100%')
        .id('passcode-inline-notice')

      Text(this.t('The passcode is stored in this device secure storage and never synced.'))
        .fontSize(this.getTheme().typography.footnote.fontSize)
        .fontColor(this.getTheme().colors.textSecondary)
        .margin({ top: this.getTheme().spacing.sm })
        .width('100%')
    }
    .width('100%')
    .margin({
      top: this.getTheme().spacing.sm,
      left: this.getTheme().spacing.xs,
      right: this.getTheme().spacing.xs
    })
  }

  /**
   * 必须在 builder 内现取：`@Builder` 的按值入参不参与状态观察，
   * 把翻译好的档位文字传进去会导致点一行循环档位而文字不变（SET-106 同一条坑）。
   */
  private autoLockLabel(choice: AutoLockChoice): string {
    return this.t(autoLockLabelKey(choice));
  }
}
