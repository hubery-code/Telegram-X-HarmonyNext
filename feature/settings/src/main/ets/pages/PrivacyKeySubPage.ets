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
 * feature/settings — 单个隐私项的详情页（PRIVACY-101）。
 *
 * 端口自 Android `SettingsPrivacyKeyController`：主档位单选（+「我的联系人」档下的 Premium
 * 勾）+「总是允许 / 从不允许」两份例外名单 + 一句脚注。
 *
 * 两条与旧列表页相反的规矩：
 * 1. **页内编辑不写服务器**。全部改动只落在 `uiState.privacyDetail.rules` 上，离开本页那一次
 *    才 `setUserPrivacySettingRules`（Android `onBlur → saveChanges`，没改就不发）。
 *    旧版每点一行立刻写回单条规则，会把例外名单抹掉。
 * 2. **例外行按位置判定是否存在**（`privacyNeedAlwaysAllow`），不是按「有没有人」，
 *    所以「所有人」档下只剩「从不允许」一行是正确结果，不是渲染漏了。
 *
 * 选择器是多选面板而不是页面：Android 那边压的是 `ContactsController`，本端为了不引入
 * 路由层级，用同一页上的覆盖层表达，勾选集合存在 `pickedUserIds`，点「完成」才并回规则。
 */

import { Theme, ThemeManager, LightTheme } from '@tgx/core-design-system';
import { A11y, a11y, Lang, SupportedLanguage } from '@tgx/core-common';
import { SettingsUiState } from '../contract/SettingsUiState';
import {
  ApplyPrivacyPicker,
  ClosePrivacyKeyPage,
  ClosePrivacyPicker,
  OpenPrivacyPicker,
  SetErrorMessage,
  SetPrivacyMode,
  SettingsIntent,
  TogglePrivacyPickerContact,
  TogglePrivacyPremium
} from '../contract/SettingsIntent';
import { PrivacySettingKey, privacySettingLabel } from '../model/PrivacySettings';
import {
  parsePrivacyRules,
  PrivacyMode,
  privacyModeLabel,
  PrivacyRulesView
} from '../model/PrivacyRules';
import {
  PrivacyContactRow,
  PrivacyDetailState,
  PrivacyExceptionsView,
  privacyExceptionsView
} from '../model/PrivacyDetail';

/** 主档位的展示顺序（Android 同样是「所有人 → 我的联系人 → 没有人」）。 */
const PRIVACY_MODES: PrivacyMode[] = ['everybody', 'contacts', 'nobody'];

@Component
export struct PrivacyKeySubPage {
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
    const self: PrivacyKeySubPage = this;
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

  /**
   * 以下取数全部走方法而不是 @Builder 入参：按值传进 @Builder 的结果不参与状态观察，
   * 点完档位文字会停在旧值（SET-106 / PROXY-102 同一条坑）。
   */
  private detail(): PrivacyDetailState | null {
    return this.uiState.privacyDetail;
  }

  private viewOf(): PrivacyRulesView | null {
    const detail: PrivacyDetailState | null = this.detail();
    if (detail === null) {
      return null;
    }
    return parsePrivacyRules(detail.rules);
  }

  private isModeSelected(mode: PrivacyMode): boolean {
    const view: PrivacyRulesView | null = this.viewOf();
    return view !== null && view.mode === mode;
  }

  private isPremiumOn(): boolean {
    const view: PrivacyRulesView | null = this.viewOf();
    return view !== null && view.plusPremium;
  }

  /**
   * 例外行的取数方法。为什么是一堆小方法而不是把 `PrivacyExceptionsView` 传进 @Builder：
   * 按值传进 @Builder 的结果不参与状态观察，点完档位后行数会停在旧值（SET-106 同一条坑）。
   * detail 为空时回一个「两行都不显示」的空视图：调用点都在 `detail() !== null` 分支里，
   * 回空对象只是为了让类型不用到处判 null。
   */
  private exceptionsOf(): PrivacyExceptionsView {
    const detail: PrivacyDetailState | null = this.detail();
    if (detail === null) {
      return new PrivacyExceptionsView([], [], 0, 0, false, false);
    }
    return privacyExceptionsView(detail.rules, detail.contacts);
  }

  private showAlwaysRow(): boolean {
    return this.exceptionsOf().showAlwaysRow;
  }

  private showNeverRow(): boolean {
    return this.exceptionsOf().showNeverRow;
  }

  /** 例外行的人数文案：照 Android `Lang.plural(xUsers)` / `PrivacyAddUsers`。 */
  private exceptionValue(isAlways: boolean): string {
    const view: PrivacyExceptionsView = this.exceptionsOf();
    const total: number = isAlways
      ? view.alwaysRows.length + view.alwaysChatMemberCount
      : view.neverRows.length + view.neverChatMemberCount;
    if (total === 0) {
      return this.t('Add Users');
    }
    return this.t(total === 1 ? '{0} User' : '{0} Users', total);
  }

  private pickerTitle(): string {
    const detail: PrivacyDetailState | null = this.detail();
    if (detail !== null && detail.pickerTarget === 'never') {
      return this.t('Never Share With');
    }
    return this.t('Always Share With');
  }

  /** 分支判定统一收在方法里：build 里不写 `detail()!.x`，ArkTS 禁止非空断言。 */
  private isDetailView(): boolean {
    return this.detail() !== null;
  }

  private isLoading(): boolean {
    const detail: PrivacyDetailState | null = this.detail();
    return detail !== null && detail.loading;
  }

  private hasDetailError(): boolean {
    const detail: PrivacyDetailState | null = this.detail();
    return detail !== null && detail.errorMessage !== null;
  }

  private isPickerOpen(): boolean {
    const detail: PrivacyDetailState | null = this.detail();
    return detail !== null && detail.pickerTarget !== null;
  }

  build() {
    Stack() {
      Column() {
        this.HeaderView()

        Scroll() {
          Column() {
            if (!this.isDetailView()) {
              this.LoadingRowView()
            } else if (this.isLoading()) {
              this.LoadingRowView()
            } else if (this.hasDetailError()) {
              this.DetailErrorView()
            } else {
              this.ModeCardView()
              this.ExceptionsView()
              this.FootnoteView()
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

      if (this.isPickerOpen()) {
        this.PickerOverlayView()
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

      Text(this.headerTitle())
        .fontSize(this.getTheme().typography.largeTitle.fontSize)
        .fontWeight(this.getTheme().typography.largeTitle.fontWeight)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
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

  private headerTitle(): string {
    const detail: PrivacyDetailState | null = this.detail();
    return detail === null ? '' : this.t(privacySettingLabel(detail.key));
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

  /** 详情页自己的错误态：只说这一项没读到，列表页的那条横幅不在这里重复。 */
  @Builder
  DetailErrorView() {
    Column() {
      Text(this.detailErrorText())
        .fontSize(this.getTheme().typography.footnote.fontSize)
        .fontColor(this.getTheme().colors.destructive)
        .width('100%')

      Button(this.t('Dismiss'))
        .fontSize(this.getTheme().typography.caption.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .backgroundColor(this.getTheme().colors.surface)
        .height(32)
        .margin({ top: this.getTheme().spacing.sm })
        .onClick((): void => {
          this.onDispatch(new SetErrorMessage(null));
        })
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .margin({ top: this.getTheme().spacing.md })
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
    .alignItems(HorizontalAlign.Start)
  }

  private detailErrorText(): string {
    const detail: PrivacyDetailState | null = this.detail();
    return detail !== null && detail.errorMessage !== null ? detail.errorMessage : '';
  }

  @Builder
  ModeCardView() {
    Column() {
      ForEach(PRIVACY_MODES, (mode: PrivacyMode, index: number) => {
        Column() {
          if (index > 0) {
            Divider()
              .color(this.getTheme().colors.divider)
              .margin({ top: this.getTheme().spacing.xs, bottom: this.getTheme().spacing.xs })
          }
          // 圆点内联在每一项里：@Builder 的按值入参不参与状态观察，抽成 Radio(selected) 会点完不变。
          Row() {
            Stack() {
              if (this.isModeSelected(mode)) {
                Column()
                  .width(10)
                  .height(10)
                  .borderRadius(5)
                  .backgroundColor(this.getTheme().colors.accent)
              }
            }
            .width(22)
            .height(22)
            .margin({ right: this.getTheme().spacing.md })
            .borderRadius(11)
            .border({
              width: 2,
              color: this.isModeSelected(mode)
                ? this.getTheme().colors.accent
                : this.getTheme().colors.textSecondary
            })

            Text(this.t(privacyModeLabel(mode, this.isPremiumOn())))
              .fontSize(this.getTheme().typography.body.fontSize)
              .fontColor(this.getTheme().colors.textPrimary)
              .layoutWeight(1)
          }
          .width('100%')
          .height(52)
          .alignItems(VerticalAlign.Center)
          .id(`privacy-mode-${mode}`)
          .onClick((): void => {
            this.onDispatch(new SetPrivacyMode(mode));
          })

          // Premium 勾只在「我的联系人」档下出现并且可点（Android 同：其余档位它无意义）。
          if (mode === 'contacts' && this.isModeSelected('contacts')) {
            Row() {
              Stack() {
                if (this.isPremiumOn()) {
                  Image($r('app.media.ic_check_single'))
                    .width(14)
                    .height(14)
                    .fillColor(this.getTheme().colors.accent)
                }
              }
              .width(20)
              .height(20)
              .margin({ right: this.getTheme().spacing.md })
              .borderRadius(5)
              .border({
                width: 1.5,
                color: this.isPremiumOn()
                  ? this.getTheme().colors.accent
                  : this.getTheme().colors.textSecondary
              })

              Text(this.t('Premium Users'))
                .fontSize(this.getTheme().typography.subheadline.fontSize)
                .fontColor(this.getTheme().colors.textSecondary)
                .layoutWeight(1)
            }
            .width('100%')
            .height(44)
            .alignItems(VerticalAlign.Center)
            .padding({ left: this.getTheme().spacing.xxl })
            .id('privacy-premium-row')
            .onClick((): void => {
              this.onDispatch(new TogglePrivacyPremium());
            })
          }
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
    .margin({ top: this.getTheme().spacing.md })
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
  }

  /**
   * 例外名单两行。存在与否由规则列表的**位置**决定（`privacyNeedAlwaysAllow`），
   * 所以「所有人」档只剩「从不允许」一行是正确结果 —— 不是这里漏渲染。
   */
  @Builder
  ExceptionsView() {
    Column() {
      if (this.showAlwaysRow() || this.showNeverRow()) {
        Text(this.t('Add Exceptions'))
          .fontSize(this.getTheme().typography.caption.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .width('100%')
          .padding({
            left: this.getTheme().spacing.xs,
            bottom: this.getTheme().spacing.sm
          })
      }

      Column() {
        Column() {
          if (this.showAlwaysRow()) {
            Row() {
              Text(this.t('Always Allow'))
                .fontSize(this.getTheme().typography.body.fontSize)
                .fontColor(this.getTheme().colors.textPrimary)
                .layoutWeight(1)

              Text(this.exceptionValue(true))
                .fontSize(this.getTheme().typography.subheadline.fontSize)
                .fontColor(this.getTheme().colors.textSecondary)
            }
            .width('100%')
            .height(52)
            .alignItems(VerticalAlign.Center)
            .id('privacy-exception-always')
            .onClick((): void => {
              this.onDispatch(new OpenPrivacyPicker('always'));
            })
          }

          if (this.showAlwaysRow() && this.showNeverRow()) {
            Divider()
              .color(this.getTheme().colors.divider)
              .margin({ top: this.getTheme().spacing.xs, bottom: this.getTheme().spacing.xs })
          }

          if (this.showNeverRow()) {
            Row() {
              Text(this.t('Never Allow'))
                .fontSize(this.getTheme().typography.body.fontSize)
                .fontColor(this.getTheme().colors.textPrimary)
                .layoutWeight(1)

              Text(this.exceptionValue(false))
                .fontSize(this.getTheme().typography.subheadline.fontSize)
                .fontColor(this.getTheme().colors.textSecondary)
            }
            .width('100%')
            .height(52)
            .alignItems(VerticalAlign.Center)
            .id('privacy-exception-never')
            .onClick((): void => {
              this.onDispatch(new OpenPrivacyPicker('never'));
            })
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
      .width('100%')
    }
    .width('100%')
    .margin({ top: this.getTheme().spacing.lg })
  }

  @Builder
  FootnoteView() {
    Text(this.t('Custom Share Settings Help'))
      .fontSize(this.getTheme().typography.footnote.fontSize)
      .fontColor(this.getTheme().colors.textSecondary)
      .margin({
        top: this.getTheme().spacing.sm,
        left: this.getTheme().spacing.xs,
        right: this.getTheme().spacing.xs
      })
      .width('100%')
  }

  @Builder
  PickerOverlayView() {
    Column() {
      Row() {
        Button(this.t('Cancel'))
          .fontSize(this.getTheme().typography.subheadline.fontSize)
          .fontColor(this.getTheme().colors.accent)
          .backgroundColor(Color.Transparent)
          .height(36)
          .onClick((): void => {
            this.onDispatch(new ClosePrivacyPicker());
          })

        Text(this.pickerTitle())
          .fontSize(this.getTheme().typography.title.fontSize)
          .fontWeight(this.getTheme().typography.title.fontWeight)
          .fontColor(this.getTheme().colors.textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button(this.t('Done'))
          .fontSize(this.getTheme().typography.subheadline.fontSize)
          .fontColor(this.getTheme().colors.accent)
          .backgroundColor(Color.Transparent)
          .height(36)
          .id('privacy-picker-done')
          .onClick((): void => {
            this.onDispatch(new ApplyPrivacyPicker());
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: this.getTheme().spacing.sm,
        right: this.getTheme().spacing.sm,
        top: this.getTheme().spacing.lg,
        bottom: this.getTheme().spacing.sm
      })

      if (this.pickerRows().length === 0) {
        Text(this.t('No Contacts Yet'))
          .fontSize(this.getTheme().typography.subheadline.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(this.getTheme().spacing.xxl)
      }

      List({ space: 0 }) {
        ForEach(this.pickerRows(), (row: PrivacyContactRow) => {
          ListItem() {
            Row() {
              Stack() {
                if (row.selected) {
                  Image($r('app.media.ic_check_single'))
                    .width(14)
                    .height(14)
                    .fillColor(this.getTheme().colors.accent)
                }
              }
              .width(20)
              .height(20)
              .margin({ right: this.getTheme().spacing.md })
              .borderRadius(5)
              .border({
                width: 1.5,
                color: row.selected
                  ? this.getTheme().colors.accent
                  : this.getTheme().colors.textSecondary
              })

              Text(row.title)
                .fontSize(this.getTheme().typography.body.fontSize)
                .fontColor(this.getTheme().colors.textPrimary)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .height(52)
            .alignItems(VerticalAlign.Center)
            .padding({ left: this.getTheme().spacing.md, right: this.getTheme().spacing.md })
            .id(`privacy-picker-${row.userId}`)
            .onClick((): void => {
              this.onDispatch(new TogglePrivacyPickerContact(row.userId));
            })
          }
        }, (row: PrivacyContactRow): string => `${row.userId}:${row.selected ? 1 : 0}`)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getTheme().colors.background)
  }

  private pickerRows(): PrivacyContactRow[] {
    const detail: PrivacyDetailState | null = this.detail();
    return detail === null ? [] : detail.contacts;
  }
}
