/**
 * feature/chat_list — 抽屉导航面板（DRAWER-101）。
 *
 * TGX 形态：左侧滑出 ~72% 宽面板（全高），由 ChatListPage 的根 Stack
 * 叠加渲染（兄弟节点提供半透明 scrim，点击 scrim 关闭）。结构对齐 Android
 * DrawerController：
 *   头部 = 账号区（accent 色底）：圆形大头像（有路径用 Image + toSandboxUri，
 *          无则字母色底）、姓名（title）、手机（body）、右下 ⌄ 账号切换；
 *   菜单 = 联系人 / 通话 / 我的收藏 / 设置 / 邀请朋友 / 帮助
 *          （通话、邀请、帮助在 TGX 侧对应页面尚未迁移，先按 disabled 色）；
 *   底部 = 🌙 夜间模式开关（Toggle，checked=state.nightMode）。
 *
 * 纯 UI 组件：所有交互经回调上抛（onItem / onAccountClicked /
 * onNightModeChanged / onSwitchAccount），由 ChatListPage 转成 intent；
 * 状态只读 @Prop state（来自 uiState.drawer）。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { A11y, a11y } from '@tgx/core-common';
import { DrawerState, DrawerItemKey } from '../contract/DrawerState';


/** 头部大头像尺寸（vp）。 */
const DRAWER_AVATAR_SIZE: number = 64;
/** 菜单行图标占位宽（vp）。 */
const DRAWER_ICON_WIDTH: number = 32;
/** ⌄ 账号切换点击区尺寸（vp）。 */
const DRAWER_CHEVRON_SIZE: number = 40;

/** 菜单行描述（类构造，避开对象字面量显式类型问题）。 */
class DrawerMenuRow {
  readonly key: DrawerItemKey;
  readonly icon: Resource;
  readonly label: string;
  readonly enabled: boolean;

  constructor(key: DrawerItemKey, icon: Resource, label: string, enabled: boolean) {
    this.key = key;
    this.icon = icon;
    this.label = label;
    this.enabled = enabled;
  }
}

function toSandboxUri(path: string | null): string {
  if (path === null || path.length === 0) {
    return '';
  }
  if (path.startsWith('file://')) {
    return path;
  }
  return 'file://' + path;
}

@Component
export struct DrawerMenu {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @Prop state: DrawerState = DrawerState.empty();

  onItem: (item: DrawerItemKey) => void = () => {};
  onNightModeChanged: (on: boolean) => void = () => {};
  /** 由父级 scrim 消费（点击遮罩关闭抽屉）；面板自身不直接调用。 */
  onClose: () => void = () => {};
  onSwitchAccount: () => void = () => {};
  /** 点击账号头（头像/姓名区）→ 我的资料，对齐 TGX 点头像进自己资料页。 */
  onAccountClicked: () => void = () => {};

  /** 菜单项与顺序对齐 TGX DrawerController（enabled=false 先按 disabled 色展示）。 */
  private menuRows: DrawerMenuRow[] = [
    new DrawerMenuRow('contacts', $r('app.media.ic_contacts'), 'Contacts', true),
    new DrawerMenuRow('calls', $r('app.media.ic_call'), 'Calls', false),
    new DrawerMenuRow('saved', $r('app.media.ic_bookmark'), 'Saved Messages', true),
    new DrawerMenuRow('settings', $r('app.media.ic_settings'), 'Settings', true),
    new DrawerMenuRow('invite', $r('app.media.ic_person_add'), 'Invite Friends', false),
    new DrawerMenuRow('help', $r('app.media.ic_help'), 'Help', false)
  ];

  build() {
    Column() {
      // ===== 头部账号区（accent 底 + textOnAccent）=====
      Column() {
        Row() {
          if (this.state.accountAvatarPath !== null && this.state.accountAvatarPath.length > 0) {
            Image(toSandboxUri(this.state.accountAvatarPath))
              .width(DRAWER_AVATAR_SIZE)
              .height(DRAWER_AVATAR_SIZE)
              .borderRadius(this.T.radius.full)
              .objectFit(ImageFit.Cover)
          } else {
            Text(this.state.accountAvatarLetters)
              .width(DRAWER_AVATAR_SIZE)
              .height(DRAWER_AVATAR_SIZE)
              .borderRadius(this.T.radius.full)
              .backgroundColor(this.T.colors.accentPressed)
              .fontColor(this.T.colors.textOnAccent)
              .fontSize(this.T.typography.title.fontSize)
              .fontWeight(this.T.typography.title.fontWeight)
              .textAlign(TextAlign.Center)
          }

          Column() {
            Text(this.state.accountName)
              .fontSize(this.T.typography.title.fontSize)
              .fontWeight(this.T.typography.title.fontWeight)
              .fontColor(this.T.colors.textOnAccent)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Text(this.state.accountPhone)
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textOnAccent)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: this.T.spacing.xs })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: this.T.spacing.md })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // ⌄ 账号切换（TGX 位于头部右下）。
        Row() {
          Image($r('app.media.ic_chevron_down'))
            .width(DRAWER_CHEVRON_SIZE * 0.8)
            .height(DRAWER_CHEVRON_SIZE * 0.8)
            .fillColor(this.T.colors.textOnAccent)
            .accessibilityText(a11y(A11y.SWITCH_ACCOUNT))
            .onClick(() => {
              this.onSwitchAccount();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: this.T.spacing.xs })
      }
      .width('100%')
      .backgroundColor(this.T.colors.accent)
      .padding({
        left: this.T.spacing.screenInset,
        right: this.T.spacing.screenInset,
        top: this.T.spacing.lg,
        bottom: this.T.spacing.md
      })
      // DRAWER-101：点账号头进"我的资料"（⌄ 是子节点，命中仍在它自己身上）。
      .onClick(() => {
        this.onAccountClicked();
      })

      // ===== 菜单区 =====
      Column() {
        ForEach(this.menuRows.slice(), (row: DrawerMenuRow) => {
          Row() {
            Row() {
              Image(row.icon)
                .width(22)
                .height(22)
                .fillColor(row.enabled ? this.T.colors.textSecondary : this.T.colors.disabled)
            }
            .width(DRAWER_ICON_WIDTH)
            .justifyContent(FlexAlign.Start)

            Text(row.label)
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(row.enabled ? this.T.colors.textPrimary : this.T.colors.disabled)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            this.onItem(row.key);
          })
        }, (row: DrawerMenuRow) => row.key)
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Divider()
        .strokeWidth(1)
        .color(this.T.colors.divider)

      // ===== 底部：夜间模式开关 =====
      Row() {
        Row() {
          Image($r('app.media.ic_night'))
            .width(22)
            .height(22)
            .fillColor(this.T.colors.textSecondary)
        }
        .width(DRAWER_ICON_WIDTH)
        .justifyContent(FlexAlign.Start)

        Text('Night Mode')
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .layoutWeight(1)

        // 开关只做展示：点击命中交给下方整行 Row 统一处理。
        // 若此处同时绑 onChange，会与 Row 的 onClick 各切一次并互相抵消——
        // 日志表现为 "night mode changed: true" 紧跟 "false"，开关看起来没反应。
        Toggle({ type: ToggleType.Switch, isOn: this.state.nightMode })
          .selectedColor(this.T.colors.accent)
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: this.T.spacing.screenInset,
        right: this.T.spacing.screenInset,
        top: this.T.spacing.md,
        bottom: this.T.spacing.lg
      })
      .onClick(() => {
        this.onNightModeChanged(!this.state.nightMode);
      })
    }
    .width('72%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
    .alignItems(HorizontalAlign.Start)
    // DRAWER-101：挂载/卸载（父级 if showDrawer）时从左侧滑入/滑出。
    .transition(
      TransitionEffect.translate({ x: '-100%' })
        .animation({ duration: 200, curve: Curve.EaseOut })
    )
  }
}
