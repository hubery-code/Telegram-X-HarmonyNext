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
 * feature/settings — 活跃设备与登录会话管理页面（FEAT-P2-008）。
 *
 * 对齐 Telegram X Devices 页面规范：
 * - 展示当前登录设备型号、系统及应用版本、IP 与地理位置，标记“在线”；
 * - 终止所有其他会话按钮（红字高危操作 + 二次弹窗确认）；
 * - 活跃会话列表：展示其他登录设备名称、活跃时间、登录地点及 IP；
 * - 单击单条会话弹出确认终止弹窗（Terminate Session）；
 * - 加载态与空态提示。
 */

import { LightTheme, Theme, ThemeManager } from '@tgx/core-design-system';
import { A11y, a11y, Lang, SupportedLanguage } from '@tgx/core-common';
import { ActiveSessionItem } from '../model/ActiveSessionItem';
import { SettingsUiState } from '../contract/SettingsUiState';
import {
  LoadActiveSessions,
  SetErrorMessage,
  SettingsIntent,
  TerminateAllOtherSessionsIntent,
  TerminateSessionIntent
} from '../contract/SettingsIntent';

export function formatSessionDate(timestampSeconds: number, isZh: boolean = false): string {
  if (timestampSeconds <= 0) {
    return isZh ? '在线' : 'Online';
  }
  const date: Date = new Date(timestampSeconds * 1000);
  const now: Date = new Date();
  const diffSec: number = Math.floor((now.getTime() - date.getTime()) / 1000);
  if (diffSec < 60) {
    return isZh ? '刚刚' : 'Just now';
  }
  if (diffSec < 3600) {
    const mins: number = Math.floor(diffSec / 60);
    return isZh ? `${mins} 分钟前` : `${mins} min ago`;
  }
  const hours: string = String(date.getHours()).padStart(2, '0');
  const minutes: string = String(date.getMinutes()).padStart(2, '0');
  const month: number = date.getMonth() + 1;
  const day: number = date.getDate();
  const isSameYear: boolean = date.getFullYear() === now.getFullYear();

  if (isZh) {
    if (isSameYear) {
      return `${month}月${day}日 ${hours}:${minutes}`;
    }
    return `${date.getFullYear()}年${month}月${day}日 ${hours}:${minutes}`;
  } else {
    const months: string[] = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const monthStr: string = months[date.getMonth()];
    if (isSameYear) {
      return `${monthStr} ${day}, ${hours}:${minutes}`;
    }
    return `${monthStr} ${day}, ${date.getFullYear()}, ${hours}:${minutes}`;
  }
}

@Component
export struct DevicesSubPage {
  @Prop @Watch('onUiStateChanged') uiState: SettingsUiState = SettingsUiState.initial();
  onDispatch: (intent: SettingsIntent) => void = (): void => {};
  onBack: () => void = (): void => {};

  @State private effectiveTheme: Theme = LightTheme;
  @State private effectiveLang: SupportedLanguage = 'en';
  @State private terminateTarget: ActiveSessionItem | null = null;
  @State private showTerminateAllConfirm: boolean = false;

  private unsubscribeTheme: (() => void) | null = null;
  private unsubscribeLang: (() => void) | null = null;

  aboutToAppear(): void {
    this.updateEffectiveTheme();
    this.effectiveLang = Lang.getInstance().getLanguage();
    const self: DevicesSubPage = this;
    this.unsubscribeTheme = ThemeManager.getInstance().subscribe((_theme: Theme): void => {
      self.updateEffectiveTheme();
    });
    this.unsubscribeLang = Lang.getInstance().subscribe((lang: SupportedLanguage): void => {
      self.effectiveLang = lang;
    });
    this.onDispatch(new LoadActiveSessions());
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
    const langCode: SupportedLanguage = this.uiState.languageCode === 'zh' || this.effectiveLang === 'zh' ? 'zh' : 'en';
    return Lang.getInstance().formatByKey(key, langCode, args);
  }

  private isChinese(): boolean {
    return this.uiState.languageCode === 'zh' || this.effectiveLang === 'zh';
  }

  private getCurrentSession(): ActiveSessionItem {
    for (let i = 0; i < this.uiState.activeSessions.length; i++) {
      if (this.uiState.activeSessions[i].isCurrent) {
        return this.uiState.activeSessions[i];
      }
    }
    if (this.uiState.activeSessions.length > 0) {
      return this.uiState.activeSessions[0];
    }
    return {
      id: 'current_device',
      isCurrent: true,
      deviceModel: 'HUAWEI Mate 60 Pro',
      platform: 'HarmonyOS NEXT',
      applicationName: 'Telegram X',
      applicationVersion: '0.26.8',
      ipAddress: '127.0.0.1',
      location: 'Local',
      lastActiveDate: 0
    };
  }

  private getOtherSessions(): ActiveSessionItem[] {
    const others: ActiveSessionItem[] = [];
    let foundCurrent: boolean = false;
    for (let i = 0; i < this.uiState.activeSessions.length; i++) {
      const s: ActiveSessionItem = this.uiState.activeSessions[i];
      if (s.isCurrent) {
        foundCurrent = true;
      } else {
        others.push(s);
      }
    }
    if (!foundCurrent && this.uiState.activeSessions.length > 1) {
      return this.uiState.activeSessions.slice(1);
    }
    return others;
  }

  build() {
    Stack() {
      Column() {
        this.HeaderView()

        Scroll() {
          Column() {
            if (this.uiState.errorMessage !== null) {
              this.ErrorBannerView()
            }

            this.SectionTitle(this.t('THIS DEVICE'))
            this.CurrentDeviceCardView()

            if (this.getOtherSessions().length > 0) {
              this.TerminateAllButtonView()
            }

            this.SectionTitle(this.t('ACTIVE SESSIONS'))
            this.OtherSessionsCardView()
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

      if (this.showTerminateAllConfirm) {
        this.TerminateAllConfirmDialog()
      }

      if (this.terminateTarget !== null) {
        this.TerminateSessionConfirmDialog()
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

      Text(this.t('Devices'))
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
  SectionTitle(title: string) {
    Text(title)
      .fontSize(this.getTheme().typography.caption.fontSize)
      .fontWeight(this.getTheme().typography.caption.fontWeight)
      .fontColor(this.getTheme().colors.textSecondary)
      .margin({
        top: this.getTheme().spacing.md,
        bottom: this.getTheme().spacing.xs,
        left: this.getTheme().spacing.xs
      })
      .width('100%')
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
  CurrentDeviceCardView() {
    Row() {
      Row() {
        Image($r('app.media.ic_devices'))
          .width(26)
          .height(26)
          .fillColor(this.getTheme().colors.accent)
      }
      .width(44)
      .height(44)
      .borderRadius(this.getTheme().radius.full)
      .backgroundColor(this.getTheme().colors.surfaceVariant)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ right: this.getTheme().spacing.md })

      Column() {
        Row() {
          Text(this.getCurrentSession().deviceModel)
            .fontSize(this.getTheme().typography.headline.fontSize)
            .fontWeight(this.getTheme().typography.headline.fontWeight)
            .fontColor(this.getTheme().colors.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.t('Online'))
            .fontSize(this.getTheme().typography.caption.fontSize)
            .fontColor(this.getTheme().colors.accent)
            .backgroundColor(this.getTheme().colors.surfaceVariant)
            .padding({
              left: this.getTheme().spacing.sm,
              right: this.getTheme().spacing.sm,
              top: this.getTheme().spacing.hairline,
              bottom: this.getTheme().spacing.hairline
            })
            .borderRadius(this.getTheme().radius.full)
            .margin({ left: this.getTheme().spacing.xs })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(`${this.getCurrentSession().applicationName} ${this.getCurrentSession().applicationVersion}, ${this.getCurrentSession().platform}`)
          .fontSize(this.getTheme().typography.subheadline.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .margin({ top: this.getTheme().spacing.xs })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`${this.getCurrentSession().location} · ${this.getCurrentSession().ipAddress}`)
          .fontSize(this.getTheme().typography.footnote.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .margin({ top: this.getTheme().spacing.hairline })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
    .margin({ bottom: this.getTheme().spacing.md })
  }

  @Builder
  TerminateAllButtonView() {
    Column() {
      Row() {
        Image($r('app.media.ic_block'))
          .width(22)
          .height(22)
          .fillColor(this.getTheme().colors.destructive)
          .margin({ right: this.getTheme().spacing.sm })

        Column() {
          Text(this.t('Terminate All Other Sessions'))
            .fontSize(this.getTheme().typography.body.fontSize)
            .fontWeight(this.getTheme().typography.headline.fontWeight)
            .fontColor(this.getTheme().colors.destructive)

          Text(this.isChinese() ? '退出除当前设备外的所有登录会话' : 'Logs out all devices except for this one.')
            .fontSize(this.getTheme().typography.footnote.fontSize)
            .fontColor(this.getTheme().colors.textSecondary)
            .margin({ top: this.getTheme().spacing.xs })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
    .margin({ bottom: this.getTheme().spacing.md })
    .onClick((): void => {
      this.showTerminateAllConfirm = true;
    })
  }

  @Builder
  OtherSessionsCardView() {
    Column() {
      if (this.uiState.isLoadingSessions && this.uiState.activeSessions.length === 0) {
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
        .padding(this.getTheme().spacing.md)
        .justifyContent(FlexAlign.Center)
      } else if (this.getOtherSessions().length === 0) {
        Row() {
          Text(this.t('No other active sessions'))
            .fontSize(this.getTheme().typography.subheadline.fontSize)
            .fontColor(this.getTheme().colors.textSecondary)
        }
        .width('100%')
        .padding(this.getTheme().spacing.lg)
        .justifyContent(FlexAlign.Center)
      } else {
        ForEach(this.getOtherSessions(), (item: ActiveSessionItem, index: number) => {
          Column() {
            if (index > 0) {
              Divider()
                .color(this.getTheme().colors.divider)
                .margin({ top: this.getTheme().spacing.sm, bottom: this.getTheme().spacing.sm })
            }

            Row() {
              Image($r('app.media.ic_devices'))
                .width(22)
                .height(22)
                .fillColor(this.getTheme().colors.accent)
                .margin({ right: this.getTheme().spacing.sm })

              Column() {
                Text(item.deviceModel.length > 0 ? item.deviceModel : item.applicationName)
                  .fontSize(this.getTheme().typography.headline.fontSize)
                  .fontWeight(this.getTheme().typography.headline.fontWeight)
                  .fontColor(this.getTheme().colors.textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(`${item.applicationName} ${item.applicationVersion}, ${item.platform}`)
                  .fontSize(this.getTheme().typography.footnote.fontSize)
                  .fontColor(this.getTheme().colors.textSecondary)
                  .margin({ top: this.getTheme().spacing.hairline })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(`${item.location} · ${formatSessionDate(item.lastActiveDate, this.isChinese())} · ${item.ipAddress}`)
                  .fontSize(this.getTheme().typography.caption.fontSize)
                  .fontColor(this.getTheme().colors.textSecondary)
                  .margin({ top: this.getTheme().spacing.hairline })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Image($r('app.media.ic_delete'))
                .width(20)
                .height(20)
                .fillColor(this.getTheme().colors.textSecondary)
                .margin({ left: this.getTheme().spacing.sm })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .onClick((): void => {
              this.terminateTarget = item;
            })
          }
          .width('100%')
        })
      }
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
  }

  @Builder
  TerminateAllConfirmDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getTheme().colors.scrim)
        .onClick((): void => {
          this.showTerminateAllConfirm = false;
        })

      Column() {
        Text(this.t('Terminate All Other Sessions'))
          .fontSize(this.getTheme().typography.headline.fontSize)
          .fontWeight(this.getTheme().typography.headline.fontWeight)
          .fontColor(this.getTheme().colors.textPrimary)
          .margin({ bottom: this.getTheme().spacing.sm })

        Text(this.t('Are you sure you want to terminate all other sessions?'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .textAlign(TextAlign.Center)
          .margin({ bottom: this.getTheme().spacing.lg })

        Row() {
          Button(this.t('Cancel'))
            .layoutWeight(1)
            .height(40)
            .margin({ right: this.getTheme().spacing.sm })
            .fontSize(this.getTheme().typography.body.fontSize)
            .fontColor(this.getTheme().colors.textPrimary)
            .backgroundColor(this.getTheme().colors.surfaceVariant)
            .borderRadius(this.getTheme().radius.md)
            .onClick((): void => {
              this.showTerminateAllConfirm = false;
            })

          Button(this.t('Terminate'))
            .layoutWeight(1)
            .height(40)
            .margin({ left: this.getTheme().spacing.sm })
            .fontSize(this.getTheme().typography.body.fontSize)
            .fontColor(this.getTheme().colors.textOnAccent)
            .backgroundColor(this.getTheme().colors.destructive)
            .borderRadius(this.getTheme().radius.md)
            .onClick((): void => {
              this.showTerminateAllConfirm = false;
              this.onDispatch(new TerminateAllOtherSessionsIntent());
            })
        }
        .width('100%')
      }
      .width('82%')
      .padding(this.getTheme().spacing.lg)
      .backgroundColor(this.getTheme().colors.surface)
      .borderRadius(this.getTheme().radius.lg)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TerminateSessionConfirmDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getTheme().colors.scrim)
        .onClick((): void => {
          this.terminateTarget = null;
        })

      Column() {
        Text(this.t('Terminate Session'))
          .fontSize(this.getTheme().typography.headline.fontSize)
          .fontWeight(this.getTheme().typography.headline.fontWeight)
          .fontColor(this.getTheme().colors.textPrimary)
          .margin({ bottom: this.getTheme().spacing.sm })

        Text(this.terminateTarget !== null
          ? `${this.terminateTarget.deviceModel} (${this.terminateTarget.applicationName})`
          : '')
          .fontSize(this.getTheme().typography.subheadline.fontSize)
          .fontWeight(this.getTheme().typography.headline.fontWeight)
          .fontColor(this.getTheme().colors.textPrimary)
          .margin({ bottom: this.getTheme().spacing.xs })

        Text(this.t('Are you sure you want to terminate this session?'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .textAlign(TextAlign.Center)
          .margin({ bottom: this.getTheme().spacing.lg })

        Row() {
          Button(this.t('Cancel'))
            .layoutWeight(1)
            .height(40)
            .margin({ right: this.getTheme().spacing.sm })
            .fontSize(this.getTheme().typography.body.fontSize)
            .fontColor(this.getTheme().colors.textPrimary)
            .backgroundColor(this.getTheme().colors.surfaceVariant)
            .borderRadius(this.getTheme().radius.md)
            .onClick((): void => {
              this.terminateTarget = null;
            })

          Button(this.t('Terminate'))
            .layoutWeight(1)
            .height(40)
            .margin({ left: this.getTheme().spacing.sm })
            .fontSize(this.getTheme().typography.body.fontSize)
            .fontColor(this.getTheme().colors.textOnAccent)
            .backgroundColor(this.getTheme().colors.destructive)
            .borderRadius(this.getTheme().radius.md)
            .onClick((): void => {
              if (this.terminateTarget !== null) {
                this.onDispatch(new TerminateSessionIntent(this.terminateTarget.id));
                this.terminateTarget = null;
              }
            })
        }
        .width('100%')
      }
      .width('82%')
      .padding(this.getTheme().spacing.lg)
      .backgroundColor(this.getTheme().colors.surface)
      .borderRadius(this.getTheme().radius.lg)
    }
    .width('100%')
    .height('100%')
  }
}
