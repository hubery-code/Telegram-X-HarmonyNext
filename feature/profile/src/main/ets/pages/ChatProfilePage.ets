/**
 * feature/profile — 群组/频道资料页 ArkUI 组件（PROFILE-102）。
 *
 * 对齐 Telegram-X ProfileController.Args(chat) 视觉规范：
 * - 顶栏：返回键 + Group / Channel Info 标题；
 * - 封面区：大圆形群头像（图片或首字母彩底）+ 群名称 + 成员/订阅数副标题；
 * - 信息卡片：群描述、邀请链接（点击复制）；
 * - 成员列表区：展示首屏群成员，每行含头像、昵称、在线状态、Owner/Admin 角标，点击跳转用户资料页；
 * - 100% 遵从 Design Tokens。
 */

import { LightTheme } from '@tgx/core-design-system';
import { fileUri } from '@kit.CoreFileKit';
import { ChatProfileUiState, ChatMemberUiItem } from '../contract/ChatProfileUiState';
import {
  ChatProfileIntent,
  SelectChatMember,
  CopyInviteLinkRequested,
  BackRequested
} from '../contract/ChatProfileIntent';

const T = LightTheme;

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

const AVATAR_PALETTE: string[] = [
  '#FFCC5049', '#FFD67722', '#FF955CDB', '#FF40A920',
  '#FF309EBA', '#FF368AD1', '#FFC7508B'
];

const BACK_ARROW_SIZE: number = 44;
const AVATAR_SIZE: number = 96;
const MEMBER_AVATAR_SIZE: number = 44;

@Component
export struct ChatProfilePage {
  @Prop uiState: ChatProfileUiState = ChatProfileUiState.initial();
  onDispatch: (intent: ChatProfileIntent) => void = (): void => {};
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
      Image($r('app.media.ic_back'))
        .width(24)
        .height(24)
        .fillColor(T.colors.accent)
        .margin({ left: T.spacing.xs, right: T.spacing.md })
        .onClick(() => {
          this.onBack();
        })

      Text(this.uiState.isChannel ? 'Channel Info' : 'Group Info')
        .fontSize(T.typography.title.fontSize)
        .fontWeight(T.typography.title.fontWeight)
        .fontColor(T.colors.textPrimary)
        .layoutWeight(1)

      Blank()
        .width(24)
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
    .padding({ left: T.spacing.sm, right: T.spacing.sm })
    .backgroundColor(T.colors.background)
  }

  @Builder
  ChatHero() {
    Column() {
      if (this.uiState.photoPath !== null && this.uiState.photoPath.length > 0) {
        Image(toSandboxUri(this.uiState.photoPath))
          .width(AVATAR_SIZE)
          .height(AVATAR_SIZE)
          .borderRadius(T.radius.full)
          .objectFit(ImageFit.Cover)
      } else {
        Text(this.uiState.avatarLetters.length > 0 ? this.uiState.avatarLetters : 'G')
          .width(AVATAR_SIZE)
          .height(AVATAR_SIZE)
          .borderRadius(T.radius.full)
          .backgroundColor(this.avatarColor(this.uiState.avatarColorIndex))
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFFFF')
          .textAlign(TextAlign.Center)
      }

      Text(this.uiState.title.length > 0 ? this.uiState.title : 'Loading...')
        .fontSize(T.typography.headline.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(T.colors.textPrimary)
        .margin({ top: T.spacing.md })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.uiState.memberCountText.length > 0) {
        Text(this.uiState.memberCountText)
          .fontSize(T.typography.body.fontSize)
          .fontColor(T.colors.textSecondary)
          .margin({ top: T.spacing.xs })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: T.spacing.lg, bottom: T.spacing.lg })
    .backgroundColor(T.colors.background)
  }

  @Builder
  InfoCard() {
    Column() {
      if (this.uiState.description.length > 0) {
        Column() {
          Text('Description')
            .fontSize(T.typography.caption.fontSize)
            .fontColor(T.colors.accent)
            .fontWeight(FontWeight.Medium)
          Text(this.uiState.description)
            .fontSize(T.typography.body.fontSize)
            .fontColor(T.colors.textPrimary)
            .margin({ top: T.spacing.xs })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: T.spacing.md,
          right: T.spacing.md,
          top: T.spacing.sm,
          bottom: T.spacing.sm
        })
      }

      if (this.uiState.inviteLink.length > 0) {
        Divider().color(T.colors.divider).strokeWidth(0.5)
        Row() {
          Column() {
            Text('Invite Link')
              .fontSize(T.typography.caption.fontSize)
              .fontColor(T.colors.accent)
              .fontWeight(FontWeight.Medium)
            Text(this.uiState.inviteLink)
              .fontSize(T.typography.body.fontSize)
              .fontColor(T.colors.textPrimary)
              .margin({ top: T.spacing.xs })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Row({ space: T.spacing.xs }) {
            Image($r('app.media.ic_copy'))
              .width(16)
              .height(16)
              .fillColor(T.colors.accent)
            Text('Copy')
              .fontSize(T.typography.caption.fontSize)
              .fontColor(T.colors.accent)
              .fontWeight(FontWeight.Bold)
          }
          .padding({ left: T.spacing.sm, right: T.spacing.sm, top: T.spacing.xs, bottom: T.spacing.xs })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({
          left: T.spacing.md,
          right: T.spacing.md,
          top: T.spacing.sm,
          bottom: T.spacing.sm
        })
        .onClick(() => {
          this.onDispatch(new CopyInviteLinkRequested());
        })
      }
    }
    .width('100%')
    .backgroundColor(T.colors.background)
    .margin({ top: T.spacing.xs })
  }

  @Builder
  MemberRow(member: ChatMemberUiItem) {
    Row() {
      if (member.avatarPath !== null && member.avatarPath.length > 0) {
        Image(toSandboxUri(member.avatarPath))
          .width(MEMBER_AVATAR_SIZE)
          .height(MEMBER_AVATAR_SIZE)
          .borderRadius(T.radius.full)
          .objectFit(ImageFit.Cover)
      } else {
        Text(member.avatarLetters.length > 0 ? member.avatarLetters : '?')
          .width(MEMBER_AVATAR_SIZE)
          .height(MEMBER_AVATAR_SIZE)
          .borderRadius(T.radius.full)
          .backgroundColor(this.avatarColor(member.avatarColorIndex))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFFFF')
          .textAlign(TextAlign.Center)
      }

      Column() {
        Row() {
          Text(member.fullName.length > 0 ? member.fullName : 'User')
            .fontSize(T.typography.body.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(T.colors.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (member.role.length > 0) {
            Text(member.role)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(T.colors.accent)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#1A0088CC')
              .borderRadius(4)
              .margin({ left: T.spacing.xs })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(member.statusText.length > 0 ? member.statusText : (member.username ? `@${member.username}` : ''))
          .fontSize(T.typography.caption.fontSize)
          .fontColor(member.isOnline ? T.colors.accent : T.colors.textSecondary)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: T.spacing.md })
    }
    .width('100%')
    .height(60)
    .alignItems(VerticalAlign.Center)
    .padding({ left: T.spacing.md, right: T.spacing.md })
    .onClick(() => {
      this.onDispatch(new SelectChatMember(member.userId));
    })
  }

  @Builder
  MembersSection() {
    Column() {
      Row() {
        Text(`Members (${this.uiState.members.length})`)
          .fontSize(T.typography.caption.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(T.colors.textSecondary)
      }
      .width('100%')
      .padding({ left: T.spacing.md, right: T.spacing.md, top: T.spacing.md, bottom: T.spacing.xs })

      List() {
        ForEach(this.uiState.members, (member: ChatMemberUiItem) => {
          ListItem() {
            this.MemberRow(member)
          }
        }, (member: ChatMemberUiItem): string => `${member.userId}_${member.role}_${member.isOnline}`)
      }
      .width('100%')
      .divider({
        strokeWidth: 0.5,
        color: T.colors.divider,
        startMargin: 72,
        endMargin: T.spacing.md
      })
    }
    .width('100%')
    .backgroundColor(T.colors.background)
    .margin({ top: T.spacing.xs })
  }

  build() {
    Column() {
      this.Header()

      Scroll() {
        Column() {
          this.ChatHero()
          this.InfoCard()
          if (this.uiState.members.length > 0) {
            this.MembersSection()
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(T.colors.backgroundSecondary)
  }
}
