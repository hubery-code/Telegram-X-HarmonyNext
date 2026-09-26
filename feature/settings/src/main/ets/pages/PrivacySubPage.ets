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
 * feature/settings — 「隐私和安全」子页（SELF-102 / FEAT-SET-001 隐私分区）。
 *
 * 对齐 Telegram X 的 Privacy 页：一行一个设置项，右侧显示当前可见范围。
 * 例外名单编辑器（谁总是允许 / 谁从不允许）属于未拆包范围，故这里点行即在
 * 「所有人 → 我的联系人 → 没有人」之间循环；带例外名单的项显示为「自定义」
 * 且不会被静默改写成单条规则。
 */

import { Theme, ThemeManager, LightTheme } from '@tgx/core-design-system';
import { A11y, a11y, Lang, SupportedLanguage } from '@tgx/core-common';
import { SettingsUiState } from '../contract/SettingsUiState';
import {
  LoadPasscodeState,
  LoadPrivacySettings,
  OpenPasscodePage,
  SetErrorMessage,
  SettingsIntent,
  TogglePrivacySetting
} from '../contract/SettingsIntent';
import {
  PrivacyChoice,
  PrivacySettingItem,
  PrivacySettingKey,
  PRIVACY_SETTING_KEYS,
  privacyChoiceLabel,
  privacySettingLabel
} from '../model/PrivacySettings';

@Component
export struct PrivacySubPage {
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
    const self: PrivacySubPage = this;
    this.unsubscribeTheme = ThemeManager.getInstance().subscribe((_theme: Theme): void => {
      self.updateEffectiveTheme();
    });
    this.unsubscribeLang = Lang.getInstance().subscribe((lang: SupportedLanguage): void => {
      self.effectiveLang = lang;
    });
    this.onDispatch(new LoadPrivacySettings());
    // 「屏幕锁定」行的开/关文案要进页即真，不能等用户点进子页才回读。
    this.onDispatch(new LoadPasscodeState());
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

  /**
   * 必须在 builder 内部读 this.uiState：@Builder 的按值入参不参与状态观察，
   * 传成品的档位文案会导致点完一行文字不变（SET-106 同一条坑）。
   */
  private choiceOf(key: PrivacySettingKey): PrivacyChoice {
    const items: readonly PrivacySettingItem[] = this.uiState.privacyItems;
    for (let i = 0; i < items.length; i++) {
      if (items[i].key === key) {
        return items[i].choice;
      }
    }
    return 'unknown';
  }

  private isRowBusy(key: PrivacySettingKey): boolean {
    return this.uiState.updatingPrivacyKey === key;
  }

  build() {
    Column() {
      this.HeaderView()

      Scroll() {
        Column() {
          if (this.uiState.errorMessage !== null) {
            this.ErrorBannerView()
          }

          if (this.uiState.isLoadingPrivacy && this.uiState.privacyItems.length === 0) {
            this.LoadingRowView()
          } else {
            this.PrivacyCardView()
            this.ScreenLockCardView()
            this.HintView()
          }
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

      Text(this.t('Privacy & Security'))
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
  ErrorBannerView() {
    Row() {
      Text(this.uiState.errorMessage !== null ? this.uiState.errorMessage : '')
        .fontSize(this.getTheme().typography.footnote.fontSize)
        .fontColor(this.getTheme().colors.destructive)
        .layoutWeight(1)

      Button(this.t('Dismiss'))
        .fontSize(this.getTheme().typography.caption.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .backgroundColor(this.getTheme().colors.surface)
        .height(28)
        .onClick((): void => {
          this.onDispatch(new SetErrorMessage(null));
        })
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .margin({ bottom: this.getTheme().spacing.md })
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
  }

  @Builder
  LoadingRowView() {
    Row() {
      LoadingProgress()
        .width(24)
        .height(24)
        .color(this.getTheme().colors.accent)
        .margin({ right: this.getTheme().spacing.sm })

      Text(this.t('Loading...'))
        .fontSize(this.getTheme().typography.subheadline.fontSize)
        .fontColor(this.getTheme().colors.textSecondary)
    }
    .width('100%')
    .padding(this.getTheme().spacing.lg)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  PrivacyCardView() {
    Column() {
      ForEach(PRIVACY_SETTING_KEYS, (key: PrivacySettingKey, index: number) => {
        Column() {
          if (index > 0) {
            Divider()
              .color(this.getTheme().colors.divider)
              .margin({ top: this.getTheme().spacing.xs, bottom: this.getTheme().spacing.xs })
          }
          this.PrivacyRowView(key)
        }
        .width('100%')
      })
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
  PrivacyRowView(key: PrivacySettingKey) {
    Row() {
      Text(this.t(privacySettingLabel(key)))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)

      if (this.isRowBusy(key)) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.getTheme().colors.accent)
          .margin({ right: this.getTheme().spacing.sm })
      }

      Text(this.t(privacyChoiceLabel(this.choiceOf(key))))
        .fontSize(this.getTheme().typography.subheadline.fontSize)
        .fontColor(this.getTheme().colors.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.onDispatch(new TogglePrivacySetting(key));
    })
  }

  /**
   * 对标 Android 的「隐私和安全 → 屏幕锁定」入口（SettingsPrivacyController.java:111-112）：
   * 隐私页只负责把用户带进子页，PIN 的建/验/清全部在 PasscodeSubPage 里。
   */
  @Builder
  ScreenLockCardView() {
    Column() {
      Column() {
        Row() {
          Text(this.t('Screen Lock'))
            .fontSize(this.getTheme().typography.body.fontSize)
            .fontColor(this.getTheme().colors.textPrimary)
            .layoutWeight(1)

          Text(this.t(this.uiState.passcodeIsSet ? 'On' : 'Off'))
            .fontSize(this.getTheme().typography.subheadline.fontSize)
            .fontColor(this.getTheme().colors.textSecondary)
        }
        .width('100%')
        .height(52)
        .alignItems(VerticalAlign.Center)
        .id('privacy-screen-lock-row')
        .onClick((): void => {
          this.onDispatch(new OpenPasscodePage());
        })
      }
      .width('100%')
      .padding({
        left: this.getTheme().spacing.md,
        right: this.getTheme().spacing.md
      })
    }
    .width('100%')
    .padding({
      top: this.getTheme().spacing.xs,
      bottom: this.getTheme().spacing.xs
    })
    .margin({ top: this.getTheme().spacing.md })
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
  }

  @Builder
  HintView() {
    Text(this.t('Tap a row to change who can see it.'))
      .fontSize(this.getTheme().typography.footnote.fontSize)
      .fontColor(this.getTheme().colors.textSecondary)
      .margin({
        top: this.getTheme().spacing.sm,
        left: this.getTheme().spacing.xs,
        right: this.getTheme().spacing.xs
      })
      .width('100%')
  }
}
