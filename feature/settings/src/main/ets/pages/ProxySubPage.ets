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
 * feature/settings — 「代理」子页（PROXY-101 / FEAT-P2-007 代理部分，
 * PROXY-102 补连通性探测与连接态）。
 *
 * 对齐 Telegram X 的 Proxies 页：单选列表（首行「不使用代理」）+ 添加/编辑表单 +
 * 删除二次确认 + 每行一句「通不通、多久通」。这里刻意不做的还是 TGX 那两件：
 * 「自动切换」（要路由选择器，会替用户改代理）与「通话走代理」（本端没有 VoIP 通话）。
 *
 * 表单态（输入框内容、工作表开合）留在组件内：它是页面私有的草稿，不该进 UiState；
 * 但「保存成功」这件事只有 UiState 知道，故用 saveInFlight + updatingProxyId 的
 * 归位作为关闭工作表的信号，失败时保持打开、原样留着用户输入。
 */

import { Theme, ThemeManager, LightTheme } from '@tgx/core-design-system';
import { A11y, a11y, Lang, SupportedLanguage } from '@tgx/core-common';
import { SettingsUiState } from '../contract/SettingsUiState';
import {
  LoadProxies,
  RemoveProxyRequested,
  SaveProxy,
  SelectProxy,
  SetErrorMessage,
  SettingsIntent
} from '../contract/SettingsIntent';
import {
  PROXY_NEW_ID,
  PROXY_NONE_ID,
  ProxyForm,
  ProxyItem,
  ProxyKind,
  ProxyStatus,
  proxyAddress,
  proxyEnabledItem,
  proxyFailureOf,
  proxyFormError,
  proxyFormFromItem,
  proxyFormHasCredentials,
  proxyKindLabel,
  proxyPingOf,
  proxyPingSuffix,
  proxyRowIsEffective,
  proxyStatusOf,
  proxyTitle
} from '../model/ProxySettings';

const PROXY_KINDS: ProxyKind[] = ['socks5', 'http', 'mtproto'];

@Component
export struct ProxySubPage {
  @Prop @Watch('onUiStateChanged') uiState: SettingsUiState = SettingsUiState.initial();
  onDispatch: (intent: SettingsIntent) => void = (): void => {};
  onBack: () => void = (): void => {};

  @State private effectiveTheme: Theme = LightTheme;
  @State private effectiveLang: SupportedLanguage = 'en';

  /** 表单草稿：全部页面局部，关闭子页即弃。 */
  @State private formOpen: boolean = false;
  @State private formId: number = PROXY_NEW_ID;
  @State private formKind: ProxyKind = 'socks5';
  @State private formServer: string = '';
  @State private formPort: string = '';
  @State private formUsername: string = '';
  @State private formPassword: string = '';
  @State private formSecret: string = '';
  @State private formHttpOnly: boolean = false;
  @State private formComment: string = '';
  @State private formEnable: boolean = true;
  /** 用户改过任一字段后才提示校验结果，一进表单不是一片红。 */
  @State private formTouched: boolean = false;
  @State private deleteTarget: ProxyItem | null = null;

  private saveInFlight: boolean = false;
  private unsubscribeTheme: (() => void) | null = null;
  private unsubscribeLang: (() => void) | null = null;

  aboutToAppear(): void {
    this.updateEffectiveTheme();
    this.effectiveLang = Lang.getInstance().getLanguage();
    const self: ProxySubPage = this;
    this.unsubscribeTheme = ThemeManager.getInstance().subscribe((_theme: Theme): void => {
      self.updateEffectiveTheme();
    });
    this.unsubscribeLang = Lang.getInstance().subscribe((lang: SupportedLanguage): void => {
      self.effectiveLang = lang;
    });
    this.onDispatch(new LoadProxies());
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
    this.closeFormWhenWritten();
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
   * PROXY-102 状态句：连通性探测（`pingProxy`）与 TDLib 连接态合成的一句话，
   * 判定全在 `proxyStatusOf` 里。'' 表示这一句不说，副标题退回「类型 / 地址」。
   *
   * PROXY-103：那句「出错」后面跟一个括号里的原因 —— 只可能是本端分类出来的句子，
   * 不可能是 TDLib 原文（原文进日志）。Android 印的是 `Error (code: message)`，
   * 括号形状照它，内容换成我们自己看得懂、也翻得动的话。
   */
  private statusText(item: ProxyItem | null): string {
    const proxyId: number = item === null ? PROXY_NONE_ID : item.id;
    const pingMs: number = proxyPingOf(this.uiState.proxyPingMs, proxyId);
    const status: ProxyStatus = proxyStatusOf(
      item,
      pingMs,
      proxyRowIsEffective(this.uiState.proxyItems, item),
      this.uiState.proxyConnection,
      proxyFailureOf(this.uiState.proxyPingFailure, proxyId)
    );
    if (status.key.length === 0) {
      return '';
    }
    const text: string = this.t(status.key);
    if (status.failureKey.length === 0) {
      return text + proxyPingSuffix(status.pingMs);
    }
    return `${text} (${this.t(status.failureKey)})` + proxyPingSuffix(status.pingMs);
  }

  /**
   * 行的副标题。有状态可说时是「类型 · 状态」（TGX 那一行同样是「名字 + 状态值」，
   * 备注行因此不展示地址 —— 点铅笔进表单就能看到）；没状态可说时保持 PROXY-101 的原样。
   */
  private rowSubtitle(item: ProxyItem): string {
    const kind: string = this.t(proxyKindLabel(item.kind));
    const status: string = this.statusText(item);
    if (status.length === 0) {
      return item.comment.trim().length > 0 ? proxyAddress(item) : kind;
    }
    return `${kind} · ${status}`;
  }

  /**
   * 写回落地（updatingProxyId 归位）才关工作表；失败时 UiState 带着 errorMessage，
   * 此时保持打开，用户不必重打一遍服务器地址。
   */
  private closeFormWhenWritten(): void {
    if (!this.saveInFlight) {
      return;
    }
    if (this.uiState.errorMessage !== null) {
      this.saveInFlight = false;
      return;
    }
    if (this.uiState.updatingProxyId === null) {
      this.saveInFlight = false;
      this.formOpen = false;
    }
  }

  /** 「不使用代理」那一行的状态句；'' 时不渲染副标题。 */
  private noneRowStatus(): string {
    return this.statusText(null);
  }

  private currentForm(): ProxyForm {
    return new ProxyForm(
      this.formId, this.formKind, this.formServer, this.formPort, this.formUsername,
      this.formPassword, this.formSecret, this.formHttpOnly, this.formComment, this.formEnable
    );
  }

  private isFormValid(): boolean {
    return proxyFormError(this.currentForm()).length === 0;
  }

  private formErrorText(): string {
    const key: string = proxyFormError(this.currentForm());
    return key.length === 0 ? '' : this.t(key);
  }

  private isBusy(): boolean {
    return this.uiState.updatingProxyId !== null;
  }

  /**
   * ArkUI 在 TextInput 挂载时就会用初值回调一次 onChange，直接置位会让刚打开的
   * 空表单顶着一行红字；只有输入过非空内容才算「碰过」。
   */
  private markTouched(value: string): void {
    if (value.length > 0) {
      this.formTouched = true;
    }
  }

  private openAddForm(): void {
    this.formId = PROXY_NEW_ID;
    this.formKind = 'socks5';
    this.formServer = '';
    this.formPort = '';
    this.formUsername = '';
    this.formPassword = '';
    this.formSecret = '';
    this.formHttpOnly = false;
    this.formComment = '';
    this.formEnable = true;
    this.formTouched = false;
    this.formOpen = true;
  }

  private openEditForm(item: ProxyItem): void {
    const form: ProxyForm = proxyFormFromItem(item);
    this.formId = form.id;
    this.formKind = form.kind;
    this.formServer = form.server;
    this.formPort = form.portInput;
    this.formUsername = form.username;
    this.formPassword = form.password;
    this.formSecret = form.secret;
    this.formHttpOnly = form.httpOnly;
    this.formComment = form.comment;
    this.formEnable = form.enable;
    this.formTouched = false;
    this.formOpen = true;
  }

  private submitForm(): void {
    if (!this.isFormValid() || this.isBusy()) {
      return;
    }
    this.saveInFlight = true;
    this.onDispatch(new SaveProxy(this.currentForm()));
  }

  /** 「不使用代理」这一行是否处于选中态：列表里没有任何启用项。 */
  private isNoneSelected(): boolean {
    return proxyEnabledItem(this.uiState.proxyItems) === null;
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

            if (this.uiState.isLoadingProxies && this.uiState.proxyItems.length === 0) {
              this.LoadingRowView()
            } else {
              this.ProxyCardView()
              this.HintView()
              this.AddProxyButtonView()
            }
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

      if (this.formOpen) {
        this.ProxyFormSheet()
      }

      if (this.deleteTarget !== null) {
        this.DeleteConfirmDialog()
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

      Text(this.t('Proxies'))
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
        .backgroundColor(this.getTheme().colors.surfaceVariant)
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
  ProxyCardView() {
    Column() {
      // 单选列表的首项恒在：没有代理也要能显式回到「不用代理」。
      // 圆点直接内联：@Builder 的按值入参不参与状态观察，抽成 Radio(selected) 会点完不变。
      Row() {
        Stack() {
          if (this.isNoneSelected()) {
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
          color: this.isNoneSelected()
            ? this.getTheme().colors.accent
            : this.getTheme().colors.textSecondary
        })

        Column() {
          Text(this.t('Do Not Use Proxy'))
            .fontSize(this.getTheme().typography.body.fontSize)
            .fontColor(this.getTheme().colors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 直连探测有结果才多一行；没结果时这一行和 PROXY-101 时一样干净。
          if (this.noneRowStatus().length > 0) {
            Text(this.noneRowStatus())
              .fontSize(this.getTheme().typography.footnote.fontSize)
              .fontColor(this.getTheme().colors.textSecondary)
              .margin({ top: this.getTheme().spacing.hairline })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.uiState.updatingProxyId === 0) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.getTheme().colors.accent)
        }
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.onDispatch(new SelectProxy(PROXY_NONE_ID));
      })

      ForEach(this.uiState.proxyItems, (item: ProxyItem, index: number) => {
        Column() {
          Divider()
            .color(this.getTheme().colors.divider)
            .margin({ left: this.getTheme().spacing.xl })

          Row() {
            Stack() {
              if (item.isEnabled) {
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
              color: item.isEnabled
                ? this.getTheme().colors.accent
                : this.getTheme().colors.textSecondary
            })

            Column() {
              Text(proxyTitle(item))
                .fontSize(this.getTheme().typography.body.fontSize)
                .fontColor(this.getTheme().colors.textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(this.rowSubtitle(item))
                .fontSize(this.getTheme().typography.footnote.fontSize)
                .fontColor(this.getTheme().colors.textSecondary)
                .margin({ top: this.getTheme().spacing.hairline })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.uiState.updatingProxyId === item.id) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color(this.getTheme().colors.accent)
                .margin({ right: this.getTheme().spacing.sm })
            }

            Image($r('app.media.ic_edit'))
              .width(20)
              .height(20)
              .fillColor(this.getTheme().colors.textSecondary)
              .margin({ right: this.getTheme().spacing.md })
            .accessibilityText(a11y(A11y.EDIT))
              .onClick((): void => {
                this.openEditForm(item);
              })

            Image($r('app.media.ic_delete'))
              .width(20)
              .height(20)
              .fillColor(this.getTheme().colors.destructive)
            .accessibilityText(a11y(A11y.DELETE))
              .onClick((): void => {
                this.deleteTarget = item;
              })
          }
          .width('100%')
          .padding({ top: this.getTheme().spacing.sm, bottom: this.getTheme().spacing.sm })
          .alignItems(VerticalAlign.Center)
          .onClick((): void => {
            this.onDispatch(new SelectProxy(item.id));
          })
        }
        .width('100%')
      }, (item: ProxyItem): string =>
        // 探测结果与连接态不在 ProxyItem 上（列表每次写回都整批重建行），所以键要自己带上，
        // 否则 ArkUI 按键复用节点、那一行的状态句会停在旧文案。
        `${item.id}|${item.isEnabled}|${item.comment}|${item.server}` +
        `|${proxyPingOf(this.uiState.proxyPingMs, item.id)}|${this.uiState.proxyConnection}` +
        `|${proxyFailureOf(this.uiState.proxyPingFailure, item.id)}`)
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
  HintView() {
    Text(this.uiState.proxyItems.length === 0
      ? this.t('No proxies set up yet. Tap Add Proxy below.')
      : this.t('Tap a proxy to route Telegram through it.'))
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
  AddProxyButtonView() {
    Row() {
      Image($r('app.media.ic_add'))
        .width(18)
        .height(18)
        .fillColor(this.getTheme().colors.accent)
        .margin({ right: this.getTheme().spacing.xs })

      Text(this.t('Add Proxy'))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontWeight(this.getTheme().typography.headline.fontWeight)
        .fontColor(this.getTheme().colors.accent)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .margin({ top: this.getTheme().spacing.lg })
    .onClick((): void => {
      this.openAddForm();
    })
  }

  @Builder
  ProxyFormSheet() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getTheme().colors.scrim)
        .onClick((): void => {
          this.formOpen = false;
        })

      Scroll() {
        Column() {
          Row() {
            Text(this.formId === PROXY_NEW_ID ? this.t('Add Proxy') : this.t('Edit Proxy'))
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
                this.formOpen = false;
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ bottom: this.getTheme().spacing.md })

          Text(this.t('Proxy Type'))
            .fontSize(this.getTheme().typography.footnote.fontSize)
            .fontColor(this.getTheme().colors.textSecondary)
            .margin({ bottom: this.getTheme().spacing.xs })
            .width('100%')

          Row() {
            ForEach(PROXY_KINDS, (kind: ProxyKind) => {
              this.KindOption(kind)
            })
          }
          .width('100%')
          .margin({ bottom: this.getTheme().spacing.md })

          this.FieldLabel('Server Address')
          this.ServerInput()
          this.FieldLabel('Port')
          this.PortInput()

          if (proxyFormHasCredentials(this.formKind)) {
            this.FieldLabel('Username')
            this.UsernameInput()
            this.FieldLabel('Password')
            this.PasswordInput()
          }

          if (this.formKind === 'http') {
            this.HttpOnlyRow()
          }

          if (this.formKind === 'mtproto') {
            this.FieldLabel('Secret (hex)')
            this.SecretInput()
          }

          this.FieldLabel('Comment')
          this.CommentInput()

          this.EnableNowRow()

          if (this.formTouched && this.formErrorText().length > 0) {
            Text(this.formErrorText())
              .fontSize(this.getTheme().typography.footnote.fontSize)
              .fontColor(this.getTheme().colors.destructive)
              .margin({ top: this.getTheme().spacing.sm })
              .width('100%')
          }

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
                this.formOpen = false;
              })

            Button(this.formId === PROXY_NEW_ID ? this.t('Add Proxy') : this.t('Save'))
              .layoutWeight(1)
              .height(40)
              .margin({ left: this.getTheme().spacing.sm })
              .fontSize(this.getTheme().typography.body.fontSize)
              .fontColor(this.getTheme().colors.textOnAccent)
              .backgroundColor(this.getTheme().colors.accent)
              .borderRadius(this.getTheme().radius.md)
              .enabled(this.isFormValid() && !this.isBusy())
              .onClick((): void => {
                this.submitForm();
              })
          }
          .width('100%')
          .margin({ top: this.getTheme().spacing.lg })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(this.getTheme().spacing.lg)
      }
      .width('100%')
      .constraintSize({ maxHeight: '78%' })
      .scrollBar(BarState.Off)
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
  KindOption(kind: ProxyKind) {
    Button(this.t(proxyKindLabel(kind)))
      .layoutWeight(1)
      .height(36)
      .margin({
        left: kind === PROXY_KINDS[0] ? 0 : this.getTheme().spacing.xs,
        right: kind === PROXY_KINDS[2] ? 0 : this.getTheme().spacing.xs
      })
      .fontSize(this.getTheme().typography.subheadline.fontSize)
      .fontColor(this.formKind === kind
        ? this.getTheme().colors.textOnAccent
        : this.getTheme().colors.textPrimary)
      .backgroundColor(this.formKind === kind
        ? this.getTheme().colors.accent
        : this.getTheme().colors.surfaceVariant)
      .borderRadius(this.getTheme().radius.md)
      .onClick((): void => {
        this.formKind = kind;
        this.formTouched = true;
      })
  }

  @Builder
  FieldLabel(labelKey: string) {
    Text(this.t(labelKey))
      .fontSize(this.getTheme().typography.footnote.fontSize)
      .fontColor(this.getTheme().colors.textSecondary)
      .margin({ top: this.getTheme().spacing.sm, bottom: this.getTheme().spacing.xs })
      .width('100%')
  }

  @Builder
  ServerInput() {
    TextInput({ text: this.formServer, placeholder: 'proxy.example.com' })
      .fontSize(this.getTheme().typography.body.fontSize)
      .fontColor(this.getTheme().colors.textPrimary)
      .placeholderColor(this.getTheme().colors.textTertiary)
      .backgroundColor(this.getTheme().colors.surfaceVariant)
      .borderRadius(this.getTheme().radius.md)
      .height(44)
      .width('100%')
      .onChange((value: string): void => {
        this.formServer = value;
        this.markTouched(value);
      })
  }

  @Builder
  PortInput() {
    TextInput({ text: this.formPort, placeholder: '1080' })
      .type(InputType.Number)
      .fontSize(this.getTheme().typography.body.fontSize)
      .fontColor(this.getTheme().colors.textPrimary)
      .placeholderColor(this.getTheme().colors.textTertiary)
      .backgroundColor(this.getTheme().colors.surfaceVariant)
      .borderRadius(this.getTheme().radius.md)
      .height(44)
      .width('100%')
      .onChange((value: string): void => {
        this.formPort = value;
        this.markTouched(value);
      })
  }

  @Builder
  UsernameInput() {
    TextInput({ text: this.formUsername, placeholder: this.t('Optional') })
      .fontSize(this.getTheme().typography.body.fontSize)
      .fontColor(this.getTheme().colors.textPrimary)
      .placeholderColor(this.getTheme().colors.textTertiary)
      .backgroundColor(this.getTheme().colors.surfaceVariant)
      .borderRadius(this.getTheme().radius.md)
      .height(44)
      .width('100%')
      .onChange((value: string): void => {
        this.formUsername = value;
        this.markTouched(value);
      })
  }

  @Builder
  PasswordInput() {
    TextInput({ text: this.formPassword, placeholder: this.t('Optional') })
      .type(InputType.Password)
      .fontSize(this.getTheme().typography.body.fontSize)
      .fontColor(this.getTheme().colors.textPrimary)
      .placeholderColor(this.getTheme().colors.textTertiary)
      .backgroundColor(this.getTheme().colors.surfaceVariant)
      .borderRadius(this.getTheme().radius.md)
      .height(44)
      .width('100%')
      .onChange((value: string): void => {
        this.formPassword = value;
        this.markTouched(value);
      })
  }

  @Builder
  SecretInput() {
    TextInput({ text: this.formSecret, placeholder: 'ee…' })
      .fontSize(this.getTheme().typography.body.fontSize)
      .fontColor(this.getTheme().colors.textPrimary)
      .placeholderColor(this.getTheme().colors.textTertiary)
      .backgroundColor(this.getTheme().colors.surfaceVariant)
      .borderRadius(this.getTheme().radius.md)
      .height(44)
      .width('100%')
      .onChange((value: string): void => {
        this.formSecret = value;
        this.markTouched(value);
      })
  }

  @Builder
  CommentInput() {
    TextInput({ text: this.formComment, placeholder: this.t('Optional') })
      .fontSize(this.getTheme().typography.body.fontSize)
      .fontColor(this.getTheme().colors.textPrimary)
      .placeholderColor(this.getTheme().colors.textTertiary)
      .backgroundColor(this.getTheme().colors.surfaceVariant)
      .borderRadius(this.getTheme().radius.md)
      .height(44)
      .width('100%')
      .onChange((value: string): void => {
        this.formComment = value;
        this.markTouched(value);
      })
  }

  @Builder
  HttpOnlyRow() {
    Row() {
      Text(this.t('HTTP Only'))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.formHttpOnly })
        .onChange((isOn: boolean): void => {
          this.formHttpOnly = isOn;
        })
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
    .margin({ top: this.getTheme().spacing.sm })
  }

  @Builder
  EnableNowRow() {
    Row() {
      Column() {
        Text(this.t('Enable Proxy'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontColor(this.getTheme().colors.textPrimary)

        Text(this.t('Route Telegram traffic through this proxy now.'))
          .fontSize(this.getTheme().typography.caption.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .margin({ top: this.getTheme().spacing.hairline })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.formEnable })
        .onChange((isOn: boolean): void => {
          this.formEnable = isOn;
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: this.getTheme().spacing.md })
  }

  @Builder
  DeleteConfirmDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getTheme().colors.scrim)
        .onClick((): void => {
          this.deleteTarget = null;
        })

      Column() {
        Text(this.t('Remove proxy'))
          .fontSize(this.getTheme().typography.title.fontSize)
          .fontWeight(this.getTheme().typography.title.fontWeight)
          .fontColor(this.getTheme().colors.textPrimary)
          .margin({ bottom: this.getTheme().spacing.sm })

        Text(this.t('Delete this proxy configuration?'))
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
              this.deleteTarget = null;
            })

          Button(this.t('Delete'))
            .layoutWeight(1)
            .height(40)
            .margin({ left: this.getTheme().spacing.sm })
            .fontSize(this.getTheme().typography.body.fontSize)
            .fontColor(this.getTheme().colors.textOnAccent)
            .backgroundColor(this.getTheme().colors.destructive)
            .borderRadius(this.getTheme().radius.md)
            .onClick((): void => {
              const target: ProxyItem | null = this.deleteTarget;
              if (target === null) {
                return;
              }
              this.deleteTarget = null;
              this.onDispatch(new RemoveProxyRequested(target.id));
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
