/**
 * feature/chat_list — 建群/建频道命名页（GROUP-CREATE-101）。
 *
 * 群/频道共用一段命名 UI，模式由 state.mode 区分：
 * - 标题输入（1-128 字，TextInput 层 maxLength 先拦，提交时 reducer 再校验）；
 * - 频道多一个可选简介输入（群模式不渲染）；
 * - 群模式显示已选成员数（成员选择在 feature/contact 的多选模式完成，
 *   userIds 由装配层经 GroupCreateStarted 带入，本页只读计数）；
 * - 内联错误条（errorMessageKey 存 Lang key，this.t 现取，切语言随重渲染）；
 * - 底部「创建」按钮：标题为空或请求在途时禁用。
 *
 * 提交经 onDispatch(GroupCreateSubmitRequested) 进 reducer——本地校验、
 * effect 产出与回包导航都在协调器/reducer 闭环（OnGroupChatCreated →
 * NavigateToChat），本页不做任何路由或请求。
 *
 * 本页由装配层挂载（groupCreate !== null 时才渲染），挂载/卸载与返回键
 * 拦截都是装配层的事；返回时装配层派发 GroupCreateCancelled 清流程态。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { A11y, a11y, Lang, SupportedLanguage } from '@tgx/core-common';
import { GroupCreateState } from '../contract/GroupCreateState';
import {
  ChatListIntent,
  GroupCreateSubmitRequested,
  GroupCreateTitleChanged,
  GroupCreateDescriptionChanged
} from '../contract/ChatListIntent';

/** 输入框高度（对齐 RegistrationPage 的表单形态）。 */
const NAMING_INPUT_HEIGHT: number = 48;

@Component
export struct GroupNamingPage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅（其余页同款口径）。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;

  /**
   * I18N-HOTSWITCH-101：语言 tick（同 ContactsPage/DrawerMenu 的口径），
   * 换语言会重渲染本页，文案永远按当前语言现取。
   */
  @StorageProp('activeLanguage') effectiveLanguage: string = 'en';

  /** 建群/建频道命名段状态（ChatListUiState.groupCreate）；null 时不渲染正文。 */
  @Prop createState: GroupCreateState | null = null;

  /** 派发意图到 ChatListCoordinator（创建/输入流都走这条）。 */
  onDispatch: (intent: ChatListIntent) => void = (): void => {};

  /** 返回（装配层负责派发 GroupCreateCancelled + 路由回退）。 */
  onBack: () => void = (): void => {};

  private t(key: string, ...args: (string | number)[]): string {
    const langCode: SupportedLanguage = this.effectiveLanguage === 'zh' ? 'zh' : 'en';
    return Lang.getInstance().formatByKey(key, langCode, args);
  }

  /** 「创建」可点性：标题 trim 后非空且请求不在途（reducer 会再校验一遍）。 */
  private canSubmit(): boolean {
    const state: GroupCreateState | null = this.createState;
    if (state === null || state.isSubmitting) {
      return false;
    }
    return state.title.trim().length > 0;
  }

  @Builder
  HeaderTitle() {
    Text(this.createState !== null && this.createState.mode === 'channel'
      ? this.t('New Channel')
      : this.t('New Group'))
      .fontSize(this.T.typography.title.fontSize)
      .fontWeight(this.T.typography.title.fontWeight)
      .fontColor(this.T.colors.textPrimary)
      .layoutWeight(1)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  ErrorBar() {
    // 空收窄在调用点自包含表达式（@Builder 体内不声明局部变量，ArkTS 编译红线）。
    Text(this.createState !== null && this.createState.errorMessageKey !== null
      ? this.t(this.createState.errorMessageKey)
      : '')
      .fontSize(this.T.typography.footnote.fontSize)
      .fontColor(this.T.colors.destructive)
      .visibility(this.createState !== null && this.createState.errorMessageKey !== null
        ? Visibility.Visible
        : Visibility.None)
      .margin({ top: this.T.spacing.sm })
  }

  build() {
    Column() {
      // ===== 头部：返回 + 标题 =====
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(this.T.colors.accent)
          .margin({ left: this.T.spacing.xs, right: this.T.spacing.md })
          .accessibilityText(a11y(A11y.BACK))
          .onClick(() => {
            this.onBack();
          })

        this.HeaderTitle()
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm })

      if (this.createState !== null) {
        Column() {
          // ===== 群模式：已选成员数（选择在联系人页多选模式完成）=====
          if (this.createState.mode === 'group') {
            Text(this.t('{0} members', this.createState.memberUserIds.length))
              .fontSize(this.T.typography.subheadline.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .margin({ bottom: this.T.spacing.md })
          }

          // ===== 标题输入（TextInput maxLength 先拦 128，reducer 提交时再校验）=====
          TextInput({
            text: this.createState.title,
            placeholder: this.createState.mode === 'channel'
              ? this.t('Enter channel name')
              : this.t('Enter group name')
          })
            .fontSize(this.T.typography.body.fontSize)
            .width('100%')
            .height(NAMING_INPUT_HEIGHT)
            .maxLength(128)
            .backgroundColor(this.T.colors.surfaceVariant)
            .border({
              width: 1,
              color: this.createState.errorMessageKey !== null
                ? this.T.colors.destructive
                : this.T.colors.border,
              radius: this.T.radius.md
            })
            .onChange((value: string) => {
              this.onDispatch(new GroupCreateTitleChanged(value));
            })

          this.ErrorBar()

          // ===== 频道：可选简介 =====
          if (this.createState.mode === 'channel') {
            TextInput({
              text: this.createState.description,
              placeholder: this.t('Description')
            })
              .fontSize(this.T.typography.body.fontSize)
              .width('100%')
              .height(NAMING_INPUT_HEIGHT)
              .backgroundColor(this.T.colors.surfaceVariant)
              .border({
                width: 1,
                color: this.T.colors.border,
                radius: this.T.radius.md
              })
              .margin({ top: this.T.spacing.md })
              .onChange((value: string) => {
                this.onDispatch(new GroupCreateDescriptionChanged(value));
              })
          }

          Blank()
            .layoutWeight(1)

          // ===== 创建按钮：标题空 / 在途禁用（本地校验在 reducer，双保险）=====
          Button(this.t('Create'))
            .width('60%')
            .height(44)
            .backgroundColor(this.T.colors.accent)
            .borderRadius(this.T.radius.full)
            .opacity(this.canSubmit() ? 1 : 0.5)
            .enabled(this.canSubmit())
            .onClick(() => {
              this.onDispatch(new GroupCreateSubmitRequested());
            })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({
          left: this.T.spacing.screenInset,
          right: this.T.spacing.screenInset,
          top: this.T.spacing.lg,
          bottom: this.T.spacing.xxl
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }
}
