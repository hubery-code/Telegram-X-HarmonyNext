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
 * feature/settings — 「自动媒体下载」子页（AUTODL-101 + AUTODL-102 + AUTODL-103 / FEAT-P2-007 下载策略部分）。
 *
 * 对齐 Telegram X 的 Automatic Media Download 页：三个会话分区各一行（私聊 / 群组 / 频道），
 * 副标题直接列出这一区当前会自动下载的媒体；点行进该分区的勾选面板。
 *
 * 面板里只有「哪一类媒体自动下」这一个决定，所以勾选即写回、没有「应用」按钮 ——
 * 与 TGX 的对话框一致，也省掉一份和 UiState 并存的草稿态。
 *
 * AUTODL-102 补上了顶部那张「省流量」卡（TGX 的 Data Saver 页在同一层级）：
 * 主开关 + 「自动开启」两档（移动网络 / 漫游）。它和下面的分区策略是**两套设置**：
 * 省流量生效时一票否决，不看分区勾了什么 —— Android 也是存在另一个偏好键里。
 * 摘要恒按当前设置显示 Mobile / Roaming / both / None，与 TGX 的
 * `SettingsDataController.java:156-158` 一致。
 *
 * AUTODL-103 再补上底部三行「按网络类型限制」（Android 的 `Restrict on mobile data /
 * Wi-Fi / roaming`）：每档一个尺寸上限 + 七类「不自动下」的排除项，存在第三套偏好键里。
 * 判定压在分区策略**之前**（`TdlibFilesManager.java:1381` 早于 `:1407`），所以 Wi-Fi 上限
 * 调到 1MB 时，3MB 的照片不会因为「私聊勾了照片」就放过去。
 *
 * 三套设置各自读盘、各自写回，互不覆盖 —— 这是 Android 的存法，本端照搬以免互相打架。
 */

import { Theme, ThemeManager, LightTheme } from '@tgx/core-design-system';
import { A11y, a11y, Lang, SupportedLanguage } from '@tgx/core-common';
import {
  AutoDownloadChatScope,
  AutoDownloadFlags,
  AutoDownloadMediaKind,
  AutoDownloadPolicy,
  DATA_SAVER_AUTO_ON_FLAGS,
  DATA_SAVER_FLAG_ENABLED,
  DOWNLOAD_LIMIT_OPTIONS,
  DataSaverNetworkType,
  DataSaverSettings,
  DownloadLimitsByNetwork,
  NetworkDownloadLimits
} from '@tgx/core-domain';
import { SettingsUiState } from '../contract/SettingsUiState';
import {
  LoadAutoDownloadPolicy,
  LoadDataSaverSettings,
  LoadDownloadLimits,
  SetAutoDownloadKind,
  SetDataSaverFlag,
  SetDownloadLimitExclusion,
  SetDownloadLimitSize,
  SettingsIntent
} from '../contract/SettingsIntent';
import {
  AUTO_DOWNLOAD_KIND_ORDER,
  AUTO_DOWNLOAD_SCOPE_ORDER,
  AutoDownloadScopeSummary,
  autoDownloadKindEnabled,
  autoDownloadKindLabelKey,
  autoDownloadScopeLabelKey,
  autoDownloadScopeSummary
} from '../model/AutoDownloadRows';
import { dataSaverAutoOnLabelKey } from '../model/DataSaverRows';
import {
  DOWNLOAD_LIMIT_NETWORK_ORDER,
  DownloadLimitSummary,
  downloadLimitKindLabelKey,
  downloadLimitNetworkLabelKey,
  downloadLimitOfNetwork,
  downloadLimitSizeLabelKey,
  downloadLimitSummary
} from '../model/DownloadLimitRows';

@Component
export struct AutoDownloadSubPage {
  @Prop @Watch('onUiStateChanged') uiState: SettingsUiState = SettingsUiState.initial();
  onDispatch: (intent: SettingsIntent) => void = (): void => {};
  onBack: () => void = (): void => {};

  @State private effectiveTheme: Theme = LightTheme;
  @State private effectiveLang: SupportedLanguage = 'en';
  /** 面板开在哪一区；null 表示关闭。页面私有的展开态，不进 UiState。 */
  @State private editingScope: AutoDownloadChatScope | null = null;
  /** AUTODL-102：「自动开启」面板是否打开。同样是页面私有的展开态。 */
  @State private showAutoOnSheet: boolean = false;
  /** AUTODL-103：限制面板开在哪一档网络；null 表示关闭。 */
  @State private editingLimitNetwork: DataSaverNetworkType | null = null;

  private unsubscribeTheme: (() => void) | null = null;
  private unsubscribeLang: (() => void) | null = null;

  aboutToAppear(): void {
    this.updateEffectiveTheme();
    this.effectiveLang = Lang.getInstance().getLanguage();
    const self: AutoDownloadSubPage = this;
    this.unsubscribeTheme = ThemeManager.getInstance().subscribe((_theme: Theme): void => {
      self.updateEffectiveTheme();
    });
    this.unsubscribeLang = Lang.getInstance().subscribe((lang: SupportedLanguage): void => {
      self.effectiveLang = lang;
    });
    this.onDispatch(new LoadAutoDownloadPolicy());
    this.onDispatch(new LoadDataSaverSettings());
    this.onDispatch(new LoadDownloadLimits());
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

  private flagsOf(scope: AutoDownloadChatScope): AutoDownloadFlags | null {
    const policy: AutoDownloadPolicy | null = this.uiState.autoDownloadPolicy;
    return policy === null ? null : policy.flagsOf(scope);
  }

  /**
   * 一区副标题的译文：还没读盘显 Loading，一条都没勾显「不自动下载」，
   * 否则按掩码位序列出媒体类型（多项用「 · 」连接）。
   */
  private scopeSummaryText(scope: AutoDownloadChatScope): string {
    const summary: AutoDownloadScopeSummary = autoDownloadScopeSummary(this.flagsOf(scope));
    if (summary.singleKey.length > 0) {
      return this.t(summary.singleKey);
    }
    const labels: string[] = [];
    for (const kindKey of summary.kindKeys) {
      labels.push(this.t(kindKey));
    }
    return labels.join(' · ');
  }

  private editingScopeLabel(): string {
    const scope: AutoDownloadChatScope | null = this.editingScope;
    return scope === null ? '' : this.t(autoDownloadScopeLabelKey(scope));
  }

  /**
   * 面板里某一行的开关态与写回。
   * 收成方法而不是在 @Builder 里写局部量：@Builder 的按值入参不参与状态观察，
   * 只有在这里现读 this.uiState 才能让勾选立刻反映到开关上。
   */
  private isKindOn(kind: AutoDownloadMediaKind): boolean {
    const scope: AutoDownloadChatScope | null = this.editingScope;
    return scope !== null && autoDownloadKindEnabled(this.flagsOf(scope), kind);
  }

  private onKindToggled(kind: AutoDownloadMediaKind, isOn: boolean): void {
    const scope: AutoDownloadChatScope | null = this.editingScope;
    if (scope !== null) {
      this.onDispatch(new SetAutoDownloadKind(scope, kind, isOn));
    }
  }

  /**
   * AUTODL-102：省流量某一位的当前态。
   * 与 `isKindOn` 同理，现读 `this.uiState` 才能让勾选立刻反映到开关上；
   * 还没读盘时一律显未开（主开关未开、两档未勾），避免首帧闪一下又收回去。
   */
  private isDataSaverFlagOn(flag: number): boolean {
    const settings: DataSaverSettings | null = this.uiState.dataSaverSettings;
    return settings !== null && settings.ofFlag(flag);
  }

  private onDataSaverFlagToggled(flag: number, isOn: boolean): void {
    this.onDispatch(new SetDataSaverFlag(flag, isOn));
  }

  /** 「自动开启」行的副标题：Mobile / Roaming / both / None，与 Android 四态一致。 */
  private autoOnSummaryText(): string {
    const settings: DataSaverSettings | null = this.uiState.dataSaverSettings;
    if (settings === null) {
      return this.t('Loading...');
    }
    return this.t(settings.autoOnSummaryKey());
  }

  // ---- AUTODL-103 按网络类型的限制 ----

  /**
   * 一行的副标题：整句键 → 尺寸句 + 裸类型名列表（Android 用「, 」拼接，
   * 如 `Any media exceeding 50 MB, Photos, Videos`）。
   */
  private limitSummaryText(network: DataSaverNetworkType): string {
    const summary: DownloadLimitSummary =
      downloadLimitSummary(downloadLimitOfNetwork(this.uiState.downloadLimits, network));
    if (summary.singleKey.length > 0) {
      return this.t(summary.singleKey);
    }
    const parts: string[] = [];
    if (summary.exceedingKey.length > 0) {
      parts.push(this.t(summary.exceedingKey, summary.sizeLabel));
    }
    for (const kindKey of summary.excludedKeys) {
      parts.push(this.t(kindKey));
    }
    return parts.join(', ');
  }

  private editingLimitLabel(): string {
    const network: DataSaverNetworkType | null = this.editingLimitNetwork;
    return network === null ? '' : this.t(downloadLimitNetworkLabelKey(network));
  }

  /** 面板里某一类「不自动下」的勾选态；现读 this.uiState 才会点完立刻反映到开关上。 */
  private isExclusionOn(kind: AutoDownloadMediaKind): boolean {
    const network: DataSaverNetworkType | null = this.editingLimitNetwork;
    if (network === null) {
      return false;
    }
    const limits: NetworkDownloadLimits | null =
      downloadLimitOfNetwork(this.uiState.downloadLimits, network);
    return limits !== null && limits.isExcluded(kind);
  }

  private onExclusionToggled(kind: AutoDownloadMediaKind, isOn: boolean): void {
    const network: DataSaverNetworkType | null = this.editingLimitNetwork;
    if (network !== null) {
      this.onDispatch(new SetDownloadLimitExclusion(network, kind, isOn));
    }
  }

  private isSizeSelected(code: number): boolean {
    const network: DataSaverNetworkType | null = this.editingLimitNetwork;
    if (network === null) {
      return false;
    }
    const limits: NetworkDownloadLimits | null =
      downloadLimitOfNetwork(this.uiState.downloadLimits, network);
    return limits !== null && limits.sizeCode === code;
  }

  private onSizePicked(code: number): void {
    const network: DataSaverNetworkType | null = this.editingLimitNetwork;
    if (network !== null) {
      this.onDispatch(new SetDownloadLimitSize(network, code));
    }
  }

  build() {
    Stack() {
      Column() {
        this.HeaderView()

        Scroll() {
          Column() {
            if (this.uiState.errorMessage !== null) {
              Text(this.uiState.errorMessage)
                .fontSize(this.getTheme().typography.footnote.fontSize)
                .fontColor(this.getTheme().colors.destructive)
                .width('100%')
                .padding(this.getTheme().spacing.md)
                .margin({ bottom: this.getTheme().spacing.md })
                .backgroundColor(this.getTheme().colors.surface)
                .borderRadius(this.getTheme().radius.md)
            }

            // AUTODL-102：省流量卡压在分区策略之上 —— 生效时一票否决，不看下面勾了什么。
            Column() {
              this.DataSaverMasterRow()
              Divider()
                .color(this.getTheme().colors.divider)
                .strokeWidth(0.5)
                .margin({ left: this.getTheme().spacing.md, right: this.getTheme().spacing.md })
              this.DataSaverAutoOnRow()
            }
            .width('100%')
            .backgroundColor(this.getTheme().colors.surface)
            .borderRadius(this.getTheme().radius.md)
            .margin({ bottom: this.getTheme().spacing.xs })

            Text(this.t('Media never downloads automatically while Data Saver is on.'))
              .fontSize(this.getTheme().typography.footnote.fontSize)
              .fontColor(this.getTheme().colors.textSecondary)
              .margin({
                bottom: this.getTheme().spacing.lg,
                left: this.getTheme().spacing.xs,
                right: this.getTheme().spacing.xs
              })
              .width('100%')

            ForEach(AUTO_DOWNLOAD_SCOPE_ORDER, (scope: AutoDownloadChatScope) => {
              Column() {
                this.ScopeRow(scope)
              }
              .width('100%')
              .backgroundColor(this.getTheme().colors.surface)
              .borderRadius(this.getTheme().radius.md)
              .margin({ bottom: this.getTheme().spacing.md })
            }, (scope: AutoDownloadChatScope): string => scope)

            // AUTODL-103：三档网络各一行（Android 的 advanced items 就在分区行的下面）。
            Column() {
              ForEach(DOWNLOAD_LIMIT_NETWORK_ORDER, (network: DataSaverNetworkType) => {
                if (network !== DOWNLOAD_LIMIT_NETWORK_ORDER[0]) {
                  Divider()
                    .color(this.getTheme().colors.divider)
                    .strokeWidth(0.5)
                    .margin({ left: this.getTheme().spacing.md, right: this.getTheme().spacing.md })
                }
                this.DownloadLimitRow(network)
              }, (network: DataSaverNetworkType): string => network)
            }
            .width('100%')
            .backgroundColor(this.getTheme().colors.surface)
            .borderRadius(this.getTheme().radius.md)
            .margin({ bottom: this.getTheme().spacing.md })

            Text(this.t('Media still downloads when you tap it.'))
              .fontSize(this.getTheme().typography.footnote.fontSize)
              .fontColor(this.getTheme().colors.textSecondary)
              .margin({
                top: this.getTheme().spacing.xs,
                left: this.getTheme().spacing.xs,
                right: this.getTheme().spacing.xs
              })
              .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({
            left: this.getTheme().spacing.screenInset,
            right: this.getTheme().spacing.screenInset,
            bottom: this.getTheme().spacing.xxl
          })
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getTheme().colors.background)

      if (this.editingScope !== null) {
        this.ScopeSheet()
      }

      if (this.showAutoOnSheet) {
        this.AutoOnSheet()
      }

      if (this.editingLimitNetwork !== null) {
        this.DownloadLimitSheet()
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

      Text(this.t('Automatic Media Download'))
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
  ScopeRow(scope: AutoDownloadChatScope) {
    Row() {
      Column() {
        Text(this.t(autoDownloadScopeLabelKey(scope)))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontColor(this.getTheme().colors.textPrimary)

        Text(this.scopeSummaryText(scope))
          .fontSize(this.getTheme().typography.footnote.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .margin({ top: this.getTheme().spacing.xs })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(18)
        .height(18)
        .fillColor(this.getTheme().colors.textSecondary)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.editingScope = scope;
    })
  }

  @Builder
  ScopeSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getTheme().colors.scrim)
        .onClick((): void => {
          this.editingScope = null;
        })

      Column() {
        Row() {
          Column() {
            Text(this.t('Automatic download'))
              .fontSize(this.getTheme().typography.title.fontSize)
              .fontWeight(this.getTheme().typography.title.fontWeight)
              .fontColor(this.getTheme().colors.textPrimary)

            Text(this.editingScopeLabel())
              .fontSize(this.getTheme().typography.footnote.fontSize)
              .fontColor(this.getTheme().colors.textSecondary)
              .margin({ top: this.getTheme().spacing.hairline })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor(this.getTheme().colors.textSecondary)
          .accessibilityText(a11y(A11y.CLOSE))
            .onClick((): void => {
              this.editingScope = null;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: this.getTheme().spacing.md })

        ForEach(AUTO_DOWNLOAD_KIND_ORDER, (kind: AutoDownloadMediaKind) => {
          this.KindRow(kind)
        }, (kind: AutoDownloadMediaKind): string => kind)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(this.getTheme().spacing.lg)
      .backgroundColor(this.getTheme().colors.background)
      .borderRadius({
        topLeft: this.getTheme().radius.xl,
        topRight: this.getTheme().radius.xl
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  KindRow(kind: AutoDownloadMediaKind) {
    Row() {
      Text(this.t(autoDownloadKindLabelKey(kind)))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)

      Toggle({
        type: ToggleType.Switch,
        isOn: this.isKindOn(kind)
      })
        .onChange((isOn: boolean): void => {
          this.onKindToggled(kind, isOn);
        })
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
  }

  // ---- AUTODL-102 省流量（Data Saver）----

  @Builder
  DataSaverMasterRow() {
    Row() {
      Text(this.t('Data Saver'))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)

      Toggle({
        type: ToggleType.Switch,
        isOn: this.isDataSaverFlagOn(DATA_SAVER_FLAG_ENABLED)
      })
        .onChange((isOn: boolean): void => {
          this.onDataSaverFlagToggled(DATA_SAVER_FLAG_ENABLED, isOn);
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: this.getTheme().spacing.md, right: this.getTheme().spacing.md })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 「自动开启」行。TGX 把它做成单选（Radio）样式但实际弹的是多选面板
   * （`SettingsDataController.java:516-519` 是两个 CheckBox），这里照面板做：
   * 两档互不排斥，Wi-Fi 下永远不拦。
   */
  @Builder
  DataSaverAutoOnRow() {
    Row() {
      Column() {
        Text(this.t('Turn on automatically'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontColor(this.getTheme().colors.textPrimary)

        Text(this.autoOnSummaryText())
          .fontSize(this.getTheme().typography.footnote.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .margin({ top: this.getTheme().spacing.hairline })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(18)
        .height(18)
        .fillColor(this.getTheme().colors.textSecondary)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.showAutoOnSheet = true;
    })
  }

  @Builder
  AutoOnSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getTheme().colors.scrim)
        .onClick((): void => {
          this.showAutoOnSheet = false;
        })

      Column() {
        Row() {
          Text(this.t('Turn on automatically'))
            .fontSize(this.getTheme().typography.title.fontSize)
            .fontWeight(this.getTheme().typography.title.fontWeight)
            .fontColor(this.getTheme().colors.textPrimary)
            .layoutWeight(1)

          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor(this.getTheme().colors.textSecondary)
          .accessibilityText(a11y(A11y.CLOSE))
            .onClick((): void => {
              this.showAutoOnSheet = false;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: this.getTheme().spacing.md })

        ForEach(DATA_SAVER_AUTO_ON_FLAGS, (flag: number) => {
          this.AutoOnFlagRow(flag)
        }, (flag: number): string => `${flag}`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(this.getTheme().spacing.lg)
      .backgroundColor(this.getTheme().colors.background)
      .borderRadius({
        topLeft: this.getTheme().radius.xl,
        topRight: this.getTheme().radius.xl
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AutoOnFlagRow(flag: number) {
    Row() {
      Text(this.t(dataSaverAutoOnLabelKey(flag)))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)

      Toggle({
        type: ToggleType.Switch,
        isOn: this.isDataSaverFlagOn(flag)
      })
        .onChange((isOn: boolean): void => {
          this.onDataSaverFlagToggled(flag, isOn);
        })
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
  }

  // ---- AUTODL-103 按网络类型的限制（Android `Restrict on …` 三行 + 其面板）----

  @Builder
  DownloadLimitRow(network: DataSaverNetworkType) {
    Row() {
      Column() {
        Text(this.t(downloadLimitNetworkLabelKey(network)))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontColor(this.getTheme().colors.textPrimary)

        Text(this.limitSummaryText(network))
          .fontSize(this.getTheme().typography.footnote.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .margin({ top: this.getTheme().spacing.hairline })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(18)
        .height(18)
        .fillColor(this.getTheme().colors.textSecondary)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.editingLimitNetwork = network;
    })
  }

  /**
   * 一档网络的限制面板。内容顺序照 Android `SettingsDataController.java:520-568`：
   * 先七类「不自动下」的勾选，再尺寸档位单选。
   *
   * 与 Android 的差别只有交互：那边是关掉面板时统一 `onApplySettings` 写回，
   * 本端沿用 AUTODL-101/102 的口径 —— 勾选即写盘，没有草稿态。
   */
  @Builder
  DownloadLimitSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getTheme().colors.scrim)
        .onClick((): void => {
          this.editingLimitNetwork = null;
        })

      Column() {
        Row() {
          Column() {
            Text(this.t('Automatic download'))
              .fontSize(this.getTheme().typography.title.fontSize)
              .fontWeight(this.getTheme().typography.title.fontWeight)
              .fontColor(this.getTheme().colors.textPrimary)

            Text(this.editingLimitLabel())
              .fontSize(this.getTheme().typography.footnote.fontSize)
              .fontColor(this.getTheme().colors.textSecondary)
              .margin({ top: this.getTheme().spacing.hairline })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor(this.getTheme().colors.textSecondary)
          .accessibilityText(a11y(A11y.CLOSE))
            .onClick((): void => {
              this.editingLimitNetwork = null;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: this.getTheme().spacing.md })

        // 十四行（七勾选 + 七档位）在小屏上会顶出屏幕，所以列表侧可滚、头部固定。
        Scroll() {
          Column() {
            ForEach(AUTO_DOWNLOAD_KIND_ORDER, (kind: AutoDownloadMediaKind) => {
              this.LimitExclusionRow(kind)
            }, (kind: AutoDownloadMediaKind): string => kind)

            Divider()
              .color(this.getTheme().colors.divider)
              .strokeWidth(0.5)
              .margin({ top: this.getTheme().spacing.sm, bottom: this.getTheme().spacing.sm })

            ForEach(DOWNLOAD_LIMIT_OPTIONS, (code: number) => {
              this.LimitSizeRow(code)
            }, (code: number): string => `${code}`)
          }
          .width('100%')
        }
        .constraintSize({ maxHeight: 420 })
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(this.getTheme().spacing.lg)
      .backgroundColor(this.getTheme().colors.background)
      .borderRadius({
        topLeft: this.getTheme().radius.xl,
        topRight: this.getTheme().radius.xl
      })
    }
    .width('100%')
    .height('100%')
  }

  /** 勾选语义是「这一类不自动下」，所以开关向上等于排除（与分区面板相反）。 */
  @Builder
  LimitExclusionRow(kind: AutoDownloadMediaKind) {
    Row() {
      Text(this.t(downloadLimitKindLabelKey(kind)))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)

      Toggle({
        type: ToggleType.Switch,
        isOn: this.isExclusionOn(kind)
      })
        .onChange((isOn: boolean): void => {
          this.onExclusionToggled(kind, isOn);
        })
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 尺寸档位单选。圆点直接内联：@Builder 的按值入参不参与状态观察，
   * 抽成 `Radio(selected)` 会点完不变（同 `ProxySubPage` 的单选列表）。
   */
  @Builder
  LimitSizeRow(code: number) {
    Row() {
      Stack() {
        if (this.isSizeSelected(code)) {
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
        color: this.isSizeSelected(code)
          ? this.getTheme().colors.accent
          : this.getTheme().colors.textSecondary
      })

      Text(this.t(downloadLimitSizeLabelKey(code)))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      this.onSizePicked(code);
    })
  }
}
