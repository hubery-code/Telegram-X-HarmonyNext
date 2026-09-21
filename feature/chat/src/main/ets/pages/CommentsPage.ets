/**
 * feature/chat — 频道帖子评论列表页（CHANNEL-101 / FEAT-P2-002 / FEAT-P2-003）。
 *
 * 遵循 Telegram X 设计语言与 UI-002 / UI-004 视觉规范：
 * 1. 顶栏：Back 回退箭头 + 标题（评论数） + 副标题（频道名称）；
 * 2. 吸顶主帖卡片：展示被评论频道的原始帖子摘要、发送时间与重音指示条；
 * 3. 评论列表流：支持头像、发送者姓名、气泡正文、时间戳与发送态指示；
 * 4. 底部即时回复输入栏：圆角输入框 + 蓝底圆形发送按钮。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { CommentItem, CommentsCoordinator, CommentsUiState } from '../coordinator/CommentsCoordinator';


@Component
export struct CommentsPage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
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
            .fillColor(this.T.colors.textPrimary)
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
            .fontSize(this.T.typography.headline.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.T.colors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.uiState.channelTitle)
            .fontSize(this.T.typography.footnote.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: this.T.spacing.xs })
      }
      .width('100%')
      .height(56)
      .padding({ left: this.T.spacing.sm, right: this.T.spacing.md })
      .backgroundColor(this.T.colors.surface)
      .borderWidth({ bottom: 0.5 })
      .borderColor(this.T.colors.divider)

      // 2. 吸顶主帖摘要预览卡片
      Row() {
        // 左侧重音装饰竖条
        Column()
          .width(3)
          .height('100%')
          .backgroundColor(this.T.colors.accent)
          .borderRadius(this.T.radius.full)
          .margin({ right: this.T.spacing.sm })

        Column() {
          Row() {
            Text(this.uiState.channelTitle)
              .fontSize(this.T.typography.footnote.fontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.T.colors.accent)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            if (this.uiState.postDate.length > 0) {
              Text(this.uiState.postDate)
                .fontSize(this.T.typography.caption.fontSize)
                .fontColor(this.T.colors.textTertiary)
                .margin({ left: this.T.spacing.xs })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(this.uiState.postText.length > 0 ? this.uiState.postText : '原始帖子内容')
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: this.T.spacing.xs })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(this.T.spacing.md)
      .backgroundColor(this.T.colors.surfaceVariant)
      .borderWidth({ bottom: 1 })
      .borderColor(this.T.colors.divider)

      // 3. 评论流列表
      Stack({ alignContent: Alignment.Center }) {
        if (this.uiState.isLoading && this.uiState.comments.length === 0) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.T.colors.accent)
        } else if (!this.uiState.isLoading && this.uiState.comments.length === 0) {
          Column() {
            Image($r('app.media.ic_comments'))
              .width(48)
              .height(48)
              .fillColor(this.T.colors.textTertiary)
              .margin({ bottom: this.T.spacing.sm })

            Text('还没有评论，留下第一条评论吧')
              .fontSize(this.T.typography.footnote.fontSize)
              .fontColor(this.T.colors.textSecondary)
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
            left: this.T.spacing.md,
            right: this.T.spacing.md,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.T.colors.background)

      // 4. 底部评论输入栏
      Row() {
        TextInput({
          text: this.uiState.inputText,
          placeholder: '发表评论...'
        })
          .fontSize(this.T.typography.body.fontSize)
          .placeholderColor(this.T.colors.textTertiary)
          .fontColor(this.T.colors.textPrimary)
          .backgroundColor(this.T.colors.surfaceVariant)
          .borderRadius(this.T.radius.full)
          .height(40)
          .layoutWeight(1)
          .padding({ left: this.T.spacing.md, right: this.T.spacing.md })
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
              .color(this.T.colors.textOnAccent)
          } else {
            Image($r('app.media.ic_send'))
              .width(18)
              .height(18)
              .fillColor(this.T.colors.textOnAccent)
          }
        }
        .width(40)
        .height(40)
        .borderRadius(this.T.radius.full)
        .backgroundColor(this.uiState.inputText.trim().length > 0 ? this.T.colors.accent : this.T.colors.textTertiary)
        .margin({ left: this.T.spacing.sm })
        .onClick(() => {
          if (this.coordinator !== undefined) {
            this.coordinator.sendComment();
          }
        })
      }
      .width('100%')
      .padding({
        left: this.T.spacing.md,
        right: this.T.spacing.md,
        top: this.T.spacing.sm,
        bottom: this.T.spacing.sm
      })
      .backgroundColor(this.T.colors.surface)
      .borderWidth({ top: 0.5 })
      .borderColor(this.T.colors.divider)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }

  /** 单条评论气泡 */
  @Builder
  CommentBubble(item: CommentItem) {
    Row() {
      // 若为他人发出的评论，左侧展示头像
      if (!item.isOutgoing) {
        Stack({ alignContent: Alignment.Center }) {
          Text(item.senderAvatarLetter)
            .fontSize(this.T.typography.caption.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.T.colors.textOnAccent)
        }
        .width(36)
        .height(36)
        .borderRadius(18)
        .backgroundColor(item.senderAvatarColor)
        .margin({ right: this.T.spacing.sm })
      }

      // 气泡卡片
      Column() {
        if (!item.isOutgoing) {
          Text(item.senderName)
            .fontSize(this.T.typography.caption.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(item.senderAvatarColor)
            .margin({ bottom: 3 })
        }

        Text(item.text)
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)

        Row() {
          Text(item.dateText)
            .fontSize(10)
            .fontColor(this.T.colors.textTertiary)

          if (item.isOutgoing) {
            if (item.isSending) {
              Image($r('app.media.ic_clock'))
                .width(10)
                .height(10)
                .fillColor(this.T.colors.textTertiary)
                .margin({ left: 4 })
            } else {
              Image($r('app.media.ic_check_single'))
                .width(12)
                .height(12)
                .fillColor(this.T.colors.accent)
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
        left: this.T.spacing.md,
        right: this.T.spacing.md,
        top: this.T.spacing.sm,
        bottom: this.T.spacing.xs
      })
      .backgroundColor(item.isOutgoing ? this.T.colors.surfaceVariant : this.T.colors.surface)
      .borderRadius(this.T.radius.md)
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
