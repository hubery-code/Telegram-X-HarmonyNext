/**
 * feature/chat — 转发目标会话选择器（MSG-106 / FEAT-COMP-004）。
 *
 * 由装配层（entry）渲染：entry 同时持有会话列表数据（feature-chat-list 的
 * ChatListItem）与 ChatCoordinator，能把选择结果回灌 ChatIntent。本模块
 * （feature-chat）拿不到那个组合——feature/* 之间禁止互相依赖——所以选择器
 * 只认自己的窄视图模型 ForwardTarget[]，映射由 entry 完成。
 *
 * 结构对齐 Telegram X 的 ShareController（MODE_MESSAGES）：
 * - 顶部 Cancel + 标题；
 * - "Send as copy"（Android 文案 R.string.SendAsCopy）勾选后 sendCopy=true，
 *   转发时隐藏原发送者（TDLib forwardMessages 的 send_copy）；
 * - 目标会话列表（头像占位色 + 首字母 + 标题），可搜索过滤。
 *
 * 已知与 Android 的偏差：Android 仅当所选消息**全部** canBeCopied 时才出现
 * "Send as copy" 选项（ShareController:3316），本模块未逐条记录 canBeCopied
 * （长按只拉被按那条的 messageProperties），因此恒显示该开关；不可复制的
 * 内容由 TDLib 拒绝并经 OnForwardFailed 回灌错误提示。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { ForwardTarget, matchesForwardQuery } from '../model/ForwardTarget';


const AVATAR_SIZE: number = 44;
const CHECKBOX_SIZE: number = 22;
const HEADER_BUTTON_WIDTH: number = 72;

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
export struct ForwardPickerPage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @Prop targets: ForwardTarget[] = [];

  /** 选中目标会话：sendCopy=true 即以副本发送（隐藏原发送者）。 */
  onPick: (chatId: number, sendCopy: boolean) => void = () => {};

  onCancel: () => void = () => {};

  @State private query: string = '';
  @State private sendCopy: boolean = false;

  private filteredTargets(): ForwardTarget[] {
    const out: ForwardTarget[] = [];
    for (let i = 0; i < this.targets.length; i++) {
      const target: ForwardTarget = this.targets[i];
      if (matchesForwardQuery(target.title, this.query)) {
        out.push(target);
      }
    }
    return out;
  }

  build() {
    Column() {
      // 顶栏：Cancel + 标题（对齐 Telegram X 的 ShareController 头部）
      Row() {
        Row() {
          Image($r('app.media.ic_close'))
            .width(24)
            .height(24)
            .fillColor(this.T.colors.textPrimary)
        }
        .width(HEADER_BUTTON_WIDTH)
        .height(40)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onCancel();
        })

        Text('Forward to…')
          .fontSize(this.T.typography.title.fontSize)
          .fontWeight(this.T.typography.title.fontWeight)
          .fontColor(this.T.colors.textPrimary)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)

        // 占位：与左侧 Cancel 等宽，保证标题视觉居中
        Row()
          .width(HEADER_BUTTON_WIDTH)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: this.T.spacing.sm,
        right: this.T.spacing.sm,
        top: this.T.spacing.sm,
        bottom: this.T.spacing.sm
      })
      .borderWidth({ bottom: 1 })
      .borderColor(this.T.colors.divider)

      // 搜索框：按标题过滤目标会话
      TextInput({ text: this.query, placeholder: 'Search' })
        .width('100%')
        .height(40)
        .fontSize(this.T.typography.body.fontSize)
        .backgroundColor(this.T.colors.surface)
        .borderRadius(this.T.radius.md)
        .margin({
          left: this.T.spacing.screenInset,
          right: this.T.spacing.screenInset,
          top: this.T.spacing.sm,
          bottom: this.T.spacing.sm
        })
        .onChange((value: string) => {
          this.query = value;
        })

      // "Send as copy" 开关（隐藏原发送者）
      Row() {
        Row() {
          if (this.sendCopy) {
            Image($r('app.media.ic_check_single'))
              .width(14)
              .height(14)
              .fillColor(this.T.colors.textOnAccent)
          }
        }
        .width(CHECKBOX_SIZE)
        .height(CHECKBOX_SIZE)
        .borderRadius(this.T.radius.sm)
        .borderWidth(1)
        .borderColor(this.sendCopy ? this.T.colors.accent : this.T.colors.divider)
        .backgroundColor(this.sendCopy ? this.T.colors.accent : Color.Transparent)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ right: this.T.spacing.sm })

        Text('Send as copy')
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: this.T.spacing.screenInset,
        right: this.T.spacing.screenInset,
        top: this.T.spacing.sm,
        bottom: this.T.spacing.sm
      })
      .onClick(() => {
        this.sendCopy = !this.sendCopy;
      })

      Divider()
        .color(this.T.colors.divider)

      // 目标会话列表
      if (this.filteredTargets().length === 0) {
        Column() {
          Text('No chats found')
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.filteredTargets(), (target: ForwardTarget) => {
            ListItem() {
              Row() {
                if (target.avatarPath !== null && target.avatarPath.length > 0) {
                  Image(toSandboxUri(target.avatarPath))
                    .width(AVATAR_SIZE)
                    .height(AVATAR_SIZE)
                    .borderRadius(this.T.radius.full)
                    .objectFit(ImageFit.Cover)
                    .margin({ right: this.T.spacing.sm })
                } else {
                  Text(target.avatarLetter)
                    .width(AVATAR_SIZE)
                    .height(AVATAR_SIZE)
                    .borderRadius(this.T.radius.full)
                    .backgroundColor(target.avatarColor)
                    .fontColor(this.T.colors.textOnAccent)
                    .fontSize(this.T.typography.subheadline.fontSize)
                    .textAlign(TextAlign.Center)
                    .margin({ right: this.T.spacing.sm })
                }

                Text(target.title)
                  .fontSize(this.T.typography.body.fontSize)
                  .fontColor(this.T.colors.textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({
                left: this.T.spacing.screenInset,
                right: this.T.spacing.screenInset,
                top: this.T.spacing.sm,
                bottom: this.T.spacing.sm
              })
              .onClick(() => {
                this.onPick(target.chatId, this.sendCopy);
              })
            }
          }, (target: ForwardTarget) => `${target.chatId}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }
}
