/**
 * feature/profile — 用户资料页（PROFILE-101；PROFILE-103 增强）。
 *
 * 对齐 Android ProfileController 的信息面：
 * 封面大图头部（头像全出血 + 遮罩上的展示名/在线状态）+ @username + 手机号 +
 * 简介 + 生日 + 通知 + ⋮ 动作菜单 + 下半页共享内容六 Tab（媒体/文件/链接/音乐/语音/群组）。
 *
 * 集成契约保持三 prop：uiState / onDispatch / onBack（entry 装配不变）。
 * 全部颜色/间距/字号走 design tokens（core-design-system）。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { ProfileUiState } from '../contract/ProfileUiState';
import {
  ProfileIntent,
  MessageUserRequested,
  OnSharedTabSelected,
  LoadMoreSharedContent,
  OpenSharedChatRequested,
  ToggleSharedAudio,
  NotificationRowTapped,
  ProfileMenuAction,
  PROFILE_MENU_SECRET_CHAT,
  PROFILE_MENU_TOGGLE_BLOCK
} from '../contract/ProfileIntent';
import {
  sandboxFileUri,
  SharedContentSection,
  SharedContentViewData
} from '../components/SharedContentSection';
import { avatarColorOf } from '../model/SharedContentFormat';

/**
 * 封面头部尺寸，对齐 Android ProfileController/Size.java：
 * 展开态头部 234dp（头像铺满），收起态只剩 56dp 工具条。
 */
const TOOLBAR_HEIGHT: number = 56;
const COVER_HEIGHT: number = 234;
const COVER_LETTER_SIZE: number = 90;
const MESSAGE_BUTTON_HEIGHT: number = 44;

/**
 * ⋮ 菜单只保留真实动作（见 menuElements）。此前这里的「分享联系人 / 隐私例外 /
 * 重命名联系人 / 删除联系人」都是只打 hilog 的假入口（TDLib 侧没有对应写路径），
 * 留着等于在真菜单里挂死按钮，故整体删除。
 */
@Component
export struct ProfilePage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @Prop uiState: ProfileUiState = ProfileUiState.initial();
  onDispatch: (intent: ProfileIntent) => void = (): void => {};
  onBack: () => void = (): void => {};

  /**
   * 封面是否已滚过工具条。工具条压在封面之上（Android 同款全出血头部），
   * 滚过临界点后换成实心底 + 主题色图标。只在布尔值真的变化时写 @State，
   * 避免 onDidScroll 每帧触发整页重排。
   */
  @State private coverScrolled: boolean = false;
  private scroller: Scroller = new Scroller();

  /** 封面底图：profile_photo.big 落地路径可用才画照片，否则画调色板纯色+字母。 */
  private hasCover(): boolean {
    return this.uiState.avatarPath !== null && this.uiState.avatarPath.length > 0;
  }

  /** 封面滚过临界点的位移量：照片高度减去工具条高度。 */
  private coverCollapseOffset(): number {
    return COVER_HEIGHT - TOOLBAR_HEIGHT;
  }

  private headerIconColor(): string {
    return this.headerOverCover() ? this.T.colors.textOnScrim : this.T.colors.icon;
  }

  /**
   * 工具条是否压在封面上。加载/错误占位页没有封面，此时工具条必须回到实心底 +
   * 主题色图标，否则白色图标会消失在白底上。
   */
  private isPlaceholderScreen(): boolean {
    return this.uiState.displayName.length === 0
      && (this.uiState.isLoading || this.uiState.errorMessage !== null);
  }

  private headerOverCover(): boolean {
    return !this.coverScrolled && !this.isPlaceholderScreen();
  }

  /** 本页 UiState → 共享内容分区视图数据（分区组件不认 ProfileUiState）。 */
  private sharedView(): SharedContentViewData {
    const s: ProfileUiState = this.uiState;
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
      groups: s.sharedGroups,
      playingFileId: s.sharedPlayingFileId,
      showGroupsTab: true
    });
  }

  /**
   * ⋮ 菜单：三项全部落到 TDLib。
   * 屏蔽项文案跟着真值走；真值未读到时标「未读取」，点击由 reducer no-op。
   */
  private menuElements(): MenuElement[] {
    const items: MenuElement[] = [];
    items.push({
      value: '发送消息',
      action: (): void => {
        this.onDispatch(new MessageUserRequested());
      }
    });
    items.push({
      value: '开启密聊',
      action: (): void => {
        this.onDispatch(new ProfileMenuAction(PROFILE_MENU_SECRET_CHAT));
      }
    });
    let blockLabel: string = '屏蔽用户';
    if (!this.uiState.peerBlockReady) {
      blockLabel = '屏蔽用户（未读取）';
    } else if (this.uiState.peerBlocked) {
      blockLabel = '取消屏蔽';
    }
    items.push({
      value: blockLabel,
      action: (): void => {
        this.onDispatch(new ProfileMenuAction(PROFILE_MENU_TOGGLE_BLOCK));
      }
    });
    return items;
  }

  @Builder
  Header() {
    Row() {
      Image($r('app.media.ic_back'))
        .width(24)
        .height(24)
        .fillColor(this.headerIconColor())
        .margin({ left: this.T.spacing.xs, right: this.T.spacing.md })
        .onClick(() => {
          this.onBack();
        })

      Text(this.uiState.displayName.length > 0 ? this.uiState.displayName : 'User Info')
        .fontSize(this.T.typography.title.fontSize)
        .fontWeight(this.T.typography.title.fontWeight)
        .fontColor(this.T.colors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .opacity(this.headerOverCover() ? 0 : 1)

      Image($r('app.media.ic_more_vert'))
        .width(24)
        .height(24)
        .fillColor(this.headerIconColor())
        .margin({ right: this.T.spacing.xs })
        .bindMenu(this.menuElements())
    }
    .width('100%')
    .height(TOOLBAR_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm })
    .backgroundColor(this.headerOverCover() ? Color.Transparent : this.T.colors.background)
    .animation({ duration: this.T.motion.durationFast })
  }

  /**
   * 封面大图头部（PROFILE-103 收尾项）。
   *
   * Android 侧的「封面」并不是独立壁纸图，而是把头像放大到全出血（ProfileController
   * setHeaderPhoto → AvatarReceiver.requestPhoto(profilePhoto.big)）：
   * 有照片时照片铺满 + 底部黑色渐变遮罩，名字/状态压在遮罩上（白色）；
   * 无照片时按 Telegram 惯例用调色板纯色底 + 大号字母，不加遮罩。
   */
  @Builder
  Cover() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.hasCover()) {
        Image(sandboxFileUri(this.uiState.avatarPath))
          .width('100%')
          .height(COVER_HEIGHT)
          .objectFit(ImageFit.Cover)

        // 上下两道遮罩合成一层：Android ComplexHeaderView 只在拿到真照片时画
        // topShadow(0x77000000) + bottomShadow(0x66000000)。顶部那道是为了让工具条的
        // 白色返回/⋮ 图标压在浅色照片上仍然可读。
        Column()
          .width('100%')
          .height(COVER_HEIGHT)
          .linearGradient({
            angle: 180,
            colors: [
              [this.T.colors.scrim, 0],
              [Color.Transparent, 0.45],
              [Color.Transparent, 0.6],
              [this.T.colors.scrim, 1]
            ]
          })
      } else {
        Column() {
          Text(this.uiState.avatarLetters.length > 0 ? this.uiState.avatarLetters : '?')
            .fontSize(COVER_LETTER_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.T.colors.textOnScrim)
        }
        .width('100%')
        .height(COVER_HEIGHT)
        .backgroundColor(avatarColorOf(this.uiState.avatarColorIndex))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      Column() {
        Text(this.uiState.displayName.length > 0 ? this.uiState.displayName : 'Unknown')
          .fontSize(this.T.typography.largeTitle.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.textOnScrim)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.uiState.emojiStatusEmoji.length > 0) {
          Text(this.uiState.emojiStatusEmoji)
            .fontSize(this.T.typography.subheadline.fontSize)
            .margin({ top: this.T.spacing.hairline })
        }

        if (this.uiState.statusText.length > 0) {
          Text(this.uiState.statusText)
            .fontSize(this.T.typography.subheadline.fontSize)
            .fontColor(this.uiState.statusText === 'online'
              ? this.T.colors.accent
              : this.T.colors.textOnScrim)
            .opacity(this.uiState.statusText === 'online' ? 1 : 0.85)
            .margin({ top: this.T.spacing.hairline })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: this.T.spacing.screenInset,
        right: this.T.spacing.screenInset,
        bottom: this.T.spacing.md
      })
    }
    .width('100%')
    .height(COVER_HEIGHT)
  }

  @Builder
  InfoRow(icon: Resource, label: string, value: string) {
    Row() {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.T.colors.textSecondary)
        .margin({ right: this.T.spacing.md })

      Column() {
        Text(label)
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.textSecondary)
        Text(value)
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .margin({ top: this.T.spacing.hairline })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.sm,
      bottom: this.T.spacing.sm
    })
  }

  /** 通知行文案：真值未回读前不写死「开启」，写请求在途时显示省略号。 */
  private notificationLabel(): string {
    if (this.uiState.notificationUpdating) {
      return '…';
    }
    if (!this.uiState.notificationReady) {
      return '—';
    }
    return this.uiState.notificationMuted ? '静音' : '开启';
  }

  /** PROFILE-103 收尾：通知行（🔔 通知 / 真实静音态，点按切换）。 */
  @Builder
  NotificationRow() {
    Row() {
      Image($r('app.media.ic_notifications'))
        .width(22)
        .height(22)
        .fillColor(this.T.colors.textSecondary)
      Text('通知')
        .fontSize(this.T.typography.body.fontSize)
        .fontColor(this.T.colors.textPrimary)
        .margin({ left: this.T.spacing.sm })
        .layoutWeight(1)
      Text(this.notificationLabel())
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.textSecondary)
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
      this.onDispatch(new NotificationRowTapped());
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        if (this.uiState.isLoading && this.uiState.displayName.length === 0) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color(this.T.colors.accent)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ top: TOOLBAR_HEIGHT })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.uiState.errorMessage !== null && this.uiState.displayName.length === 0) {
          Column() {
            Text(this.uiState.errorMessage)
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ top: TOOLBAR_HEIGHT })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll(this.scroller) {
            Column() {
              this.Cover()

              Row({ space: this.T.spacing.lg }) {
                Column() {
                  Image($r('app.media.ic_call'))
                    .width(22)
                    .height(22)
                    .fillColor(this.T.colors.textSecondary)
                }
                .width(48)
                .height(48)
                .borderRadius(this.T.radius.full)
                .backgroundColor(this.T.colors.surfaceVariant)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                Text('通话')
                  .fontSize(this.T.typography.caption.fontSize)
                  .fontColor(this.T.colors.textSecondary)
                  .margin({ top: this.T.spacing.xs })

                Column() {
                  Image($r('app.media.ic_video'))
                    .width(22)
                    .height(22)
                    .fillColor(this.T.colors.textSecondary)
                }
                .width(48)
                .height(48)
                .borderRadius(this.T.radius.full)
                .backgroundColor(this.T.colors.surfaceVariant)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                Text('视频')
                  .fontSize(this.T.typography.caption.fontSize)
                  .fontColor(this.T.colors.textSecondary)
                  .margin({ top: this.T.spacing.xs })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.md })

              Divider()
                .color(this.T.colors.divider)
                .margin({ left: this.T.spacing.screenInset, right: this.T.spacing.screenInset })

              if (this.uiState.username.length > 0) {
                this.InfoRow($r('app.media.ic_username'), 'Username', `@${this.uiState.username}`)
              }
              if (this.uiState.phone.length > 0) {
                this.InfoRow($r('app.media.ic_call'), 'Phone', this.uiState.phone)
              }
              if (this.uiState.bio.length > 0) {
                this.InfoRow($r('app.media.ic_info'), 'Bio', this.uiState.bio)
              }
              if (this.uiState.birthdayText.length > 0) {
                this.InfoRow($r('app.media.ic_cake'), '生日', this.uiState.birthdayText)
              }
              this.NotificationRow()

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
                onOpenGroup: (chatId: number): void => {
                  this.onDispatch(new OpenSharedChatRequested(chatId));
                },
                onToggleAudio: (fileId: number): void => {
                  this.onDispatch(new ToggleSharedAudio(fileId));
                }
              })
            }
            .width('100%')
          }
          .layoutWeight(1)
          // Scroll 的 align 默认是 Center：内容不足一屏时整页会被垂直居中，全出血封面
          // 顶部会空出一条白带、工具条的白色图标压在白底上直接消失。锁回顶部。
          .align(Alignment.TopStart)
          .scrollBar(BarState.Off)
          .onDidScroll(() => {
            const scrolled: boolean = this.scroller.currentOffset().yOffset >= this.coverCollapseOffset();
            if (scrolled !== this.coverScrolled) {
              this.coverScrolled = scrolled;
            }
          })
          .onScrollEdge((side: Edge) => {
            const v: SharedContentViewData = this.sharedView();
            if (side === Edge.Bottom && v.hasMore && !v.loadingMore && !v.loading) {
              this.onDispatch(new LoadMoreSharedContent(v.activeTab));
            }
          })

          Button() {
            Row() {
              Image($r('app.media.ic_comments'))
                .width(20)
                .height(20)
                .fillColor(this.T.colors.textOnAccent)
                .margin({ right: this.T.spacing.xs })

              Text('Message')
                .fontSize(this.T.typography.body.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.T.colors.textOnAccent)
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .height(MESSAGE_BUTTON_HEIGHT)
          .backgroundColor(this.T.colors.accent)
          .borderRadius(this.T.radius.md)
          .margin({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.sm,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            this.onDispatch(new MessageUserRequested());
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.T.colors.background)

      this.Header()
    }
    .width('100%')
    .height('100%')
  }
}