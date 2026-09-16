/**
 * feature/chat_list — 抽屉导航面板（DRAWER-101）。
 *
 * TGX 形态：左侧滑出 ~72% 宽面板（全高），由 ChatListPage 的根 Stack
 * 叠加渲染（兄弟节点提供半透明 scrim，点击 scrim 关闭）。结构对齐 Android
 * DrawerController：
 *   头部 = 账号区（accent 色底）：圆形大头像（有路径用 Image + toSandboxUri，
 *          无则字母色底）、姓名（title）、手机（body）、右下 ⌄ 账号切换；
 *   菜单 = 联系人 / 通话 / 我的收藏 / 设置 / 邀请朋友 / 帮助
 *          （联系人、设置可用 textPrimary；其余 TGX 尚未接线，先按 disabled 色）；
 *   底部 = 🌙 夜间模式开关（Toggle，checked=state.nightMode）。
 *
 * 纯 UI 组件：所有交互经回调上抛（onItem / onNightModeChanged /
 * onSwitchAccount），不经 reducer；状态只读 @Prop state。
 */

import { LightTheme } from '@tgx/core-design-system';
import { DrawerState, DrawerItemKey } from '../contract/DrawerState';

const T = LightTheme;

/** 头部大头像尺寸（vp）。 */
const DRAWER_AVATAR_SIZE: number = 64;
/** 菜单行图标占位宽（vp）。 */
const DRAWER_ICON_WIDTH: number = 32;
/** ⌄ 账号切换点击区尺寸（vp）。 */
const DRAWER_CHEVRON_SIZE: number = 40;

/** 菜单行描述（类构造，避开对象字面量显式类型问题）。 */
class DrawerMenuRow {
  readonly key: DrawerItemKey;
  readonly icon: string;
  readonly label: string;
  readonly enabled: boolean;

  constructor(key: DrawerItemKey, icon: string, label: string, enabled: boolean) {
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
  @Prop state: DrawerState = DrawerState.empty();

  onItem: (item: string) => void = () => {};
  onNightModeChanged: (on: boolean) => void = () => {};
  /** 由父级 scrim 消费（点击遮罩关闭抽屉）；面板自身不直接调用。 */
  onClose: () => void = () => {};
  onSwitchAccount: () => void = () => {};

  /** 菜单项与顺序对齐 TGX DrawerController（enabled=false 先按 disabled 色展示）。 */
  private menuRows: DrawerMenuRow[] = [
    new DrawerMenuRow('contacts', '👤', 'Contacts', true),
    new DrawerMenuRow('calls', '📞', 'Calls', false),
    new DrawerMenuRow('saved', '🔖', 'Saved Messages', false),
    new DrawerMenuRow('settings', '⚙', 'Settings', true),
    new DrawerMenuRow('invite', '👥', 'Invite Friends', false),
    new DrawerMenuRow('help', '❓', 'Help', false)
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
              .borderRadius(T.radius.full)
              .objectFit(ImageFit.Cover)
          } else {
            Text(this.state.accountAvatarLetters)
              .width(DRAWER_AVATAR_SIZE)
              .height(DRAWER_AVATAR_SIZE)
              .borderRadius(T.radius.full)
              .backgroundColor(T.colors.accentPressed)
              .fontColor(T.colors.textOnAccent)
              .fontSize(T.typography.title.fontSize)
              .fontWeight(T.typography.title.fontWeight)
              .textAlign(TextAlign.Center)
          }

          Column() {
            Text(this.state.accountName)
              .fontSize(T.typography.title.fontSize)
              .fontWeight(T.typography.title.fontWeight)
              .fontColor(T.colors.textOnAccent)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Text(this.state.accountPhone)
              .fontSize(T.typography.body.fontSize)
              .fontColor(T.colors.textOnAccent)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: T.spacing.xs })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: T.spacing.md })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // ⌄ 账号切换（TGX 位于头部右下）。
        Row() {
          Text('⌄')
            .fontSize(T.typography.title.fontSize)
            .fontColor(T.colors.textOnAccent)
            .width(DRAWER_CHEVRON_SIZE)
            .height(DRAWER_CHEVRON_SIZE)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.onSwitchAccount();
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: T.spacing.xs })
      }
      .width('100%')
      .backgroundColor(T.colors.accent)
      .padding({
        left: T.spacing.screenInset,
        right: T.spacing.screenInset,
        top: T.spacing.lg,
        bottom: T.spacing.md
      })

      // ===== 菜单区 =====
      Column() {
        ForEach(this.menuRows.slice(), (row: DrawerMenuRow) => {
          Row() {
            Text(row.icon)
              .fontSize(T.typography.body.fontSize)
              .width(DRAWER_ICON_WIDTH)
              .fontColor(row.enabled ? T.colors.textPrimary : T.colors.disabled)

            Text(row.label)
              .fontSize(T.typography.body.fontSize)
              .fontColor(row.enabled ? T.colors.textPrimary : T.colors.disabled)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: T.spacing.screenInset,
            right: T.spacing.screenInset,
            top: T.spacing.md,
            bottom: T.spacing.md
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
        .color(T.colors.divider)

      // ===== 底部：夜间模式开关 =====
      Row() {
        Text('🌙')
          .fontSize(T.typography.body.fontSize)
          .width(DRAWER_ICON_WIDTH)
          .fontColor(T.colors.textPrimary)

        Text('Night Mode')
          .fontSize(T.typography.body.fontSize)
          .fontColor(T.colors.textPrimary)
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.state.nightMode })
          .selectedColor(T.colors.accent)
          .onChange((isOn: boolean) => {
            this.onNightModeChanged(isOn);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: T.spacing.screenInset,
        right: T.spacing.screenInset,
        top: T.spacing.md,
        bottom: T.spacing.lg
      })
    }
    .width('72%')
    .height('100%')
    .backgroundColor(T.colors.background)
    .alignItems(HorizontalAlign.Start)
    // DRAWER-101：挂载/卸载（父级 if showDrawer）时从左侧滑入/滑出。
    .transition(
      TransitionEffect.translate({ x: '-100%' })
        .animation({ duration: 200, curve: Curve.EaseOut })
    )
  }
}
