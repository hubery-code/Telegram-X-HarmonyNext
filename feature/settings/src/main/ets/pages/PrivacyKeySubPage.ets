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
 * 端口自 Android `SettingsPrivacyKeyController`：主档位单选 +「总是允许 / 从不允许」两份
 * 例外名单 + 一句脚注，最后是一张「附加开关」卡（PRIVACY-103：只有「群组与频道邀请」给
 * Premium 开关、只有「最后上线时间」给「隐藏已读时间」开关）。
 *
 * 两条与旧列表页相反的规矩：
 * 1. **页内编辑不写服务器**。全部改动只落在 `uiState.privacyDetail.rules` 上，离开本页那一次
 *    才 `setUserPrivacySettingRules`（Android `onBlur → saveChanges`，没改就不发）。
 *    旧版每点一行立刻写回单条规则，会把例外名单抹掉。
 * 2. **例外行按位置判定是否存在**（`privacyNeedAlwaysAllow`），不是按「有没有人」，
 *    所以「所有人」档下只剩「从不允许」一行是正确结果，不是渲染漏了。
 *
 * 选择器是多选面板而不是页面：Android 那边压的是 `ContactsController`，本端为了不引入
 * 路由层级，用同一页上的覆盖层表达。面板分「我的联系人 / 群聊」两个分区（PRIVACY-102），
 * 勾选集合分别是 `pickedUserIds` 与 `pickedChatIds`，点「完成」才并回规则列表。
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
  TogglePrivacyHideReadTime,
  TogglePrivacyPickerChat,
  TogglePrivacyPickerContact,
  TogglePrivacyPremium
} from '../contract/SettingsIntent';
import {
  PrivacySettingKey,
  privacyAlwaysAllowLabel,
  privacyNeedNobodyOption,
  privacyNeedExceptions,
  privacyNeverAllowLabel,
  privacyNeedsPremiumRow,
  privacyNeedsReadDateRow,
  privacySettingLabel
} from '../model/PrivacySettings';
import {
  parsePrivacyRules,
  PrivacyMode,
  privacyModeLabel,
  privacyNeedsHideReadTime,
  PrivacyRulesView
} from '../model/PrivacyRules';
import {
  PrivacyChatRow,
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
   * 附加开关行（PRIVACY-103）的可见性，逐条照 Android `needExtraToggle()`：
   * Premium 行只有「群组与频道邀请」有，且「所有人」档下不出（那时谁都进得来，勾了没意义）；
   * 「隐藏已读时间」只有「最后上线时间」有，且档位是「所有人」但排除了具体的人/会话时仍要出。
   */
  private premiumRowShown(): boolean {
    const detail: PrivacyDetailState | null = this.detail();
    if (detail === null || !privacyNeedsPremiumRow(detail.key)) {
      return false;
    }
    const view: PrivacyRulesView | null = this.viewOf();
    return view !== null && view.mode !== 'everybody';
  }

  private readDateRowShown(): boolean {
    const detail: PrivacyDetailState | null = this.detail();
    if (detail === null || !privacyNeedsReadDateRow(detail.key)) {
      return false;
    }
    const view: PrivacyRulesView | null = this.viewOf();
    return view !== null && privacyNeedsHideReadTime(view);
  }

  private hasExtraToggle(): boolean {
    return this.premiumRowShown() || this.readDateRowShown();
  }

  /** 界面是「隐藏」，TDLib 字段是 `show_read_date`，方向相反。 */
  private isHideReadTimeOn(): boolean {
    const detail: PrivacyDetailState | null = this.detail();
    return detail !== null && detail.showReadDate !== null && !detail.showReadDate;
  }

  /** 还没读到 read-date 设置 = 这一行画成关闭且不可点（Android `setRadioEnabled(readDatePrivacySetting != null && …)`）。 */
  private isReadDateRowEnabled(): boolean {
    const detail: PrivacyDetailState | null = this.detail();
    return detail !== null && detail.showReadDate !== null;
  }

  private extraToggleDescription(): string {
    return this.premiumRowShown() ? 'Allow Premium Invite Desc' : 'Hide Read Time Desc';
  }

  /**
   * 例外行的取数方法。为什么是一堆小方法而不是把 `PrivacyExceptionsView` 传进 @Builder：
   * 按值传进 @Builder 的结果不参与状态观察，点完档位后行数会停在旧值（SET-106 同一条坑）。
   * detail 为空、或这一项根本没有例外（`allow_find_by_phone`，Android `needExceptions()`）时，
   * 回一个「两行都不显示」的空视图：调用点都在 `detail() !== null` 分支里，
   * 回空对象只是为了让类型不用到处判 null。
   */
  private exceptionsOf(): PrivacyExceptionsView {
    const detail: PrivacyDetailState | null = this.detail();
    if (detail === null || !privacyNeedExceptions(detail.key)) {
      return new PrivacyExceptionsView(0, 0, false, false);
    }
    return privacyExceptionsView(detail.rules, detail.chats);
  }

  private showAlwaysRow(): boolean {
    return this.exceptionsOf().showAlwaysRow;
  }

  private showNeverRow(): boolean {
    return this.exceptionsOf().showNeverRow;
  }

  /**
   * 这一项到底有没有例外名单（Android `needExceptions()`）。没有的话整块卡片不渲染：
   * 留一张空卡等于在界面上承诺一个不可编辑的功能。
   */
  private hasExceptions(): boolean {
    return this.showAlwaysRow() || this.showNeverRow();
  }

  /**
   * 例外行的标题：只有「最后上线时间」这一项在 Android 上读作「分享给谁」
   * （`SettingsPrivacyKeyController:494-517`），其余项是「允许谁」。
   */
  private alwaysLabel(): string {
    const detail: PrivacyDetailState | null = this.detail();
    return detail === null ? 'Always Allow' : privacyAlwaysAllowLabel(detail.key);
  }

  private neverLabel(): string {
    const detail: PrivacyDetailState | null = this.detail();
    return detail === null ? 'Never Allow' : privacyNeverAllowLabel(detail.key);
  }

  /**
   * 档位单选的行：「没有人」按这一项是否存在而定（Android `needNobodyOption()` ——
   * 「通过手机号发现我」只有「所有人 / 我的联系人」两档，禁止它是无意义的）。
   */
  private modeRows(): PrivacyMode[] {
    const detail: PrivacyDetailState | null = this.detail();
    if (detail !== null && privacyNeedNobodyOption(detail.key)) {
      return PRIVACY_MODES;
    }
    const rows: PrivacyMode[] = [];
    for (let i = 0; i < PRIVACY_MODES.length; i++) {
      if (PRIVACY_MODES[i] !== 'nobody') {
        rows.push(PRIVACY_MODES[i]);
      }
    }
    return rows;
  }

  /** 例外行的人数文案：照 Android `Lang.plural(xUsers)` / `PrivacyAddUsers`。 */
  private exceptionValue(isAlways: boolean): string {
    const view: PrivacyExceptionsView = this.exceptionsOf();
    // 人数含会话的**成员数**，不是会话条数（Android `getPlusTotalCount`）。
    const total: number = isAlways ? view.alwaysCount : view.neverCount;
    if (total === 0) {
      return this.t('Add Users');
    }
    return this.t(total === 1 ? '{0} User' : '{0} Users', total);
  }

  /**
   * 面板标题沿用打开它的那一行的标题：Android 是同一个字符串推进去的。
   * 之前写死「…Share With」，结果「 Bio」页面上行读「Never Allow」、点进去标题读「Never Share With」。
   */
  private pickerTitle(): string {
    const detail: PrivacyDetailState | null = this.detail();
    if (detail !== null && detail.pickerTarget === 'never') {
      return this.t(this.neverLabel());
    }
    return this.t(this.alwaysLabel());
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
              if (this.hasExceptions()) {
                this.ExceptionsView()
              }
              this.FootnoteView()
              if (this.hasExtraToggle()) {
                this.ExtraToggleView()
              }
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
      ForEach(this.modeRows(), (mode: PrivacyMode, index: number) => {
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
   * 例外名单两行（仅在 `hasExceptions()` 为真时由 build 调进来）。存在与否由规则列表的
   * **位置**决定（`privacyNeedAlwaysAllow`），所以「所有人」档只剩「从不允许」一行是正确结果 ——
   * 不是这里漏渲染。人数含会话成员数，见 `exceptionValue`。
   */
  @Builder
  ExceptionsView() {
    Column() {
      if (this.hasExceptions()) {
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
              Text(this.t(this.alwaysLabel()))
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
              Text(this.t(this.neverLabel()))
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

  /**
   * 附加开关卡（PRIVACY-103）：Android 在例外名单之后另起一张卡 + 一段自己的脚注
   * （`newExtraToggleItems`），所以 Premium 行不在档位卡里。「隐藏已读时间」这一行
   * 在没读到服务端值之前画成关闭且不可点。
   */
  @Builder
  ExtraToggleView() {
    Column() {
      Column() {
        if (this.premiumRowShown()) {
          Row() {
            Text(this.t('Telegram Premium subscribers'))
              .fontSize(this.getTheme().typography.body.fontSize)
              .fontColor(this.getTheme().colors.textPrimary)
              .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.isPremiumOn() })
              .onChange((isOn: boolean): void => {
                if (isOn !== this.isPremiumOn()) {
                  this.onDispatch(new TogglePrivacyPremium());
                }
              })
          }
          .width('100%')
          .height(52)
          .alignItems(VerticalAlign.Center)
          .id('privacy-premium-row')
        }

        if (this.readDateRowShown()) {
          Row() {
            Text(this.t('Hide Read Time'))
              .fontSize(this.getTheme().typography.body.fontSize)
              .fontColor(this.getTheme().colors.textPrimary)
              .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.isHideReadTimeOn() })
              .enabled(this.isReadDateRowEnabled())
              .onChange((isOn: boolean): void => {
                if (isOn !== this.isHideReadTimeOn()) {
                  this.onDispatch(new TogglePrivacyHideReadTime());
                }
              })
          }
          .width('100%')
          .height(52)
          .alignItems(VerticalAlign.Center)
          .id('privacy-read-date-row')
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

      Text(this.t(this.extraToggleDescription()))
        .fontSize(this.getTheme().typography.footnote.fontSize)
        .fontColor(this.getTheme().colors.textSecondary)
        .margin({
          top: this.getTheme().spacing.sm,
          left: this.getTheme().spacing.xs,
          right: this.getTheme().spacing.xs
        })
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

      if (this.pickerIsEmpty()) {
        Text(this.t('No Contacts Yet'))
          .fontSize(this.getTheme().typography.subheadline.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(this.getTheme().spacing.xxl)
      }

      List({ space: 0 }) {
        // 两个分区：Android 压的是 ContactsController，它本身就有「我的联系人 / 群聊」
        // 两段；例外名单允许填会话，所以只有联系人一段是功能缺失，不是简化。
        if (this.pickerContacts().length > 0) {
          ListItemGroup({ header: this.PickerSectionHeaderView('contacts', 'My Contacts') }) {
            ForEach(this.pickerContacts(), (row: PrivacyContactRow) => {
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
            }, (row: PrivacyContactRow): string => `u${row.userId}:${row.selected ? 1 : 0}`)
          }
        }

        if (this.pickerChats().length > 0) {
          ListItemGroup({ header: this.PickerSectionHeaderView('chats', 'Group Chats') }) {
            ForEach(this.pickerChats(), (row: PrivacyChatRow) => {
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

                  Column() {
                    Text(row.title)
                      .fontSize(this.getTheme().typography.body.fontSize)
                      .fontColor(this.getTheme().colors.textPrimary)
                      .width('100%')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    // 成员数是服务端给的，读不到就是 0 —— 宁可不出这行，也不编一个人数。
                    if (row.memberCount > 0) {
                      Text(this.t('{0} members', row.memberCount))
                        .fontSize(this.getTheme().typography.caption.fontSize)
                        .fontColor(this.getTheme().colors.textSecondary)
                        .width('100%')
                        .maxLines(1)
                    }
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .height(52)
                .alignItems(VerticalAlign.Center)
                .padding({ left: this.getTheme().spacing.md, right: this.getTheme().spacing.md })
                .id(`privacy-picker-chat-${row.chatId}`)
                .onClick((): void => {
                  this.onDispatch(new TogglePrivacyPickerChat(row.chatId));
                })
              }
            }, (row: PrivacyChatRow): string => `c${row.chatId}:${row.selected ? 1 : 0}`)
          }
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getTheme().colors.background)
  }

  @Builder
  PickerSectionHeaderView(slug: string, label: string) {
    Text(this.t(label))
      .fontSize(this.getTheme().typography.caption.fontSize)
      .fontColor(this.getTheme().colors.textSecondary)
      .width('100%')
      .padding({
        left: this.getTheme().spacing.md,
        right: this.getTheme().spacing.md,
        top: this.getTheme().spacing.md,
        bottom: this.getTheme().spacing.xs
      })
      .id(`privacy-picker-section-${slug}`)
  }

  private pickerContacts(): PrivacyContactRow[] {
    const detail: PrivacyDetailState | null = this.detail();
    return detail === null ? [] : detail.contacts;
  }

  private pickerChats(): PrivacyChatRow[] {
    const detail: PrivacyDetailState | null = this.detail();
    return detail === null ? [] : detail.chats;
  }

  /** 空态判据是「两个分区都没有候选」，只看联系人会误报「暂无联系人」。 */
  private pickerIsEmpty(): boolean {
    return this.pickerContacts().length === 0 && this.pickerChats().length === 0;
  }
}
