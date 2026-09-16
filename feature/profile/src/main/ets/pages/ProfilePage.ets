/**
 * feature/profile — 用户资料页（PROFILE-101）。
 *
 * 对齐 Android ProfileController 的信息面（查看他人资料的 MVP）：
 * 大头像 + 展示名 + 在线状态 + @username + 手机号 + 简介 + 「发消息」入口。
 * 共享媒体、举报/拉黑等动作留后续工作包。
 *
 * 全部颜色/间距/字号走 design tokens（core-design-system）。
 */

import { LightTheme } from '@tgx/core-design-system';
import { fileUri } from '@kit.CoreFileKit';
import { ProfileUiState } from '../contract/ProfileUiState';
import { ProfileIntent, MessageUserRequested } from '../contract/ProfileIntent';

const T = LightTheme;

/** 本地沙箱绝对路径 → 可渲染 uri（与 feature/chat、feature/chat_list 的同名助手一致）。 */
function toSandboxUri(path: string | null): string {
  if (path === null || path.length === 0) {
    return '';
  }
  if (path.startsWith('file://')) {
    return path;
  }
  const normalized: string = path.startsWith('/') ? path : '/' + path;
  try {
    return fileUri.getUriFromPath(normalized);
  } catch (_e) {
    return 'file://org.telegram.x.harmony' + normalized;
  }
}

/** Telegram 经典头像调色板（0..6），与 feature/chat 的 AVATAR_PALETTE 同色值。 */
const AVATAR_PALETTE: string[] = [
  '#FFCC5049', '#FFD67722', '#FF955CDB', '#FF40A920',
  '#FF309EBA', '#FF368AD1', '#FFC7508B'
];

const BACK_ARROW_SIZE: number = 44;
const AVATAR_SIZE: number = 96;
const MESSAGE_BUTTON_HEIGHT: number = 44;

@Component
export struct ProfilePage {
  @Prop uiState: ProfileUiState = ProfileUiState.initial();
  onDispatch: (intent: ProfileIntent) => void = (): void => {};
  onBack: () => void = (): void => {};

  private avatarColor(index: number): string {
    if (index < 0 || index >= AVATAR_PALETTE.length) {
      return AVATAR_PALETTE[0];
    }
    return AVATAR_PALETTE[index];
  }

  @Builder
  Header() {
    Row() {
      Text('‹')
        .fontSize(T.typography.title.fontSize)
        .fontWeight(T.typography.title.fontWeight)
        .fontColor(T.colors.accent)
        .width(BACK_ARROW_SIZE)
        .height(BACK_ARROW_SIZE)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onBack();
        })

      Text('User Info')
        .fontSize(T.typography.title.fontSize)
        .fontWeight(T.typography.title.fontWeight)
        .fontColor(T.colors.textPrimary)
        .layoutWeight(1)

      Text('')
        .width(BACK_ARROW_SIZE)
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
    .padding({ left: T.spacing.sm, right: T.spacing.sm })
    .backgroundColor(T.colors.background)
  }

  @Builder
  Avatar() {
    if (this.uiState.avatarPath !== null && this.uiState.avatarPath.length > 0) {
      Image(toSandboxUri(this.uiState.avatarPath))
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(T.radius.full)
        .objectFit(ImageFit.Cover)
    } else {
      Text(this.uiState.avatarLetters.length > 0 ? this.uiState.avatarLetters : '?')
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(T.radius.full)
        .backgroundColor(this.avatarColor(this.uiState.avatarColorIndex))
        .fontColor(T.colors.textOnAccent)
        .fontSize(36)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
    }
  }

  @Builder
  InfoRow(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(T.typography.footnote.fontSize)
        .fontColor(T.colors.textSecondary)
      Text(value)
        .fontSize(T.typography.body.fontSize)
        .fontColor(T.colors.textPrimary)
        .margin({ top: T.spacing.hairline })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: T.spacing.screenInset,
      right: T.spacing.screenInset,
      top: T.spacing.sm,
      bottom: T.spacing.sm
    })
  }

  build() {
    Column() {
      this.Header()

      if (this.uiState.isLoading && this.uiState.displayName.length === 0) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(T.colors.accent)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.uiState.errorMessage !== null && this.uiState.displayName.length === 0) {
        Column() {
          Text(this.uiState.errorMessage)
            .fontSize(T.typography.body.fontSize)
            .fontColor(T.colors.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column() {
            Column() {
              this.Avatar()

              Text(this.uiState.displayName.length > 0 ? this.uiState.displayName : 'Unknown')
                .fontSize(T.typography.largeTitle.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(T.colors.textPrimary)
                .margin({ top: T.spacing.md })
                .textAlign(TextAlign.Center)

              if (this.uiState.statusText.length > 0) {
                Text(this.uiState.statusText)
                  .fontSize(T.typography.subheadline.fontSize)
                  .fontColor(this.uiState.statusText === 'online'
                    ? T.colors.accent
                    : T.colors.textSecondary)
                  .margin({ top: T.spacing.xs })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: T.spacing.lg, bottom: T.spacing.md })

            Divider()
              .color(T.colors.divider)
              .margin({ left: T.spacing.screenInset, right: T.spacing.screenInset })

            if (this.uiState.username.length > 0) {
              this.InfoRow('Username', `@${this.uiState.username}`)
            }
            if (this.uiState.phone.length > 0) {
              this.InfoRow('Phone', this.uiState.phone)
            }
            if (this.uiState.bio.length > 0) {
              this.InfoRow('Bio', this.uiState.bio)
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Button('Message')
          .width('100%')
          .height(MESSAGE_BUTTON_HEIGHT)
          .fontSize(T.typography.body.fontSize)
          .fontColor(T.colors.textOnAccent)
          .backgroundColor(T.colors.accent)
          .borderRadius(T.radius.md)
          .margin({
            left: T.spacing.screenInset,
            right: T.spacing.screenInset,
            top: T.spacing.sm,
            bottom: T.spacing.md
          })
          .onClick(() => {
            this.onDispatch(new MessageUserRequested());
          })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(T.colors.background)
  }
}
