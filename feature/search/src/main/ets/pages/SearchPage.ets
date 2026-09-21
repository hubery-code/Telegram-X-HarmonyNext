/**
 * feature/search — SearchPage：全局搜索页（SEARCH-101）。
 *
 * 界面组成：
 * - 搜索栏（Search 组件带清空与提交）；
 * - Tab 切换（全部、对话、消息）；
 * - 历史搜索记录 Tag 列表（单项点击直达搜索、全部清空）；
 * - 搜索结果列表（Chat 项与 Message 项分段展示）；
 * - Loading 状态与空结果提示。
 * 色彩、字号与间距统一使用 core/design_system token。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { SearchChatItem } from '../contract/SearchChatItem';
import { SearchMessageItem } from '../contract/SearchMessageItem';
import { SearchTab, SearchUiState } from '../contract/SearchUiState';
import {
  ClearQuery,
  ClearRecentSearches,
  PerformSearch,
  SelectTab,
  UpdateQuery
} from '../contract/SearchIntent';
import { SearchCoordinator } from '../coordinator/SearchCoordinator';

const AVATAR_SIZE: number = 44;

const AVATAR_COLORS: string[] = [
  '#FFE91E63',
  '#FF9C27B0',
  '#FF673AB7',
  '#FF3F51B5',
  '#FF2196F3',
  '#FF009688',
  '#FF4CAF50',
  '#FFFF9800'
];

function getAvatarColor(id: number): string {
  const index: number = Math.abs(id) % AVATAR_COLORS.length;
  return AVATAR_COLORS[index];
}

function getAvatarLetter(title: string): string {
  const trimmed = title.trim();
  if (trimmed.length === 0) {
    return '?';
  }
  return trimmed.charAt(0).toUpperCase();
}

@Component
export struct SearchPage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @Prop uiState: SearchUiState = SearchUiState.initial();
  coordinator: SearchCoordinator | null = null;
  onDispatch: (intent: Object) => void = () => {};
  onNavigateToChat: (chatId: number, messageId?: number) => void = () => {};
  onBack: () => void = () => {};

  private readonly tabs: SearchTab[] = ['all', 'chats', 'messages'];

  private getTabLabel(tab: SearchTab): string {
    switch (tab) {
      case 'all':
        return 'All';
      case 'chats':
        return 'Chats';
      case 'messages':
        return 'Messages';
      case 'media':
        return 'Media';
      default:
        return '';
    }
  }

  private handleQueryChange(value: string): void {
    if (this.coordinator !== null) {
      this.coordinator.updateQuery(value);
    } else {
      this.onDispatch(new UpdateQuery(value));
    }
  }

  private handleQuerySubmit(value: string): void {
    if (this.coordinator !== null) {
      this.coordinator.performSearchImmediate(value);
    } else {
      this.onDispatch(new PerformSearch(value));
    }
  }

  private handleTabSelect(tab: SearchTab): void {
    if (this.coordinator !== null) {
      this.coordinator.selectTab(tab);
    } else {
      this.onDispatch(new SelectTab(tab));
    }
  }

  private handleRecentSearchClick(term: string): void {
    if (this.coordinator !== null) {
      this.coordinator.performSearchImmediate(term);
    } else {
      this.onDispatch(new PerformSearch(term));
    }
  }

  private handleClearRecent(): void {
    if (this.coordinator !== null) {
      this.coordinator.clearRecentSearches();
    } else {
      this.onDispatch(new ClearRecentSearches());
    }
  }

  /**
   * 点击会话结果 → 导航到会话（INTEG-002）。
   *
   * 协调器存在时**必须直接 return**：`SearchCoordinator.navigateToChat` 内部就是
   * `this.onNavigateToChat(...)`，转发的正是同一个回调；若再调一次页面 prop，
   * 装配层会被调两次，每次点结果都会开两次会话（重复 openChat + 重复建协调器）。
   * 协调器缺席时（只用 reducer 的降级路径）才走页面 prop。
   */
  private handleChatClick(chatId: number): void {
    if (this.coordinator !== null) {
      this.coordinator.navigateToChat(chatId);
      return;
    }
    this.onNavigateToChat(chatId);
  }

  /** 点击消息结果 → 导航到所属会话（见 handleChatClick 的双发说明）。 */
  private handleMessageClick(chatId: number, messageId: number): void {
    if (this.coordinator !== null) {
      this.coordinator.navigateToChat(chatId, messageId);
      return;
    }
    this.onNavigateToChat(chatId, messageId);
  }

  build() {
    Column() {
      // 1. 搜索栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(this.T.colors.accent)
          .margin({ right: this.T.spacing.sm })
          .onClick(() => {
            this.onBack();
          })

        Search({ value: this.uiState.query, placeholder: 'Search chats, messages...' })
          .searchButton('Search')
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.T.colors.surfaceVariant)
          .placeholderColor(this.T.colors.textSecondary)
          .textFont({ size: this.T.typography.body.fontSize })
          .onChange((value: string) => {
            this.handleQueryChange(value);
          })
          .onSubmit((value: string) => {
            this.handleQuerySubmit(value);
          })
      }
      .width('100%')
      .padding({
        left: this.T.spacing.screenInset,
        right: this.T.spacing.screenInset,
        top: this.T.spacing.sm,
        bottom: this.T.spacing.xs
      })

      // 2. Tab 切换
      Row() {
        ForEach(this.tabs, (tab: SearchTab) => {
          Column() {
            Text(this.getTabLabel(tab))
              .fontSize(this.T.typography.subheadline.fontSize)
              .fontWeight(this.uiState.activeTab === tab ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.uiState.activeTab === tab ? this.T.colors.accent : this.T.colors.textSecondary)
              .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.xs })

            Divider()
              .strokeWidth(2)
              .color(this.uiState.activeTab === tab ? this.T.colors.accent : Color.Transparent)
              .width('70%')
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.handleTabSelect(tab);
          })
        }, (tab: SearchTab) => tab)
      }
      .width('100%')
      .border({
        width: { bottom: 1 },
        color: this.T.colors.divider
      })

      // 3. 内容区
      if (this.uiState.isLoading) {
        this.LoadingView()
      } else if (this.uiState.errorMessage !== null) {
        this.ErrorView(this.uiState.errorMessage)
      } else if (this.uiState.query.trim().length === 0) {
        this.RecentSearchesView()
      } else if (this.uiState.chatResults.length === 0 && this.uiState.messageResults.length === 0) {
        this.EmptyResultView()
      } else {
        this.SearchResultsView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }

  @Builder
  private LoadingView() {
    Column() {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(this.T.colors.accent)
      Text('Searching...')
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .margin({ top: this.T.spacing.sm })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private ErrorView(message: string) {
    Column() {
      Text('Search Error')
        .fontSize(this.T.typography.headline.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.T.colors.destructive)
        .textAlign(TextAlign.Center)
      Text(message)
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.destructive)
        .textAlign(TextAlign.Center)
        .margin({ top: this.T.spacing.xs })
      Button('Retry')
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.textOnAccent)
        .backgroundColor(this.T.colors.accent)
        .borderRadius(this.T.radius.md)
        .margin({ top: this.T.spacing.md })
        .onClick(() => {
          this.handleQuerySubmit(this.uiState.query);
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset
    })
  }

  @Builder
  private EmptyResultView() {
    Column() {
      Image($r('app.media.ic_search'))
        .width(48)
        .height(48)
        .fillColor(this.T.colors.textTertiary)
        .margin({ bottom: this.T.spacing.md })
      Text('No Results')
        .fontSize(this.T.typography.headline.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.T.colors.textPrimary)
      Text(`No results found for "${this.uiState.query}"`)
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .margin({ top: this.T.spacing.xs })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private RecentSearchesView() {
    Column() {
      if (this.uiState.recentSearches.length > 0) {
        Row() {
          Text('Recent Searches')
            .fontSize(this.T.typography.subheadline.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.T.colors.textPrimary)

          Blank()

          Text('Clear All')
            .fontSize(this.T.typography.caption.fontSize)
            .fontColor(this.T.colors.accent)
            .onClick(() => {
              this.handleClearRecent();
            })
        }
        .width('100%')
        .padding({
          left: this.T.spacing.screenInset,
          right: this.T.spacing.screenInset,
          top: this.T.spacing.md,
          bottom: this.T.spacing.sm
        })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.uiState.recentSearches, (term: string) => {
            Row() {
              Text(term)
                .fontSize(this.T.typography.caption.fontSize)
                .fontColor(this.T.colors.textPrimary)
            }
            .padding({
              left: this.T.spacing.md,
              right: this.T.spacing.md,
              top: this.T.spacing.xs,
              bottom: this.T.spacing.xs
            })
            .margin({ right: this.T.spacing.xs, bottom: this.T.spacing.xs })
            .backgroundColor(this.T.colors.surfaceVariant)
            .borderRadius(this.T.radius.full)
            .onClick(() => {
              this.handleRecentSearchClick(term);
            })
          }, (term: string) => term)
        }
        .padding({
          left: this.T.spacing.screenInset,
          right: this.T.spacing.screenInset
        })
      } else {
        Column() {
          Image($r('app.media.ic_search'))
            .width(56)
            .height(56)
            .fillColor(this.T.colors.textTertiary)
            .margin({ bottom: this.T.spacing.md })
          Text('Search Telegram')
            .fontSize(this.T.typography.headline.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.T.colors.textSecondary)
          Text('Search for chats, channels, and messages')
            .fontSize(this.T.typography.subheadline.fontSize)
            .fontColor(this.T.colors.textTertiary)
            .margin({ top: this.T.spacing.xs })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private SearchResultsView() {
    List() {
      // 对话分段
      if (
        (this.uiState.activeTab === 'all' || this.uiState.activeTab === 'chats') &&
        this.uiState.chatResults.length > 0
      ) {
        ListItem() {
          Text(`CHATS (${this.uiState.chatResults.length})`)
            .fontSize(this.T.typography.caption.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.T.colors.textSecondary)
            .padding({
              left: this.T.spacing.screenInset,
              right: this.T.spacing.screenInset,
              top: this.T.spacing.md,
              bottom: this.T.spacing.xs
            })
        }

        ForEach(this.uiState.chatResults, (item: SearchChatItem) => {
          ListItem() {
            this.ChatResultRow(item)
          }
          .onClick(() => {
            this.handleChatClick(item.chatId);
          })
        }, (item: SearchChatItem) => `chat_${item.chatId}`)
      }

      // 消息分段
      if (
        (this.uiState.activeTab === 'all' || this.uiState.activeTab === 'messages') &&
        this.uiState.messageResults.length > 0
      ) {
        ListItem() {
          Text(`MESSAGES (${this.uiState.messageResults.length})`)
            .fontSize(this.T.typography.caption.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.T.colors.textSecondary)
            .padding({
              left: this.T.spacing.screenInset,
              right: this.T.spacing.screenInset,
              top: this.T.spacing.md,
              bottom: this.T.spacing.xs
            })
        }

        ForEach(this.uiState.messageResults, (item: SearchMessageItem) => {
          ListItem() {
            this.MessageResultRow(item)
          }
          .onClick(() => {
            this.handleMessageClick(item.chatId, item.messageId);
          })
        }, (item: SearchMessageItem) => `msg_${item.chatId}_${item.messageId}`)
      }
    }
    .width('100%')
    .layoutWeight(1)
    .divider({
      strokeWidth: 1,
      color: this.T.colors.divider,
      startMargin: this.T.spacing.screenInset + AVATAR_SIZE + this.T.spacing.md,
      endMargin: this.T.spacing.none
    })
  }

  @Builder
  private ChatResultRow(item: SearchChatItem) {
    Row() {
      // 头像占位
      Text(getAvatarLetter(item.title))
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(this.T.radius.full)
        .backgroundColor(getAvatarColor(item.chatId))
        .fontColor(this.T.colors.textOnAccent)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)

      Column() {
        Row() {
          Text(item.title)
            .fontSize(this.T.typography.body.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.T.colors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (item.isChannel) {
            Text('Channel')
              .fontSize(this.T.typography.caption.fontSize)
              .fontColor(this.T.colors.accent)
              .padding({ left: this.T.spacing.xs, right: this.T.spacing.xs })
              .backgroundColor(this.T.colors.surfaceVariant)
              .borderRadius(this.T.radius.sm)
              .margin({ left: this.T.spacing.xs })
          } else if (item.isGroup) {
            Text('Group')
              .fontSize(this.T.typography.caption.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .padding({ left: this.T.spacing.xs, right: this.T.spacing.xs })
              .backgroundColor(this.T.colors.surfaceVariant)
              .borderRadius(this.T.radius.sm)
              .margin({ left: this.T.spacing.xs })
          }
        }
        .width('100%')

        if (item.username.length > 0) {
          Text(`@${item.username}`)
            .fontSize(this.T.typography.subheadline.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: this.T.spacing.md })
    }
    .width('100%')
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.sm,
      bottom: this.T.spacing.sm
    })
  }

  @Builder
  private MessageResultRow(item: SearchMessageItem) {
    Row() {
      // 会话图标或首字母
      Text(getAvatarLetter(item.chatTitle))
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(this.T.radius.full)
        .backgroundColor(getAvatarColor(item.chatId))
        .fontColor(this.T.colors.textOnAccent)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)

      Column() {
        Row() {
          Text(item.chatTitle)
            .fontSize(this.T.typography.body.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.T.colors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(item.dateFormatted)
            .fontSize(this.T.typography.caption.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .margin({ left: this.T.spacing.xs })
        }
        .width('100%')

        Row() {
          if (item.senderName.length > 0) {
            Text(`${item.senderName}: `)
              .fontSize(this.T.typography.subheadline.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .fontWeight(FontWeight.Medium)
          }

          Text(item.textSnippet)
            .fontSize(this.T.typography.subheadline.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: this.T.spacing.md })
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
