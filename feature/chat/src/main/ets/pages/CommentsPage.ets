/**
 * feature/chat — 频道帖子评论列表页（CHANNEL-101 / FEAT-P2-002 / FEAT-P2-003）。
 *
 * 遵循 Telegram X 设计语言与 UI-002 / UI-004 视觉规范：
 * 1. 顶栏：Back 回退箭头 + 标题（评论数） + 副标题（频道名称）；
 * 2. 吸顶主帖卡片：展示被评论频道的原始帖子摘要、发送时间与重音指示条；
 * 3. 评论列表流：支持头像、发送者姓名、气泡正文、时间戳与发送态指示；
 * 4. 底部即时回复输入栏：圆角输入框 + 蓝底圆形发送按钮。
 */

import { LightTheme } from '@tgx/core-design-system';
import { CommentItem, CommentsCoordinator, CommentsUiState } from '../coordinator/CommentsCoordinator';

const T = LightTheme;

@Component
export struct CommentsPage {
  @Prop uiState: CommentsUiState;
  coordinator?: CommentsCoordinator;
  onBack: () => void = () => {};

  build() {
    Column() {
      // 1. 顶栏导航区
      Row() {
        // 返回按钮
        Row() {
          Image($r('app.media.ic_back'))
            .width(24)
            .height(24)
            .fillColor(T.colors.textPrimary)
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onBack();
        })

        // 标题与副标题
        Column() {
          Text(this.uiState.commentsCount > 0 ? `评论 (${this.uiState.commentsCount})` : '评论')
            .fontSize(T.typography.headline.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(T.colors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.uiState.channelTitle)
            .fontSize(T.typography.footnote.fontSize)
            .fontColor(T.colors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: T.spacing.xs })
      }
      .width('100%')
      .height(56)
      .padding({ left: T.spacing.sm, right: T.spacing.md })
      .backgroundColor(T.colors.surface)
      .borderWidth({ bottom: 0.5 })
      .borderColor(T.colors.divider)

      // 2. 吸顶主帖摘要预览卡片
      Row() {
        // 左侧重音装饰竖条
        Column()
          .width(3)
          .height('100%')
          .backgroundColor(T.colors.accent)
          .borderRadius(T.radius.full)
          .margin({ right: T.spacing.sm })

        Column() {
          Row() {
            Text(this.uiState.channelTitle)
              .fontSize(T.typography.footnote.fontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(T.colors.accent)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            if (this.uiState.postDate.length > 0) {
              Text(this.uiState.postDate)
                .fontSize(T.typography.caption.fontSize)
                .fontColor(T.colors.textTertiary)
                .margin({ left: T.spacing.xs })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.uiState.postText.length > 0 ? this.uiState.postText : '原始帖子内容')
            .fontSize(T.typography.body.fontSize)
            .fontColor(T.colors.textPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: T.spacing.xs })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(T.spacing.md)
      .backgroundColor(T.colors.surfaceVariant)
      .borderWidth({ bottom: 1 })
      .borderColor(T.colors.divider)

      // 3. 评论流列表
      Stack({ alignContent: Alignment.Center }) {
        if (this.uiState.isLoading && this.uiState.comments.length === 0) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(T.colors.accent)
        } else if (!this.uiState.isLoading && this.uiState.comments.length === 0) {
          Column() {
            Image($r('app.media.ic_comments'))
              .width(48)
              .height(48)
              .fillColor(T.colors.textTertiary)
              .margin({ bottom: T.spacing.sm })

            Text('还没有评论，留下第一条评论吧')
              .fontSize(T.typography.footnote.fontSize)
              .fontColor(T.colors.textSecondary)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List({ space: 10 }) {
            ForEach(this.uiState.comments, (item: CommentItem) => {
              ListItem() {
                this.CommentBubble(item)
              }
              .width('100%')
            }, (item: CommentItem) => `${item.id}_${item.isSending}`)
          }
          .width('100%')
          .height('100%')
          .padding({
            left: T.spacing.md,
            right: T.spacing.md,
            top: T.spacing.md,
            bottom: T.spacing.md
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(T.colors.background)

      // 4. 底部评论输入栏
      Row() {
        TextInput({
          text: this.uiState.inputText,
          placeholder: '发表评论...'
        })
          .fontSize(T.typography.body.fontSize)
          .placeholderColor(T.colors.textTertiary)
          .fontColor(T.colors.textPrimary)
          .backgroundColor(T.colors.surfaceVariant)
          .borderRadius(T.radius.full)
          .height(40)
          .layoutWeight(1)
          .padding({ left: T.spacing.md, right: T.spacing.md })
          .onChange((value: string) => {
            if (this.coordinator !== undefined) {
              this.coordinator.setInputText(value);
            }
          })
          .onSubmit(() => {
            if (this.coordinator !== undefined) {
              this.coordinator.sendComment();
            }
          })

        Stack({ alignContent: Alignment.Center }) {
          if (this.uiState.isSending) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(T.colors.textOnAccent)
          } else {
            Image($r('app.media.ic_send'))
              .width(18)
              .height(18)
              .fillColor(T.colors.textOnAccent)
          }
        }
        .width(40)
        .height(40)
        .borderRadius(T.radius.full)
        .backgroundColor(this.uiState.inputText.trim().length > 0 ? T.colors.accent : T.colors.textTertiary)
        .margin({ left: T.spacing.sm })
        .onClick(() => {
          if (this.coordinator !== undefined) {
            this.coordinator.sendComment();
          }
        })
      }
      .width('100%')
      .padding({
        left: T.spacing.md,
        right: T.spacing.md,
        top: T.spacing.sm,
        bottom: T.spacing.sm
      })
      .backgroundColor(T.colors.surface)
      .borderWidth({ top: 0.5 })
      .borderColor(T.colors.divider)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(T.colors.background)
  }

  /** 单条评论气泡 */
  @Builder
  CommentBubble(item: CommentItem) {
    Row() {
      // 若为他人发出的评论，左侧展示头像
      if (!item.isOutgoing) {
        Stack({ alignContent: Alignment.Center }) {
          Text(item.senderAvatarLetter)
            .fontSize(T.typography.caption.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(T.colors.textOnAccent)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(item.senderAvatarColor)
        .margin({ right: T.spacing.sm })
      }

      // 气泡卡片
      Column() {
        if (!item.isOutgoing) {
          Text(item.senderName)
            .fontSize(T.typography.caption.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(item.senderAvatarColor)
            .margin({ bottom: 3 })
        }

        Text(item.text)
          .fontSize(T.typography.body.fontSize)
          .fontColor(T.colors.textPrimary)

        Row() {
          Text(item.dateText)
            .fontSize(10)
            .fontColor(T.colors.textTertiary)

          if (item.isOutgoing) {
            if (item.isSending) {
              Image($r('app.media.ic_clock'))
                .width(10)
                .height(10)
                .fillColor(T.colors.textTertiary)
                .margin({ left: 4 })
            } else {
              Image($r('app.media.ic_check_single'))
                .width(12)
                .height(12)
                .fillColor(T.colors.accent)
                .margin({ left: 4 })
            }
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 3 })
      }
      .padding({
        left: T.spacing.md,
        right: T.spacing.md,
        top: T.spacing.sm,
        bottom: T.spacing.xs
      })
      .backgroundColor(item.isOutgoing ? T.colors.surfaceVariant : T.colors.surface)
      .borderRadius(T.radius.md)
      .constraintSize({ minWidth: 80, maxWidth: 280 })
      .shadow({
        radius: 2,
        color: 'rgba(0, 0, 0, 0.04)',
        offsetY: 1
      })
    }
    .width('100%')
    .justifyContent(item.isOutgoing ? FlexAlign.End : FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
  }
}
