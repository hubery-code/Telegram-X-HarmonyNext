/**
 * feature/profile — 用户资料页（PROFILE-101；PROFILE-103 增强）。
 *
 * 对齐 Android ProfileController 的信息面：
 * 大头像 + 展示名 + 在线状态 + @username + 手机号 + 简介 + 生日 + 通知 +
 * ⋮ 动作菜单 + 下半页共享内容四 Tab（媒体/文件/链接/群组）。
 *
 * 集成契约保持三 prop：uiState / onDispatch / onBack（entry 装配不变）。
 * 全部颜色/间距/字号走 design tokens（core-design-system）。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { getAvatarColorIndex } from '@tgx/core-domain';
import { fileUri } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProfileUiState } from '../contract/ProfileUiState';
import { ProfileIntent, MessageUserRequested, OnSharedTabSelected, LoadMoreSharedContent } from '../contract/ProfileIntent';
import { SharedMediaItem, SharedFileItem, SharedLinkItem, SharedGroupItem } from '../contract/SharedContentItems';


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

/** 共享内容 Tab 描述（图标 + 文案）。 */
interface SharedTabSpec {
  icon: Resource;
  label: string;
}

const SHARED_TABS: SharedTabSpec[] = [
  { icon: $r('app.media.ic_photo'), label: '媒体' },
  { icon: $r('app.media.ic_file'), label: '文件' },
  { icon: $r('app.media.ic_link'), label: '链接' },
  { icon: $r('app.media.ic_group'), label: '群组' }
];

/** ⋮ 菜单占位项：仅 hilog 记录 profile_menu_<key>，无其它动作。 */
interface ProfileMenuEntry {
  key: string;
  label: string;
}

const PLACEHOLDER_MENU: ProfileMenuEntry[] = [
  { key: 'share_contact', label: '分享联系人信息' },
  { key: 'block', label: '屏蔽用户' },
  { key: 'privacy_exception', label: '隐私例外' },
  { key: 'rename', label: '重命名联系人' },
  { key: 'delete', label: '删除联系人' }
];

const DOMAIN: number = 0x0000;
const PAGE_TAG: string = 'ProfilePage';

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

  private avatarColor(index: number): string {
    if (index < 0 || index >= AVATAR_PALETTE.length) {
      return AVATAR_PALETTE[0];
    }
    return AVATAR_PALETTE[index];
  }

  /** ⋮ 菜单：首项「开始私密聊天」真实派发，其余占位 hilog。 */
  private menuElements(): MenuElement[] {
    const items: MenuElement[] = [];
    items.push({
      value: '开始私密聊天',
      action: (): void => {
        this.onDispatch(new MessageUserRequested());
      }
    });
    for (let i = 0; i < PLACEHOLDER_MENU.length; i++) {
      const entry: ProfileMenuEntry = PLACEHOLDER_MENU[i];
      items.push({
        value: entry.label,
        action: (): void => {
          hilog.info(DOMAIN, PAGE_TAG, 'profile_menu_%{public}s', entry.key);
        }
      });
    }
    return items;
  }

  private groupLetters(title: string): string {
    if (title.length === 0) {
      return '?';
    }
    const first: string = title.trim();
    if (first.length === 0) {
      return '?';
    }
    const codePoint: number | undefined = first.codePointAt(0);
    if (codePoint === undefined) {
      return '?';
    }
    return String.fromCodePoint(codePoint).toUpperCase();
  }

  private hasSharedItems(): boolean {
    if (this.uiState.activeSharedTab === 0) {
      return this.uiState.sharedMedia.length > 0;
    }
    if (this.uiState.activeSharedTab === 1) {
      return this.uiState.sharedFiles.length > 0;
    }
    if (this.uiState.activeSharedTab === 2) {
      return this.uiState.sharedLinks.length > 0;
    }
    return this.uiState.sharedGroups.length > 0;
  }

  @Builder
  Header() {
    Row() {
      Image($r('app.media.ic_back'))
        .width(24)
        .height(24)
        .fillColor(this.T.colors.accent)
        .margin({ left: this.T.spacing.xs, right: this.T.spacing.md })
        .onClick(() => {
          this.onBack();
        })

      Text('User Info')
        .fontSize(this.T.typography.title.fontSize)
        .fontWeight(this.T.typography.title.fontWeight)
        .fontColor(this.T.colors.textPrimary)
        .layoutWeight(1)

      Image($r('app.media.ic_more_vert'))
        .width(24)
        .height(24)
        .fillColor(this.T.colors.textPrimary)
        .margin({ right: this.T.spacing.xs })
        .bindMenu(this.menuElements())
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
    .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm })
    .backgroundColor(this.T.colors.background)
  }

  @Builder
  Avatar() {
    if (this.uiState.avatarPath !== null && this.uiState.avatarPath.length > 0) {
      Image(toSandboxUri(this.uiState.avatarPath))
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(this.T.radius.full)
        .objectFit(ImageFit.Cover)
    } else {
      Text(this.uiState.avatarLetters.length > 0 ? this.uiState.avatarLetters : '?')
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(this.T.radius.full)
        .backgroundColor(this.avatarColor(this.uiState.avatarColorIndex))
        .fontColor(this.T.colors.textOnAccent)
        .fontSize(36)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
    }
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

  /** PROFILE-103：通知行（🔔 通知 / 开启）。 */
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
      Text(this.uiState.notificationText)
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
  }

  /** PROFILE-103：共享内容 Tab 栏（选中 accent + 下划线）。 */
  @Builder
  SharedTabBar() {
    Row() {
      ForEach(SHARED_TABS.slice(), (tab: SharedTabSpec, index: number) => {
        Column({ space: this.T.spacing.xs }) {
          Image(tab.icon)
            .width(20)
            .height(20)
            .fillColor(this.uiState.activeSharedTab === index
              ? this.T.colors.accent
              : this.T.colors.textSecondary)
          Text(tab.label)
            .fontSize(this.T.typography.footnote.fontSize)
            .fontColor(this.uiState.activeSharedTab === index
              ? this.T.colors.accent
              : this.T.colors.textSecondary)
          Blank()
            .width(24)
            .height(2)
            .backgroundColor(this.uiState.activeSharedTab === index
              ? this.T.colors.accent
              : this.T.colors.background)
        }
        .layoutWeight(1)
        .onClick(() => {
          this.onDispatch(new OnSharedTabSelected(index));
        })
      }, (tab: SharedTabSpec, index: number) => `${index}`)
    }
    .width('100%')
    .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.sm })
  }

  /** PROFILE-103：内容区空态（对齐 TGX 文案）。 */
  @Builder
  SharedEmpty(title: string, subtitle: string) {
    Column() {
      Text(title)
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.textPrimary)
        .textAlign(TextAlign.Center)
      Text(subtitle)
        .fontSize(this.T.typography.footnote.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ top: this.T.spacing.xs })
    }
    .width('100%')
    .padding({ top: this.T.spacing.lg, bottom: this.T.spacing.lg, left: this.T.spacing.lg, right: this.T.spacing.lg })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  SharedMediaGrid() {
    if (this.uiState.sharedMedia.length === 0) {
      this.SharedEmpty('暂无媒体文件', '在此聊天中分享图片和视频，并在您所有的设备上访问。')
    } else {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.uiState.sharedMedia.slice(), (item: SharedMediaItem, index: number) => {
          Column() {
            if (item.localPath !== null && item.localPath.length > 0) {
              Image(toSandboxUri(item.localPath))
                .width('100%')
                .aspectRatio(1)
                .objectFit(ImageFit.Cover)
            } else {
              Column() {
                Image(item.isPhoto ? $r('app.media.ic_photo') : $r('app.media.ic_file'))
                  .width(24)
                  .height(24)
                  .fillColor(this.T.colors.textSecondary)
              }
              .width('100%')
              .aspectRatio(1)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.T.colors.surfaceVariant)
            }
          }
          .width('33.33%')
          .padding(this.T.spacing.hairline)
        }, (item: SharedMediaItem, index: number) => `${item.fileId}_${index}`)
      }
      .width('100%')
    }
  }

  @Builder
  SharedFileList() {
    if (this.uiState.sharedFiles.length === 0) {
      this.SharedEmpty('暂无文件', '在此聊天中分享文件，并在您所有的设备上访问。')
    } else {
      Column() {
        ForEach(this.uiState.sharedFiles.slice(), (item: SharedFileItem, index: number) => {
          Row() {
            Image($r('app.media.ic_file'))
              .width(28)
              .height(28)
              .fillColor(this.T.colors.accent)
            Column() {
              Text(item.fileName)
                .fontSize(this.T.typography.body.fontSize)
                .fontColor(this.T.colors.textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(item.fileSizeText.length > 0 && item.dateText.length > 0
                ? `${item.fileSizeText} · ${item.dateText}`
                : (item.fileSizeText.length > 0 ? item.fileSizeText : item.dateText))
                .fontSize(this.T.typography.footnote.fontSize)
                .fontColor(this.T.colors.textSecondary)
                .margin({ top: this.T.spacing.hairline })
            }
            .margin({ left: this.T.spacing.sm })
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
        }, (item: SharedFileItem, index: number) => `${index}`)
      }
      .width('100%')
    }
  }

  @Builder
  SharedLinkList() {
    if (this.uiState.sharedLinks.length === 0) {
      this.SharedEmpty('暂无链接', '在此聊天中分享链接，并在您所有的设备上访问。')
    } else {
      Column({ space: this.T.spacing.sm }) {
        ForEach(this.uiState.sharedLinks.slice(), (item: SharedLinkItem, index: number) => {
          Column() {
            if (item.siteName.length > 0) {
              Text(item.siteName)
                .fontSize(this.T.typography.body.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.T.colors.textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            if (item.description.length > 0) {
              Text(item.description)
                .fontSize(this.T.typography.subheadline.fontSize)
                .fontColor(this.T.colors.textSecondary)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .margin({ top: item.siteName.length > 0 ? this.T.spacing.hairline : 0 })
            }
            Text(item.url)
              .fontSize(this.T.typography.footnote.fontSize)
              .fontColor(this.T.colors.link)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .margin({ top: this.T.spacing.xs })
          }
          .width('100%')
          .padding(this.T.spacing.md)
          .backgroundColor(this.T.colors.surfaceVariant)
          .borderRadius(this.T.radius.md)
          .alignItems(HorizontalAlign.Start)
        }, (item: SharedLinkItem, index: number) => `${index}`)
      }
      .width('100%')
      .padding({
        left: this.T.spacing.screenInset,
        right: this.T.spacing.screenInset,
        top: this.T.spacing.sm,
        bottom: this.T.spacing.sm
      })
    }
  }

  @Builder
  SharedGroupList() {
    if (this.uiState.sharedGroups.length === 0) {
      this.SharedEmpty('暂无共同群组', '你们所在的共同群组会显示在这里。')
    } else {
      Column() {
        ForEach(this.uiState.sharedGroups.slice(), (item: SharedGroupItem, index: number) => {
          Row() {
            Text(this.groupLetters(item.title))
              .width(40)
              .height(40)
              .borderRadius(this.T.radius.full)
              .backgroundColor(this.avatarColor(getAvatarColorIndex(item.chatId)))
              .fontColor(this.T.colors.textOnAccent)
              .fontSize(16)
              .textAlign(TextAlign.Center)
            Column() {
              Text(item.title)
                .fontSize(this.T.typography.body.fontSize)
                .fontColor(this.T.colors.textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (item.subtitle.length > 0) {
                Text(item.subtitle)
                  .fontSize(this.T.typography.subheadline.fontSize)
                  .fontColor(this.T.colors.textSecondary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: this.T.spacing.hairline })
              }
            }
            .margin({ left: this.T.spacing.sm })
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
          .onClick(() => {
            hilog.info(DOMAIN, PAGE_TAG, 'profile_shared_group_click chatId=%{public}d', item.chatId);
          })
        }, (item: SharedGroupItem, index: number) => `${item.chatId}_${index}`)
      }
      .width('100%')
    }
  }

  @Builder
  SharedContent() {
    if (this.uiState.activeSharedTab === 0) {
      this.SharedMediaGrid()
    } else if (this.uiState.activeSharedTab === 1) {
      this.SharedFileList()
    } else if (this.uiState.activeSharedTab === 2) {
      this.SharedLinkList()
    } else {
      this.SharedGroupList()
    }
  }

  build() {
    Column() {
      this.Header()

      if (this.uiState.isLoading && this.uiState.displayName.length === 0) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.T.colors.accent)
        }
        .width('100%')
        .layoutWeight(1)
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
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column() {
            Column() {
              this.Avatar()

              Text(this.uiState.displayName.length > 0 ? this.uiState.displayName : 'Unknown')
                .fontSize(this.T.typography.largeTitle.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.T.colors.textPrimary)
                .margin({ top: this.T.spacing.md })
                .textAlign(TextAlign.Center)

              if (this.uiState.statusText.length > 0) {
                Text(this.uiState.statusText)
                  .fontSize(this.T.typography.subheadline.fontSize)
                  .fontColor(this.uiState.statusText === 'online'
                    ? this.T.colors.accent
                    : this.T.colors.textSecondary)
                  .margin({ top: this.T.spacing.xs })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: this.T.spacing.lg, bottom: this.T.spacing.md })

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

            this.SharedTabBar()

            if (this.uiState.sharedLoading) {
              Column() {
                LoadingProgress()
                  .width(32)
                  .height(32)
                  .color(this.T.colors.accent)
              }
              .width('100%')
              .padding({ top: this.T.spacing.lg, bottom: this.T.spacing.lg })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else {
              this.SharedContent()

              if (this.hasSharedItems()) {
                if (this.uiState.sharedLoadingMore) {
                  Row({ space: this.T.spacing.xs }) {
                    LoadingProgress()
                      .width(20)
                      .height(20)
                      .color(this.T.colors.accent)
                    Text('正在加载更多...')
                      .fontSize(this.T.typography.footnote.fontSize)
                      .fontColor(this.T.colors.textSecondary)
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                  .padding({ top: this.T.spacing.md, bottom: this.T.spacing.md })
                } else if (this.uiState.sharedHasMore) {
                  Row() {
                    Text('加载更多')
                      .fontSize(this.T.typography.subheadline.fontSize)
                      .fontColor(this.T.colors.accent)
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                  .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.md })
                  .onClick(() => {
                    this.onDispatch(new LoadMoreSharedContent(this.uiState.activeSharedTab));
                  })
                }
              }
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .onScrollEdge((side: Edge) => {
          if (side === Edge.Bottom && this.uiState.sharedHasMore && !this.uiState.sharedLoadingMore && !this.uiState.sharedLoading) {
            this.onDispatch(new LoadMoreSharedContent(this.uiState.activeSharedTab));
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
  }
}
