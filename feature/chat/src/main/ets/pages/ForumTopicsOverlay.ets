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
import {
  ForumTopicItem,
  ForumTopicsState,
  TopicManageState,
  TOPIC_ICON_COLORS,
  EMPTY_FORUM_CURSOR
} from '../model/ForumTopic';

@Component
export struct ForumTopicsOverlay {
  @Prop forumTopics: ForumTopicsState = ForumTopicsState.initial();
  /** 搜索结果为空时区分「搜不到」与「一条都没有」。 */
  @Prop query: string = '';
  /** FORUM-104：话题管理三合一弹层状态（null = 创建/编辑弹窗、长按菜单、删除确认全关）。 */
  @Prop topicManage: TopicManageState | null = null;
  /**
   * FORUM-105：本端用户能否管理话题（own-admin-rights 回灌）。
   * false（含权限未知/未回包）时「新建话题」按钮不渲染、话题行长按不出菜单 ——
   * 宁可晚出现，不让无权用户点进去吃 TDLib 的 400。
   */
  @Prop canManageTopics: boolean = false;
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
  // FORUM-104：话题管理回调（与 ForumTopicsState 同源，ChatPage 派发意图）。
  onCreateTap?: () => void;
  onTopicManageTitleChanged?: (title: string) => void;
  onTopicManageIconSelected?: (color: number) => void;
  /** FORUM-105：emoji 网格点选（create/edit 两模式都有效；再点一次取消选中）。 */
  onTopicManageEmojiSelected?: (emojiId: string) => void;
  onSubmitTopicManage?: () => void;
  onCloseTopicManageDialog?: () => void;
  onOpenTopicMenu?: (topicId: number) => void;
  onCloseTopicMenu?: () => void;
  onMenuEdit?: (topicId: number, name: string) => void;
  onMenuToggleClosed?: (topicId: number, isClosed: boolean) => void;
  onMenuDelete?: (topicId: number) => void;
  onConfirmDelete?: () => void;
  onDismissDelete?: () => void;

  private t(key: string, ...args: (string | number)[]): string {
    return Lang.getInstance().getString(key, ...args);
  }

  build() {
    Column() {
      // ---- 顶栏：标题 + 新建 + 关闭 ----
      Row() {
        Text(this.t('Topics'))
          .fontSize(this.T.typography.title.fontSize)
          .fontWeight(this.T.typography.title.fontWeight)
          .fontColor(this.T.colors.textPrimary)
          .layoutWeight(1)

        // FORUM-104：新建话题入口。文字按钮自带可读文本（Retry 同一惯例），
        // 不需要 a11y 槽位。FORUM-105：按钮按 own-admin-rights 把关 ——
        // getChatMember 回包确认 can_manage_topics（或群主）才渲染；
        // 权限未知时隐藏，宁可晚出现也不让无权用户点进去报错。
        // 遗留：admin rights 变更的实时推送（updateChatMember）未订阅，
        // 会话中途拿到权限要重进会话才看到按钮。
        if (this.canManageTopics) {
          Text(this.t('Create Topic'))
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.accent)
            .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm })
            .onClick(() => {
              if (this.onCreateTap !== undefined) {
                this.onCreateTap();
              }
            })
        }

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

      // ---- FORUM-104：话题管理弹层 ----
      // 渲染顺序即视觉层叠（后渲染在上）：创建/编辑弹窗 → 长按菜单 → 删除确认。
      // chatOverlayCloseIntent 的收口顺序与此一致（确认 > 菜单 > 弹窗）。
      // 与 ActionMenuSheet(menu) 同一模式：判空用自包含表达式，builder 收**非空**
      // 对象参数 —— @Builder 体内不能声明局部变量做空收窄，参数化后体内直接读。
      if (this.topicManage !== null && this.topicManage.dialogOpen) {
        this.TopicManageDialogSheet(this.topicManage)
      }
      if (this.topicManage !== null && this.topicManage.menuTopicId > 0 &&
        this.menuTopicItem(this.topicManage.menuTopicId) !== null) {
        this.TopicMenuSheet(this.menuTopicItem(this.topicManage.menuTopicId) as ForumTopicItem)
      }
      if (this.topicManage !== null && this.topicManage.confirmDeleteTopicId > 0) {
        this.TopicDeleteConfirmKey()
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
    // FORUM-104：长按出管理菜单。General 话题不出菜单 —— 它的名字/删除
    // 服务端都不允许（editForumTopic 明说 General 不可编辑），出空菜单比
    // 不出菜单更让人困惑。手势常挂、动作内放行（.gesture 不收 undefined
    // 分支）；时长对齐 ChatPage 气泡的 350ms。
    // FORUM-105：own-admin-rights 把关 —— 无权（含权限未知）时动作直接放行掉。
    .gesture(LongPressGesture({ duration: 350 })
      .onAction(() => {
        if (item.isGeneral || !this.canManageTopics) {
          return;
        }
        if (this.onOpenTopicMenu !== undefined) {
          this.onOpenTopicMenu(item.topicId);
        }
      }))
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

  /**
   * FORUM-104：长按菜单指向的话题行（编辑要现拿名字、关闭/重开要现拿关闭态）。
   * 菜单指向的行可能在弹层开着时被下一页合并/服务端推送刷掉 —— 找不到就不渲染菜单，
   * 让返回键/遮罩把状态清掉（比渲染一张数据全空的菜单诚实）。
   */
  private menuTopicItem(topicId: number): ForumTopicItem | null {
    for (let i = 0; i < this.forumTopics.items.length; i++) {
      if (this.forumTopics.items[i].topicId === topicId) {
        return this.forumTopics.items[i];
      }
    }
    return null;
  }

  /**
   * FORUM-104：创建/编辑话题弹窗（遮罩 + 居中卡片）。
   *
   * 与 ActionMenuSheet(menu) 同一模式：收**非空对象参数**，体内直接读字段；
   * 换语言整卡重算（无参/对象参数都在父渲染时重新求值，字符串 key 走体内 t()）。
   */
  @Builder
  TopicManageDialogSheet(tm: TopicManageState) {
    Stack() {
      // 遮罩：点它 = 取消（与关闭按钮同义，不做提交）。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          if (this.onCloseTopicManageDialog !== undefined) {
            this.onCloseTopicManageDialog();
          }
        })

      Column() {
        Text(tm.mode === 'edit' ? this.t('Edit Topic') : this.t('Create Topic'))
          .fontSize(this.T.typography.title.fontSize)
          .fontWeight(this.T.typography.title.fontWeight)
          .fontColor(this.T.colors.textPrimary)
          .margin({ bottom: this.T.spacing.md })

        TextInput({
          text: tm.title,
          placeholder: this.t('Topic Title')
        })
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .placeholderColor(this.T.colors.textSecondary)
          .backgroundColor(this.T.colors.surfaceVariant)
          .borderRadius(this.T.radius.sm)
          .height(44)
          .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm })
          .enabled(!tm.isSubmitting)
          .onChange((value: string) => {
            if (this.onTopicManageTitleChanged !== undefined) {
              this.onTopicManageTitleChanged(value);
            }
          })

        if (tm.mode === 'create') {
          // 色板：TDLib 只认文档六个色值。编辑模式不渲染（服务端不支持改色）。
          Row() {
            ForEach(TOPIC_ICON_COLORS.slice(), (color: number) => {
              Circle()
                .width(32)
                .height(32)
                .fill(color)
                .margin({ right: this.T.spacing.sm })
                .accessibilityText(a11y(A11y.TOPIC_ICON_COLOR))
                .onClick(() => {
                  if (this.onTopicManageIconSelected !== undefined) {
                    this.onTopicManageIconSelected(color);
                  }
                })
            }, (color: number) => `topic_color_${color}`)
          }
          .width('100%')
          .margin({ top: this.T.spacing.md })
        }

        if (tm.iconEmojiIds.length > 0) {
          // FORUM-105：emoji 图标网格（候选来自 getForumTopicDefaultIcons）。
          // 拉取失败/回包为空时整块不渲染（只有色板），不是错误态。
          this.TopicEmojiGrid(tm)
        }

        if (tm.errorMessage.length > 0) {
          // errorMessage 恒为**词条 key**（协调器只回 key，见 classifyTopicManageFailureKey）
          Text(this.t(tm.errorMessage))
            .fontSize(this.T.typography.footnote.fontSize)
            .fontColor(this.T.colors.destructive)
            .margin({ top: this.T.spacing.sm })
        }

        Row() {
          Text(this.t('Cancel'))
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.sm })
            .onClick(() => {
              if (this.onCloseTopicManageDialog !== undefined) {
                this.onCloseTopicManageDialog();
              }
            })

          Text(this.t('Save'))
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.accent)
            .opacity(tm.isSubmitting ? 0.4 : 1)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.sm })
            .onClick(() => {
              if (!tm.isSubmitting && this.onSubmitTopicManage !== undefined) {
                this.onSubmitTopicManage();
              }
            })
        }
        .width('100%')
        .margin({ top: this.T.spacing.sm })
      }
      .width('84%')
      .padding(this.T.spacing.lg)
      .backgroundColor(this.T.colors.background)
      .borderRadius(this.T.radius.lg)
    }
    .width('100%')
    .height('100%')
  }

  /**
   * FORUM-105：话题 emoji 图标网格（create / edit 弹窗共用）。
   *
   * 格子渲染的是**通用占位字符**，不是真实的自定义 emoji：custom_emoji_id 需要
   * 「下载 custom emoji 贴纸文件 → 渲染」的完整管线，本端还没有（全仓检索确认无
   * 可复用组件）。这是 FORUM-105 记录在案的折中 —— 发给 TDLib 的值是真实的
   * custom_emoji_id（TDLib 回包 Sticker.full_type 里的那个），占位只影响本端视觉；
   * 唯一的观感代价是网格里每格长一样，用户盲选一个后再看服务端回灌的真实图标。
   *
   * 收**非空弹层对象**参数（与 ActionMenuSheet 同一模式）：调用点已判
   * iconEmojiIds.length > 0，体内直接读；选中态描边，再点一次取消选中（reducer 侧）。
   * 格子是带文本内容的 Text（占位字符即内容），不是图标-only 控件，不需要 a11y 槽位。
   */
  @Builder
  TopicEmojiGrid(tm: TopicManageState) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(tm.iconEmojiIds, (emojiId: string) => {
        Text('🙂')
          .width(40)
          .height(40)
          .fontSize(22)
          .textAlign(TextAlign.Center)
          .backgroundColor(this.T.colors.surfaceVariant)
          .borderRadius(20)
          .border({
            width: tm.iconEmojiId === emojiId ? 2 : 0,
            color: this.T.colors.accent
          })
          .margin({ right: this.T.spacing.sm, bottom: this.T.spacing.sm })
          .onClick(() => {
            if (this.onTopicManageEmojiSelected !== undefined) {
              this.onTopicManageEmojiSelected(emojiId);
            }
          })
      }, (emojiId: string) => `topic_emoji_${emojiId}`)
    }
    .width('100%')
    .margin({ top: this.T.spacing.md })
  }

  /**
   * FORUM-104：长按管理菜单（遮罩 + 居中卡片，三行文字按钮）。
   * 收**非空行对象**参数（调用点已确认行存在）；行被服务端推送刷掉时不渲染菜单。
   */
  @Builder
  TopicMenuSheet(item: ForumTopicItem) {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          if (this.onCloseTopicMenu !== undefined) {
            this.onCloseTopicMenu();
          }
        })

      Column() {
        Text(this.t('Manage Topic'))
          .fontSize(this.T.typography.subheadline.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .margin({ bottom: this.T.spacing.sm })

        Text(this.t('Edit Topic'))
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(this.T.spacing.sm)
          .onClick(() => {
            if (this.onMenuEdit !== undefined) {
              this.onMenuEdit(item.topicId, item.name);
            }
          })

        Text(item.isClosed ? this.t('Reopen Topic') : this.t('Close Topic'))
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(this.T.spacing.sm)
          .onClick(() => {
            if (this.onMenuToggleClosed !== undefined) {
              this.onMenuToggleClosed(item.topicId, !item.isClosed);
            }
          })

        Text(this.t('Delete Topic'))
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.destructive)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(this.T.spacing.sm)
          .onClick(() => {
            if (this.onMenuDelete !== undefined) {
              this.onMenuDelete(item.topicId);
            }
          })
      }
      .width('70%')
      .padding(this.T.spacing.md)
      .backgroundColor(this.T.colors.background)
      .borderRadius(this.T.radius.lg)
    }
    .width('100%')
    .height('100%')
  }

  /** FORUM-104：删除确认弹窗（破坏性动作的最后一道闸）。 */
  @Builder
  TopicDeleteConfirmKey() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          if (this.onDismissDelete !== undefined) {
            this.onDismissDelete();
          }
        })

      Column() {
        Text(this.t('Delete this topic?'))
          .fontSize(this.T.typography.title.fontSize)
          .fontWeight(this.T.typography.title.fontWeight)
          .fontColor(this.T.colors.textPrimary)
          .margin({ bottom: this.T.spacing.sm })

        Text(this.t('All messages in this topic will be removed for everyone.'))
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .margin({ bottom: this.T.spacing.md })

        Row() {
          Text(this.t('Cancel'))
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.sm })
            .onClick(() => {
              if (this.onDismissDelete !== undefined) {
                this.onDismissDelete();
              }
            })

          Text(this.t('Delete'))
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.destructive)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.sm })
            .onClick(() => {
              if (this.onConfirmDelete !== undefined) {
                this.onConfirmDelete();
              }
            })
        }
        .width('100%')
      }
      .width('84%')
      .padding(this.T.spacing.lg)
      .backgroundColor(this.T.colors.background)
      .borderRadius(this.T.radius.lg)
    }
    .width('100%')
    .height('100%')
  }
}
