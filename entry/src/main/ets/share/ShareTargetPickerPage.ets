/**
 * entry/src/main/ets/share/ShareTargetPickerPage.ets — 系统分享目标选择页（SHARE-EXT-101）。
 *
 * 形态对齐 feature/chat 的 ForwardPickerPage（MSG-106）：顶部 Cancel + 标题 +
 * 可搜索的目标会话列表。差异只有两点：标题是「分享到…」而不是「转发到…」，
 * 且没有「Send as copy」开关（分享的是外应用文本，不存在原发送者）。
 *
 * 由装配层（pages/Index）渲染与接管：entry 同时持有会话列表数据与 ChatCoordinator，
 * 能把选择结果落进既有发送链路（ComposerTextChanged + SendCurrentMessage）。
 * 目标行视图模型直接复用 feature-chat 的 ForwardTarget（公开导出，映射在 entry 完成）。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { A11y, a11y, Lang, SupportedLanguage } from '@tgx/core-common';
import { ForwardTarget, matchesForwardQuery } from '@tgx/feature-chat';

const AVATAR_SIZE: number = 44;
const HEADER_BUTTON_WIDTH: number = 72;
const PREVIEW_MAX_LINES: number = 4;

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
export struct ShareTargetPickerPage {
  /** 主题/语言 tick 的订阅形状与 ForwardPickerPage 一致（I18N-HOTSWITCH-101）。 */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @StorageProp('activeLanguage') effectiveLanguage: string = 'zh';

  @Prop targets: ForwardTarget[] = [];
  /** 待分享文本预览（来自系统分享面板）。 */
  @Prop sharedText: string = '';

  /** 选中目标会话：由装配层导航到该会话并立即发送 sharedText。 */
  onPick: (chatId: number) => void = () => {};

  /** 取消分享：只关面板，回到分享前的页面，不崩不外发。 */
  onCancel: () => void = () => {};

  @State private query: string = '';

  private t(key: string, ...args: (string | number)[]): string {
    const langCode: SupportedLanguage = this.effectiveLanguage === 'zh' ? 'zh' : 'en';
    return Lang.getInstance().formatByKey(key, langCode, args);
  }

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
      // 顶栏：Cancel + 标题（形状与 ForwardPickerPage 一致）
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
        .accessibilityText(a11y(A11y.CANCEL))
        .onClick(() => {
          this.onCancel();
        })

        Text(this.t('Share to…'))
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

      // 待分享文本预览：发送前让用户看见「即将发出去的是什么」
      if (this.sharedText.trim().length > 0) {
        Column() {
          Text(this.t('Shared content'))
            .fontSize(this.T.typography.footnote.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .margin({ bottom: this.T.spacing.xs })

          Text(this.sharedText)
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textPrimary)
            .maxLines(PREVIEW_MAX_LINES)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(this.T.spacing.md)
        .borderRadius(this.T.radius.md)
        .backgroundColor(this.T.colors.surface)
        .margin({
          left: this.T.spacing.screenInset,
          right: this.T.spacing.screenInset,
          top: this.T.spacing.sm
        })
      }

      // 搜索框：按标题过滤目标会话（与转发选择器同一条交互）
      TextInput({ text: this.query, placeholder: this.t('Search') })
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

      Divider()
        .color(this.T.colors.divider)

      // 目标会话列表
      if (this.filteredTargets().length === 0) {
        Column() {
          Text(this.t('No chats found'))
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
                    .accessibilityLevel('no')
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
                this.onPick(target.chatId);
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
