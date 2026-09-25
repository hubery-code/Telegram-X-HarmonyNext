/**
 * entry/src/main/ets/deeplink/AppLinkPromptView.ets — 链接确认弹窗的视图（DEEPLINK-102）。
 *
 * 只认 `PromptCard`（已经翻译好的三段文案 + 两/三个按钮），不认识「邀请」「代理」这些业务概念：
 * 构卡的纯函数在 `AppLinkPrompt.ets` 里，视图这边零分支，也就不会出现「新加一类链接忘了加按钮」。
 *
 * 为什么挂在 entry 而不是某个 feature：弹窗可能盖在任何页面之上（冷启动深链落在 home、
 * 气泡里的链接在 chat），而 entry 是唯一的路由与装配所有者。视觉口径抄的
 * `ProxySubPage.DeleteConfirmDialog`（scrim + 82% 卡片），保持全工程一种弹窗。
 */

import { Theme, LightTheme } from '@tgx/core-design-system';
import { EMPTY_PROMPT_CARD, PromptCard } from './AppLinkPrompt';

@Component
export struct AppLinkPromptLayer {
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @Prop card: PromptCard = EMPTY_PROMPT_CARD;
  readonly onPrimary: () => void = (): void => {};
  readonly onSecondary: () => void = (): void => {};
  readonly onCancel: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.T.colors.scrim)
        .onClick((): void => {
          this.onCancel();
        })

      Column() {
        Text(this.card.title)
          .fontSize(this.T.typography.title.fontSize)
          .fontWeight(this.T.typography.title.fontWeight)
          .fontColor(this.T.colors.textPrimary)
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.card.body.length > 0) {
          Text(this.card.body)
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .textAlign(TextAlign.Center)
            .margin({ top: this.T.spacing.sm })
        }

        if (this.card.footnote.length > 0) {
          Text(this.card.footnote)
            .fontSize(this.T.typography.caption.fontSize)
            .fontColor(this.T.colors.textTertiary)
            .textAlign(TextAlign.Center)
            .margin({ top: this.T.spacing.sm })
        }

        Button(this.card.primaryLabel)
          .width('100%')
          .height(44)
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textOnAccent)
          .backgroundColor(this.T.colors.accent)
          .borderRadius(this.T.radius.md)
          .margin({ top: this.T.spacing.lg })
          .onClick((): void => {
            this.onPrimary();
          })

        if (this.card.secondaryLabel.length > 0) {
          Button(this.card.secondaryLabel)
            .width('100%')
            .height(44)
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textPrimary)
            .backgroundColor(this.T.colors.surfaceVariant)
            .borderRadius(this.T.radius.md)
            .margin({ top: this.T.spacing.sm })
            .onClick((): void => {
              this.onSecondary();
            })
        }

        Button(this.card.cancelLabel)
          .width('100%')
          .height(44)
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .backgroundColor(Color.Transparent)
          .borderRadius(this.T.radius.md)
          .margin({ top: this.T.spacing.xs })
          .onClick((): void => {
            this.onCancel();
          })
      }
      .width('82%')
      .padding(this.T.spacing.lg)
      .backgroundColor(this.T.colors.surface)
      .borderRadius(this.T.radius.lg)
    }
    .width('100%')
    .height('100%')
  }
}
