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

import { LightTheme } from '@tgx/core-design-system';
import { ForwardTarget, matchesForwardQuery } from '../model/ForwardTarget';

const T = LightTheme;

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
        Text('Cancel')
          .fontSize(T.typography.body.fontSize)
          .fontColor(T.colors.accent)
          .width(HEADER_BUTTON_WIDTH)
          .onClick(() => {
            this.onCancel();
          })

        Text('Forward to…')
          .fontSize(T.typography.title.fontSize)
          .fontWeight(T.typography.title.fontWeight)
          .fontColor(T.colors.textPrimary)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)

        // 占位：与左侧 Cancel 等宽，保证标题视觉居中
        Text('')
          .width(HEADER_BUTTON_WIDTH)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: T.spacing.sm,
        right: T.spacing.sm,
        top: T.spacing.sm,
        bottom: T.spacing.sm
      })
      .borderWidth({ bottom: 1 })
      .borderColor(T.colors.divider)

      // 搜索框：按标题过滤目标会话
      TextInput({ text: this.query, placeholder: 'Search' })
        .width('100%')
        .height(40)
        .fontSize(T.typography.body.fontSize)
        .backgroundColor(T.colors.surface)
        .borderRadius(T.radius.md)
        .margin({
          left: T.spacing.screenInset,
          right: T.spacing.screenInset,
          top: T.spacing.sm,
          bottom: T.spacing.sm
        })
        .onChange((value: string) => {
          this.query = value;
        })

      // "Send as copy" 开关（隐藏原发送者）
      Row() {
        Text(this.sendCopy ? '✓' : '')
          .width(CHECKBOX_SIZE)
          .height(CHECKBOX_SIZE)
          .borderRadius(T.radius.sm)
          .borderWidth(1)
          .borderColor(this.sendCopy ? T.colors.accent : T.colors.divider)
          .backgroundColor(this.sendCopy ? T.colors.accent : Color.Transparent)
          .fontColor(T.colors.textOnAccent)
          .fontSize(T.typography.footnote.fontSize)
          .textAlign(TextAlign.Center)
          .margin({ right: T.spacing.sm })

        Text('Send as copy')
          .fontSize(T.typography.body.fontSize)
          .fontColor(T.colors.textPrimary)
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: T.spacing.screenInset,
        right: T.spacing.screenInset,
        top: T.spacing.sm,
        bottom: T.spacing.sm
      })
      .onClick(() => {
        this.sendCopy = !this.sendCopy;
      })

      Divider()
        .color(T.colors.divider)

      // 目标会话列表
      if (this.filteredTargets().length === 0) {
        Column() {
          Text('No chats found')
            .fontSize(T.typography.body.fontSize)
            .fontColor(T.colors.textSecondary)
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
                    .borderRadius(T.radius.full)
                    .objectFit(ImageFit.Cover)
                    .margin({ right: T.spacing.sm })
                } else {
                  Text(target.avatarLetter)
                    .width(AVATAR_SIZE)
                    .height(AVATAR_SIZE)
                    .borderRadius(T.radius.full)
                    .backgroundColor(target.avatarColor)
                    .fontColor(T.colors.textOnAccent)
                    .fontSize(T.typography.subheadline.fontSize)
                    .textAlign(TextAlign.Center)
                    .margin({ right: T.spacing.sm })
                }

                Text(target.title)
                  .fontSize(T.typography.body.fontSize)
                  .fontColor(T.colors.textPrimary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .padding({
                left: T.spacing.screenInset,
                right: T.spacing.screenInset,
                top: T.spacing.sm,
                bottom: T.spacing.sm
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
    .backgroundColor(T.colors.background)
  }
}
