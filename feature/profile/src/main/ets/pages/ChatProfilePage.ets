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

import { LightTheme, Theme } from '@tgx/core-design-system';
import { A11y, a11y } from '@tgx/core-common';
import { ChatProfileUiState, ChatMemberUiItem } from '../contract/ChatProfileUiState';
import {
  ChatProfileIntent,
  SelectChatMember,
  CopyInviteLinkRequested,
  BackRequested,
  OnSharedTabSelected,
  LoadMoreSharedContent,
  ToggleSharedAudio
} from '../contract/ChatProfileIntent';
import {
  sandboxFileUri,
  SharedContentSection,
  SharedContentViewData
} from '../components/SharedContentSection';
import { avatarColorOf } from '../model/SharedContentFormat';

const BACK_ARROW_SIZE: number = 44;
const AVATAR_SIZE: number = 96;
const MEMBER_AVATAR_SIZE: number = 44;

@Component
export struct ChatProfilePage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @Prop uiState: ChatProfileUiState = ChatProfileUiState.initial();
  onDispatch: (intent: ChatProfileIntent) => void = (): void => {};
  onBack: () => void = (): void => {};

  /**
   * 共享内容分区视图数据：本页五个内容 Tab —— 「共同群组」是私聊
   * 概念（getGroupsInCommon），群组/频道资料页没有它。
   */
  private sharedView(): SharedContentViewData {
    const s: ChatProfileUiState = this.uiState;
    return new SharedContentViewData({
      activeTab: s.activeSharedTab,
      loading: s.sharedLoading,
      loadingMore: s.sharedLoadingMore,
      hasMore: s.sharedHasMore,
      loadFailed: s.sharedLoadFailed,
      media: s.sharedMedia,
      files: s.sharedFiles,
      links: s.sharedLinks,
      audios: s.sharedAudios,
      voices: s.sharedVoices,
      playingFileId: s.sharedPlayingFileId,
      showGroupsTab: false
    });
  }

  @Builder
  Header() {
    Row() {
      Image($r('app.media.ic_back'))
        .width(24)
        .height(24)
        .fillColor(this.T.colors.accent)
        .margin({ left: this.T.spacing.xs, right: this.T.spacing.md })
      .accessibilityText(a11y(A11y.BACK))
        .onClick(() => {
          this.onBack();
        })

      Text(this.uiState.isChannel ? 'Channel Info' : 'Group Info')
        .fontSize(this.T.typography.title.fontSize)
        .fontWeight(this.T.typography.title.fontWeight)
        .fontColor(this.T.colors.textPrimary)
        .layoutWeight(1)

      Blank()
        .width(24)
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
    .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm })
    .backgroundColor(this.T.colors.background)
  }

  @Builder
  ChatHero() {
    Column() {
      if (this.uiState.photoPath !== null && this.uiState.photoPath.length > 0) {
        Image(sandboxFileUri(this.uiState.photoPath))
          .width(AVATAR_SIZE)
          .height(AVATAR_SIZE)
          .borderRadius(this.T.radius.full)
          .objectFit(ImageFit.Cover)
      } else {
        Text(this.uiState.avatarLetters.length > 0 ? this.uiState.avatarLetters : 'G')
          .width(AVATAR_SIZE)
          .height(AVATAR_SIZE)
          .borderRadius(this.T.radius.full)
          .backgroundColor(avatarColorOf(this.uiState.avatarColorIndex))
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFFFF')
          .textAlign(TextAlign.Center)
      }

      Text(this.uiState.title.length > 0 ? this.uiState.title : 'Loading...')
        .fontSize(this.T.typography.headline.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.T.colors.textPrimary)
        .margin({ top: this.T.spacing.md })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.uiState.memberCountText.length > 0) {
        Text(this.uiState.memberCountText)
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .margin({ top: this.T.spacing.xs })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: this.T.spacing.lg, bottom: this.T.spacing.lg })
    .backgroundColor(this.T.colors.background)
  }

  @Builder
  InfoCard() {
    Column() {
      if (this.uiState.description.length > 0) {
        Column() {
          Text('Description')
            .fontSize(this.T.typography.caption.fontSize)
            .fontColor(this.T.colors.accent)
            .fontWeight(FontWeight.Medium)
          Text(this.uiState.description)
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textPrimary)
            .margin({ top: this.T.spacing.xs })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: this.T.spacing.md,
          right: this.T.spacing.md,
          top: this.T.spacing.sm,
          bottom: this.T.spacing.sm
        })
      }

      if (this.uiState.inviteLink.length > 0) {
        Divider().color(this.T.colors.divider).strokeWidth(0.5)
        Row() {
          Column() {
            Text('Invite Link')
              .fontSize(this.T.typography.caption.fontSize)
              .fontColor(this.T.colors.accent)
              .fontWeight(FontWeight.Medium)
            Text(this.uiState.inviteLink)
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textPrimary)
              .margin({ top: this.T.spacing.xs })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Row({ space: this.T.spacing.xs }) {
            Image($r('app.media.ic_copy'))
              .width(16)
              .height(16)
              .fillColor(this.T.colors.accent)
            Text('Copy')
              .fontSize(this.T.typography.caption.fontSize)
              .fontColor(this.T.colors.accent)
              .fontWeight(FontWeight.Bold)
          }
          .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm, top: this.T.spacing.xs, bottom: this.T.spacing.xs })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({
          left: this.T.spacing.md,
          right: this.T.spacing.md,
          top: this.T.spacing.sm,
          bottom: this.T.spacing.sm
        })
        .onClick(() => {
          this.onDispatch(new CopyInviteLinkRequested());
        })
      }
    }
    .width('100%')
    .backgroundColor(this.T.colors.background)
    .margin({ top: this.T.spacing.xs })
  }

  @Builder
  MemberRow(member: ChatMemberUiItem) {
    Row() {
      if (member.avatarPath !== null && member.avatarPath.length > 0) {
        Image(sandboxFileUri(member.avatarPath))
          .width(MEMBER_AVATAR_SIZE)
          .height(MEMBER_AVATAR_SIZE)
          .borderRadius(this.T.radius.full)
          .objectFit(ImageFit.Cover)
      } else {
        Text(member.avatarLetters.length > 0 ? member.avatarLetters : '?')
          .width(MEMBER_AVATAR_SIZE)
          .height(MEMBER_AVATAR_SIZE)
          .borderRadius(this.T.radius.full)
          .backgroundColor(avatarColorOf(member.avatarColorIndex))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFFFF')
          .textAlign(TextAlign.Center)
      }

      Column() {
        Row() {
          Text(member.fullName.length > 0 ? member.fullName : 'User')
            .fontSize(this.T.typography.body.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.T.colors.textPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (member.role.length > 0) {
            Text(member.role)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.T.colors.accent)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#1A0088CC')
              .borderRadius(4)
              .margin({ left: this.T.spacing.xs })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(member.statusText.length > 0 ? member.statusText : (member.username ? `@${member.username}` : ''))
          .fontSize(this.T.typography.caption.fontSize)
          .fontColor(member.isOnline ? this.T.colors.accent : this.T.colors.textSecondary)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: this.T.spacing.md })
    }
    .width('100%')
    .height(60)
    .alignItems(VerticalAlign.Center)
    .padding({ left: this.T.spacing.md, right: this.T.spacing.md })
    .onClick(() => {
      this.onDispatch(new SelectChatMember(member.userId));
    })
  }

  @Builder
  MembersSection() {
    Column() {
      Row() {
        Text(`Members (${this.uiState.members.length})`)
          .fontSize(this.T.typography.caption.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.textSecondary)
      }
      .width('100%')
      .padding({ left: this.T.spacing.md, right: this.T.spacing.md, top: this.T.spacing.md, bottom: this.T.spacing.xs })

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
        color: this.T.colors.divider,
        startMargin: 72,
        endMargin: this.T.spacing.md
      })
    }
    .width('100%')
    .backgroundColor(this.T.colors.background)
    .margin({ top: this.T.spacing.xs })
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

          Divider()
            .color(this.T.colors.divider)
            .margin({ left: this.T.spacing.screenInset, right: this.T.spacing.screenInset })

          SharedContentSection({
            view: this.sharedView(),
            onSelectTab: (tab: number): void => {
              this.onDispatch(new OnSharedTabSelected(tab));
            },
            onLoadMore: (): void => {
              this.onDispatch(new LoadMoreSharedContent(this.uiState.activeSharedTab));
            },
            onToggleAudio: (fileId: number): void => {
              this.onDispatch(new ToggleSharedAudio(fileId));
            }
          })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .onScrollEdge((side: Edge) => {
        const v: SharedContentViewData = this.sharedView();
        if (side === Edge.Bottom && v.hasMore && !v.loadingMore && !v.loading) {
          this.onDispatch(new LoadMoreSharedContent(v.activeTab));
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.backgroundSecondary)
  }
}
