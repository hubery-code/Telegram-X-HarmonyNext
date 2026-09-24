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
 * feature/settings — 「自动媒体下载」子页（AUTODL-101 / FEAT-P2-007 下载策略部分）。
 *
 * 对齐 Telegram X 的 Automatic Media Download 页：三个会话分区各一行（私聊 / 群组 / 频道），
 * 副标题直接列出这一区当前会自动下载的媒体；点行进该分区的勾选面板。
 *
 * 面板里只有「哪一类媒体自动下」这一个决定，所以勾选即写回、没有「应用」按钮 ——
 * 与 TGX 的对话框一致，也省掉一份和 UiState 并存的草稿态。
 *
 * 刻意不做的是 TGX 的「移动网络 / 漫游」两个网络维度与「文件大小上限」：
 * 前者要把下载门接到网络状态，后者要在下载侧加尺寸判定，都另包处理。
 */

import { Theme, ThemeManager, LightTheme } from '@tgx/core-design-system';
import { Lang, SupportedLanguage } from '@tgx/core-common';
import {
  AutoDownloadChatScope,
  AutoDownloadFlags,
  AutoDownloadMediaKind,
  AutoDownloadPolicy
} from '@tgx/core-domain';
import { SettingsUiState } from '../contract/SettingsUiState';
import {
  LoadAutoDownloadPolicy,
  SetAutoDownloadKind,
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

@Component
export struct AutoDownloadSubPage {
  @Prop @Watch('onUiStateChanged') uiState: SettingsUiState = SettingsUiState.initial();
  onDispatch: (intent: SettingsIntent) => void = (): void => {};
  onBack: () => void = (): void => {};

  @State private effectiveTheme: Theme = LightTheme;
  @State private effectiveLang: SupportedLanguage = 'en';
  /** 面板开在哪一区；null 表示关闭。页面私有的展开态，不进 UiState。 */
  @State private editingScope: AutoDownloadChatScope | null = null;

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

            ForEach(AUTO_DOWNLOAD_SCOPE_ORDER, (scope: AutoDownloadChatScope) => {
              Column() {
                this.ScopeRow(scope)
              }
              .width('100%')
              .backgroundColor(this.getTheme().colors.surface)
              .borderRadius(this.getTheme().radius.md)
              .margin({ bottom: this.getTheme().spacing.md })
            }, (scope: AutoDownloadChatScope): string => scope)

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
}
