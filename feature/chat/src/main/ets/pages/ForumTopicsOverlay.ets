/**
 * feature/chat — 论坛话题列表覆盖层（FORUM-101）
 *
 * 独立文件而不是塞进 `ChatPage`：那边已经 6000+ 行、40 多个 @Builder，
 * 再加一个带搜索框、分页、错误重试的列表会让它更难维护。
 * 本组件只接 `@Prop` + 回调，不持有业务状态（与 `EmojiBoard` 同一约定）。
 */

import {
  A11y,
  a11y,
  formatListTimestamp,
  HourClock,
  hourClockFromFlag,
  Lang,
  SupportedLanguage
} from '@tgx/core-common';
import { LightTheme, Theme } from '@tgx/core-design-system';
import { ForumTopicItem, ForumTopicsState, EMPTY_FORUM_CURSOR } from '../model/ForumTopic';

@Component
export struct ForumTopicsOverlay {
  @Prop forumTopics: ForumTopicsState = ForumTopicsState.initial();
  /** 搜索结果为空时区分「搜不到」与「一条都没有」。 */
  @Prop query: string = '';
  @State private searchText: string = '';
  // I18N-DATE-101：语言与时钟档来自 AppStorage 同一对键（ChatListPage 同源），
  // 这样话题行的时间戳与聊天列表的时间戳形态永远一致。
  @StorageProp('activeLanguage') effectiveLanguage: string = 'en';
  @StorageProp('is24HourClock') is24HourClock: boolean = true;
  private readonly T: Theme = LightTheme;

  onClose?: () => void;
  onLoadMore?: () => void;
  onRetry?: () => void;
  onSearch?: (query: string) => void;
  onOpenTopic?: (item: ForumTopicItem) => void;

  private t(key: string, ...args: (string | number)[]): string {
    return Lang.getInstance().getString(key, ...args);
  }

  build() {
    Column() {
      // ---- 顶栏：标题 + 关闭 ----
      Row() {
        Text(this.t('Topics'))
          .fontSize(this.T.typography.title.fontSize)
          .fontWeight(this.T.typography.title.fontWeight)
          .fontColor(this.T.colors.textPrimary)
          .layoutWeight(1)

        Row() {
          Image($r('app.media.ic_close'))
            .width(24)
            .height(24)
            .fillColor(this.T.colors.textPrimary)
        }
        .width(44)
        .height(44)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .accessibilityText(a11y(A11y.CLOSE))
        .onClick(() => {
          if (this.onClose !== undefined) {
            this.onClose();
          }
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: this.T.spacing.screenInset, right: this.T.spacing.xs })

      // ---- 搜索框 ----
      Row() {
        Image($r('app.media.ic_search'))
          .width(20)
          .height(20)
          .fillColor(this.T.colors.textSecondary)

        TextInput({ text: this.searchText, placeholder: this.t('Search topics') })
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .placeholderColor(this.T.colors.textSecondary)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .height(40)
          .accessibilityText(a11y(A11y.FORUM_SEARCH))
          .onChange((value: string) => {
            this.searchText = value;
            if (this.onSearch !== undefined) {
              this.onSearch(value);
            }
          })
      }
      .width('100%')
      .height(44)
      .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm })
      .margin({ left: this.T.spacing.screenInset, right: this.T.spacing.screenInset })
      .backgroundColor(this.T.colors.surfaceVariant)
      .borderRadius(this.T.radius.md)

      // ---- 列表 / 空态 / 错误 ----
      if (this.forumTopics.errorMessage.length > 0 && this.forumTopics.items.length === 0) {
        this.StatusRowKey('Failed to load topics', true)
      } else if (!this.forumTopics.isLoading && this.forumTopics.items.length === 0) {
        this.StatusRowKey(this.query.length > 0 ? 'No topics found' : 'No topics yet', false)
      } else {
        List() {
          ForEach(this.forumTopics.items, (item: ForumTopicItem) => {
            ListItem() {
              this.TopicRow(item)
            }
          }, (item: ForumTopicItem) => `forum_topic_${item.topicId}`)

          // 尾部：加载中 / 加载更多 / 出错重试
          if (this.forumTopics.isLoading) {
            ListItem() {
              Row() {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(this.T.colors.accent)
              }
              .width('100%')
              .height(56)
              .justifyContent(FlexAlign.Center)
            }
          } else if (this.forumTopics.errorMessage.length > 0) {
            ListItem() {
              this.StatusRowKey('Failed to load topics', true)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .onReachEnd(() => {
          // 触底拉下一页；`hasMore` 与「正在加载」的闸门在 reducer 里，
          // 这里不做判断 —— 页面只负责报告「用户到底了」这个事实。
          if (this.onLoadMore !== undefined) {
            this.onLoadMore();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }

  /**
   * 空态 / 错误态共用一行（图标 + 说明 + 可选重试）。
   *
   * 形参名以 `Key` 结尾是契约：`@Builder` 的**按值参数只求值一次**，
   * 传已解析的串进去，应用内换语言后这一行不会重算（守卫 R7 拦的就是这个）。
   * 所以传 key、在这里 `t()`。
   */
  @Builder
  StatusRowKey(textKey: string, showRetry: boolean) {
    Column() {
      Image($r('app.media.ic_forum'))
        .width(48)
        .height(48)
        .fillColor(this.T.colors.textSecondary)
        .opacity(0.4)
        .margin({ bottom: this.T.spacing.md })

      Text(this.t(textKey))
        .fontSize(this.T.typography.body.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .textAlign(TextAlign.Center)

      if (showRetry) {
        // 文字按钮自带可读文本，读屏会直接念「重试」；
        // 再挂 accessibilityText 是重复标注（守卫 ROUTING 只允许图标-only 控件
        // 走 a11y(...)，这里本就不该挂）。
        Text(this.t('Retry'))
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.accent)
          .margin({ top: this.T.spacing.md })
          .onClick(() => {
            if (this.onRetry !== undefined) {
              this.onRetry();
            }
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: this.T.spacing.xxl, right: this.T.spacing.xxl })
  }

  /** 单个话题行：图标 + 名称 + 最后消息预览 + 未读/置顶/关闭标记。 */
  @Builder
  TopicRow(item: ForumTopicItem) {
    Row() {
      // 话题图标：TDLib 给的是「颜色 + 自定义 emoji id」。
      // 拿不到自定义 emoji 时用首字母占位（与联系人头像同一手法），
      // 因为 ForumTopicIcon 的颜色本身就是服务端为该话题分配的身份色。
      Stack() {
        Circle()
          .width(40)
          .height(40)
          .fill(item.iconColor !== 0 ? item.iconColor : this.T.colors.surfaceVariant)

        Text(item.isGeneral ? '#' : this.topicInitial(item.name))
          .fontSize(this.T.typography.title.fontSize)
          .fontColor(this.T.colors.textOnAccent)
          .accessibilityLevel('no')
      }
      .width(40)
      .height(40)
      .margin({ right: this.T.spacing.sm })

      Column() {
        Row() {
          if (item.isPinned) {
            // 装饰性提示：话题行本身是 accessibilityGroup(true)，
            // 读屏会把「已置顶」并进整行播报，这里再挂一个 accessibilityText
            // 反而会被分组吞掉（守卫 GROUPING 拦的就是这种写法），
            // 所以按本仓惯例用 accessibilityLevel('no') 把它移出可达树。
            Image($r('app.media.ic_pin'))
              .width(14)
              .height(14)
              .fillColor(this.T.colors.textSecondary)
              .margin({ right: 4 })
              .accessibilityLevel('no')
          }
          Text(item.name)
            .fontSize(this.T.typography.body.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.T.colors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (item.lastMessageDate > 0) {
            Text(this.topicTimestamp(item.lastMessageDate))
              .fontSize(this.T.typography.footnote.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .margin({ left: this.T.spacing.xs })
          }
        }
        .width('100%')

        Row() {
          // 预览可能是**词条 key**（协调器 `forumTopicPreviewKey` 的约定），
          // 也可能是一段真实消息文本 —— 只有命中词典的才翻译，
          // 否则原样显示（用户发的内容不许被当成 key 去查）。
          Text(this.previewText(item.preview))
            .fontSize(this.T.typography.subheadline.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (item.isClosed) {
            Text(this.t('Closed'))
              .fontSize(this.T.typography.footnote.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .margin({ left: this.T.spacing.xs })
          }

          if (item.unreadMentionCount > 0) {
            this.Badge('@', this.T.colors.accent)
          } else if (item.unreadCount > 0) {
            this.Badge(`${item.unreadCount}`, this.T.colors.accent)
          }
        }
        .width('100%')
        .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.sm,
      bottom: this.T.spacing.sm
    })
    .alignItems(VerticalAlign.Center)
    // 只用 accessibilityGroup(true)：让读屏把行内已有文本
    //（话题名 / 预览 / 未读数 / 已关闭）自然合成一句。
    // 早先这里还自己拼了一个 accessibilityText，结果是**分组吞掉子标签**
    // 且那句拼串绕过了词典的复数规则（守卫 ROUTING 与 GROUPING 同时报）。
    .accessibilityGroup(true)
    .onClick(() => {
      if (this.onOpenTopic !== undefined) {
        this.onOpenTopic(item);
      }
    })
  }

  @Builder
  Badge(text: string, color: ResourceColor) {
    Text(text)
      .fontSize(this.T.typography.footnote.fontSize)
      .fontColor(this.T.colors.textOnAccent)
      .textAlign(TextAlign.Center)
      .constraintSize({ minWidth: 18 })
      .height(18)
      .padding({ left: 5, right: 5 })
      .backgroundColor(color)
      .borderRadius(9)
      .margin({ left: this.T.spacing.xs })
  }

  /**
   * 话题行时间戳。
   *
   * `item.lastMessageDate` 是**秒**（TDLib 的 Unix 时间戳），而
   * `formatListTimestamp` 要毫秒，所以这里乘 1000 —— 少了这一步会让所有
   * 话题都显示成 1970 年（本仓踩过同类：秒/毫秒混用过一次）。
   */
  private topicTimestamp(seconds: number): string {
    const lang: SupportedLanguage = this.effectiveLanguage === 'zh' ? 'zh' : 'en';
    const clock: HourClock = hourClockFromFlag(this.is24HourClock);
    return formatListTimestamp(lang, seconds * 1000, Date.now(), clock);
  }

  /**
   * 预览文本：命中词典就翻译，否则原样显示。
   *
   * 为什么要 `!== key` 这一层判断：协调器对媒体类消息塞的是词条 key
   * （`'Photo'` / `'Poll'` …），而文本消息塞的是**用户原文**。
   * 用户恰好发了一句 "Photo" 时，若不加判断就会被翻成「照片」——
   * 那是把用户内容当 UI 文案，属于静默改内容。
   */
  private previewText(preview: string): string {
    if (preview.length === 0) {
      return '';
    }
    const translated: string = this.t(preview);
    return translated === preview ? preview : translated;
  }

  /** 首字母占位（emoji/汉字取首字符）。 */
  private topicInitial(name: string): string {
    return name.length > 0 ? name.substring(0, 1) : '?';
  }
}
