/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { StickerSetItem } from '../model/StickerSetPreviewState';
import { GifItem, GIF_CATEGORIES, DEFAULT_RECENT_GIFS, DEFAULT_GIF_PACKS } from '../model/GifItem';
import {
  StickerBoardPack,
  StickerTrendingPack,
  STICKER_BOARD_RECENT_SET_ID,
  stickerBoardBlocks,
  stickerBoardPackKey,
  stickerCellImagePath,
  stickerCellKey,
  stickerTrendingKey
} from '../model/StickerBoard';


/** 沙箱路径 → Image 可吃的 uri（与贴纸包预览弹层同一口径）。 */
function toSandboxUri(path: string | null): string {
  if (path === null || path.length === 0) {
    return '';
  }
  return path.startsWith('file://') ? path : `file://${path}`;
}


export interface StickerPreviewItem {
  readonly id: string;
  readonly emoji: string;
  readonly title: string;
}

export interface GifPreviewItem {
  readonly id: string;
  readonly title: string;
  readonly tag: string;
}

/** EMOJI-101：静态内置表情分类（对标 Telegram X EmojiSection 体系） */
const STATIC_EMOJI_CATEGORIES: string[][] = [
  // 0: Smileys & Emotions
  [
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃',
    '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙',
    '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫', '🤔',
    '🤐', '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬', '🤥',
    '😌', '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕', '🤢', '🤮',
    '🤧', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳', '🥸', '😎',
    '🤓', '🧐', '😕', '😟', '🙁', '😮', '😯', '😲', '😳', '🥺',
    '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖', '😣',
    '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '💀',
    '💩', '🤡', '👻', '👽', '🤖'
  ],
  // 1: Gestures & Body
  [
    '👋', '🤚', '🖐', '✋', '🖖', '👌', '🤌', '🤏', '✌', '🤞',
    '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝', '👍',
    '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌', '👐', '🤲', '🤝',
    '🙏', '✍', '💅', '🤳', '💪', '🧠', '🫀', '🫁', '🦷', '🦴',
    '👀', '👁', '👅', '👄'
  ],
  // 2: Animals & Nature
  [
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯',
    '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🦆', '🦅',
    '🦉', '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🐛', '🦋', '🐌',
    '🐞', '🐜', '🦟', '🐢', '🐍', '🦎', '🐙', '🦑', '🦐', '🦞',
    '🦀', '🐡', '🐠', '🐟', '🐬', '🐳', '🦈', '🐊', '🐅', '🐆',
    '🦓', '🦍', '🦧', '🐘', '🦛', '🦏', '🐪', '🐫', '🦒', '🦘',
    '🌸', '🌺', '🌻', '🌹', '🌷', '🌼', '🌲', '🌳', '🌴', '🌵',
    '🍀', '🍁', '🍂', '🍃'
  ],
  // 3: Food & Drink
  [
    '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐',
    '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🥑', '🥦',
    '🥬', '🥒', '🌶', '🌽', '🥕', '🧄', '🧅', '🥔', '🍠', '🥐',
    '🥯', '🍞', '🥖', '🥨', '🧀', '🥚', '🍳', '🧈', '🥞', '🧇',
    '🥓', '🥩', '🍗', '🍖', '🌭', '🍔', '🍟', '🍕', '🥪', '🥙',
    '🌮', '🌯', '🥗', '🥘', '🍝', '🍜', '🍲', '🍛', '🍣', '🍱',
    '🥟', '🍤', '🍙', '🍚', '🍘', '🍦', '🍧', '🍨', '🍩', '🍪',
    '🎂', '🍰', '🧁', '🍫', '🍬', '🍭', '☕', '🍵', '🧃', '🥤',
    '🧋', '🍶', '🍺', '🍻', '🥂', '🍷', '🥃', '🍸', '🍹'
  ],
  // 4: Travel & Activities
  [
    '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱',
    '🪀', '🏓', '🏸', '🏒', '🏑', '🥍', '🏏', '🪃', '🥅', '⛳',
    '🪁', '🏹', '🎣', '🤿', '🥊', '🥋', '🎽', '🛹', '🛼', '🛷',
    '⛸', '🥌', '🎿', '⛷', '🏂', '🏋', '🤼', '🤸', '⛹', '🤺',
    '🤾', '🏌', '🏇', '🧘', '🚗', '🚕', '🚙', '🚌', '🚎', '🏎',
    '🚓', '🚑', '🚒', '🚐', '🛻', '🚚', '🚛', '🚜', '🦯', '🦽',
    '🦼', '🛴', '🚲', '🛵', '🏍', '🛺', '🚨', '🚔', '🚍', '🚘',
    '🚖', '🚡', '🚠', '🚀', '🛸', '🚁', '🛶', '⛵', '🚤', '🛥',
    '🛳', '⛴', '🚢'
  ],
  // 5: Objects & Symbols
  [
    '❤', '🧡', '💛', '💚', '💙', '💜', '🤎', '🖤', '🤍', '💔',
    '❣', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟', '☮',
    '✝', '☪', '🕉', '☸', '✡', '🔯', '🕎', '☯', '☦', '🛐',
    '⛎', '♈', '♉', '♊', '♋', '♌', '♍', '♎', '♏', '♐',
    '♑', '♒', '♓', '🆔', '⚛', '🉑', '☢', '☣', '📴', '📳',
    '🈶', '🈚', '🈸', '🈺', '🈷', '✴', '🆚', '💮', '🉐', '㊙',
    '㊗', '🈴', '🈵', '🈹', '🈲', '🅰', '🅱', '🆎', '🆑', '🅾',
    '🆘', '❌', '⭕', '🛑', '⛔', '📛', '🚫', '💯', '💢', '♨',
    '🚷', '🚯', '🚳', '🚱', '🔞', '📵', '🚭', '❗', '❕', '❓',
    '❔', '‼', '⁉', '🔅', '🔆', '〽', '⚠', '🚸', '🔱', '⚜',
    '🔰', '♻', '✅', '🈯', '💹', '❇', '✳', '❎', '🌐', '💠',
    'Ⓜ', '🌀', '💤'
  ],
  // 6: Flags
  [
    '🏳', '🏴', '🏁', '🚩', '🎌', '🏴‍☠️', '🇨🇳', '🇺🇸', '🇬🇧', '🇯🇵',
    '🇩🇪', '🇫🇷', '🇷🇺', '🇮🇹', '🇪🇸', '🇰🇷', '🇮🇳', '🇨🇦', '🇧🇷', '🇦🇺',
    '🇲🇽', '🇳🇱', '🇹🇷', '🇸🇦', '🇦🇪', '🇿🇦', '🇪🇬', '🇸🇬', '🇲🇾', '🇹🇭',
    '🇻🇳', '🇮🇩', '🇵🇭', '🇳🇿', '🇨🇭', '🇸🇪', '🇳🇴', '🇩🇰', '🇫🇮', '🇵🇱',
    '🇺🇦', '🇬🇷', '🇵🇹', '🇮🇪', '🇦🇹', '🇧🇪'
  ]
];

/** EMOJI-101：8 大分类图标（索引 0 为 Recent 最近使用） */
const CATEGORY_ICONS: string[] = ['🕒', '😀', '🖐', '🐶', '🍔', '🚗', '💡', '🏁'];

const SAMPLE_STICKERS: StickerPreviewItem[] = [
  { id: '1', emoji: '😎', title: 'Cool' },
  { id: '2', emoji: '🎉', title: 'Party' },
  { id: '3', emoji: '🚀', title: 'Rocket' },
  { id: '4', emoji: '🔥', title: 'Fire' },
  { id: '5', emoji: '👍', title: 'Like' },
  { id: '6', emoji: '❤️', title: 'Love' },
  { id: '7', emoji: '☕', title: 'Coffee' },
  { id: '8', emoji: '🌟', title: 'Star' },
  { id: '9', emoji: '🐱', title: 'Cat' },
  { id: '10', emoji: '🐶', title: 'Dog' },
  { id: '11', emoji: '🥳', title: 'Celebrate' },
  { id: '12', emoji: '💪', title: 'Strong' }
];

const SAMPLE_GIFS: GifPreviewItem[] = [
  { id: 'g1', title: 'Thumbs Up', tag: '👍' },
  { id: 'g2', title: 'Cheers!', tag: '🥂' },
  { id: 'g3', title: 'Mind Blown', tag: '🤯' },
  { id: 'g4', title: 'Dancing', tag: '💃' },
  { id: 'g5', title: 'LOL', tag: '🤣' },
  { id: 'g6', title: 'Applause', tag: '👏' }
];

@Component
export struct EmojiBoard {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  onSelectEmoji: (emoji: string) => void = () => {};
  onDeleteChar: () => void = () => {};
  onSelectSticker: (emoji: string) => void = () => {};
  onSendSticker?: (item: StickerSetItem) => void;
  onClearRecentStickers?: () => void;
  onSendGif?: (item: GifItem) => void;
  onClearRecentGifs?: () => void;
  onOpenStickerSet: (setId: string) => void = () => {};
  /**
   * STICKER-BOARD-101：切到贴纸页签时通知父层「要看贴纸板」。
   * 父层收到后派发 `OpenStickerBoard`；重复派发无害（reducer 里已装过盘就不再请求）。
   */
  onStickerBoardVisible: () => void = () => {};
  /**
   * STICKER-BOARD-102：热门区那一个「添加 / 移除」。语义与 Android 一致 —— 装包是
   * **行内**动作（`ChangeStickerSet`），不是跳去商店页；点封面/标题才开整包弹层。
   */
  onInstallStickerSet?: (setId: string) => void;
  onUninstallStickerSet?: (setId: string) => void;
  onClearRecent?: () => void;

  /** STICKER-BOARD-101：`getInstalledStickerSets` 装出来的真实贴纸包（空 = 账号没装任何包）。 */
  @Prop stickerPacks: StickerBoardPack[] = [];
  @Prop stickerBoardLoading: boolean = false;
  @Prop stickerBoardError: string | null = null;
  /** STICKER-BOARD-102：`getTrendingStickerSets` 的热门包（读不到就是没有这一区）。 */
  @Prop stickerTrending: StickerTrendingPack[] = [];
  /** 在途的那一包（含卸载）；同一时刻只允许一包，避免重复点击发出第二条请求。 */
  @Prop stickerInstallingSetId: string | null = null;

  /** EMOJI-101：由父层回灌的最近使用表情列表 */
  @Prop recentEmojis: string[] = [];
  /** STICKER-101：由父层回灌的最近使用贴纸列表 */
  @Prop recentStickers: StickerSetItem[] = [];
  /** GIF-101：由父层回灌的最近使用动图列表 */
  @Prop recentGifs: GifItem[] = [];

  @State currentMainTab: string = 'emoji';
  @State currentEmojiCategory: number = 0;
  @State currentStickerPackIndex: number = 0;
  /** 贴纸包连续列表的滚动器：顶部包条点一下滚到对应那一包。 */
  private stickerScroller: Scroller = new Scroller();
  @State currentGifCategoryIndex: number = 0;
  @State gifSearchQuery: string = '';

  build() {
    Column() {
      // 顶部内容区（根据当前 Tab 切换显示表情网格、贴纸或 GIF）
      Column() {
        if (this.currentMainTab === 'emoji') {
          this.EmojiView()
        } else if (this.currentMainTab === 'sticker') {
          this.StickerView()
        } else {
          this.GifView()
        }
      }
      .layoutWeight(1)
      .width('100%')

      // 底部切换导航栏（对齐 Telegram X：表情、贴纸、GIF 切换，右侧退格键）
      Row() {
        // 左侧主要分页切换按钮
        Row() {
          // 表情 Tab
          Row() {
            Image($r('app.media.ic_emoji'))
              .width(22)
              .height(22)
              .fillColor(this.currentMainTab === 'emoji' ? this.T.colors.accent : this.T.colors.textSecondary)
          }
          .height('100%')
          .padding({ left: this.T.spacing.md, right: this.T.spacing.md })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.currentMainTab = 'emoji';
          })

          // 贴纸 Tab
          Row() {
            Image($r('app.media.ic_sticker'))
              .width(22)
              .height(22)
              .fillColor(this.currentMainTab === 'sticker' ? this.T.colors.accent : this.T.colors.textSecondary)
          }
          .height('100%')
          .padding({ left: this.T.spacing.md, right: this.T.spacing.md })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.currentMainTab = 'sticker';
            this.onStickerBoardVisible();
          })

          // GIF Tab
          Row() {
            Image($r('app.media.ic_gif'))
              .width(22)
              .height(22)
              .fillColor(this.currentMainTab === 'gif' ? this.T.colors.accent : this.T.colors.textSecondary)
          }
          .height('100%')
          .padding({ left: this.T.spacing.md, right: this.T.spacing.md })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.currentMainTab = 'gif';
          })
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(VerticalAlign.Center)

        // 右侧退格删除键
        Row() {
          Image($r('app.media.ic_backspace'))
            .width(22)
            .height(22)
            .fillColor(this.T.colors.textSecondary)
        }
        .width(48)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onDeleteChar();
        })
      }
      .width('100%')
      .height(44)
      .borderWidth({ top: 1 })
      .borderColor(this.T.colors.divider)
      .backgroundColor(this.T.colors.surface)
    }
    .width('100%')
    .height(280)
    .backgroundColor(this.T.colors.surface)
  }

  /** 表情视图：分类横向滚动条 + 8列 Emoji 网格 / 最近表情空态 */
  @Builder
  EmojiView() {
    Column() {
      // 表情子分类选择条：横向平滑滚动 Scroll 容器包裹 8 大分类
      Scroll() {
        Row() {
          ForEach(CATEGORY_ICONS, (icon: string, index: number) => {
            Column() {
              Row() {
                Text(icon)
                  .fontSize(18)
                  .opacity(this.currentEmojiCategory === index ? 1.0 : 0.45)
              }
              .height(34)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)

              // 选中高亮指示条
              Row()
                .width(28)
                .height(2)
                .backgroundColor(this.currentEmojiCategory === index ? this.T.colors.accent : Color.Transparent)
                .borderRadius(1)
            }
            .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm })
            .height(36)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.currentEmojiCategory = index;
            })
          })
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(36)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .borderWidth({ bottom: 1 })
      .borderColor(this.T.colors.divider)

      // 表情主体展示区（分类 0 为 Recent，分类 1..7 为内置各组）
      if (this.currentEmojiCategory === 0) {
        if (this.recentEmojis.length > 0) {
          Column() {
            // Recent 顶栏（展示标题与清空入口）
            Row() {
              Text('Recent')
                .fontSize(this.T.typography.caption.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.T.colors.textSecondary)

              Blank()

              Text('Clear')
                .fontSize(this.T.typography.caption.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.T.colors.accent)
                .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm, top: 4, bottom: 4 })
                .borderRadius(this.T.radius.sm)
                .onClick(() => {
                  if (this.onClearRecent) {
                    this.onClearRecent();
                  }
                })
            }
            .width('100%')
            .padding({ left: this.T.spacing.md, right: this.T.spacing.md, top: this.T.spacing.xs, bottom: this.T.spacing.xs })

            // 最近使用表情网格
            Grid() {
              ForEach(this.recentEmojis, (emoji: string) => {
                GridItem() {
                  Row() {
                    Text(emoji)
                      .fontSize(26)
                  }
                  .width('100%')
                  .height(42)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(VerticalAlign.Center)
                  .borderRadius(this.T.radius.sm)
                  .onClick(() => {
                    this.onSelectEmoji(emoji);
                  })
                }
              })
            }
            .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr')
            .rowsGap(2)
            .columnsGap(2)
            .padding({
              left: this.T.spacing.xs,
              right: this.T.spacing.xs,
              bottom: this.T.spacing.xs
            })
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .height('100%')
        } else {
          // 最近使用为空时的提示
          Column() {
            Text('🕒')
              .fontSize(38)
              .opacity(0.4)
              .margin({ bottom: this.T.spacing.sm })
            Text('No Recent Emojis')
              .fontSize(this.T.typography.body.fontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.T.colors.textPrimary)
            Text('Emojis you send will appear here')
              .fontSize(this.T.typography.caption.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .margin({ top: this.T.spacing.xs })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      } else {
        // 内置静态分类网格（索引偏移 1）
        Grid() {
          ForEach(STATIC_EMOJI_CATEGORIES[this.currentEmojiCategory - 1], (emoji: string) => {
            GridItem() {
              Row() {
                Text(emoji)
                  .fontSize(26)
              }
              .width('100%')
              .height(42)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .borderRadius(this.T.radius.sm)
              .onClick(() => {
                this.onSelectEmoji(emoji);
              })
            }
          })
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr')
        .rowsGap(2)
        .columnsGap(2)
        .padding({
          left: this.T.spacing.xs,
          right: this.T.spacing.xs,
          top: this.T.spacing.xs,
          bottom: this.T.spacing.xs
        })
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 贴纸视图（STICKER-BOARD-101）：**真实**已安装贴纸包 + 最近使用伪包。
   *
   * 版式照 Android 的贴纸页：一整张连续列表，每包 = 整宽标题行 + 包内封面贴纸内联
   * （`MediaStickersAdapter.java:682-698`），顶部横向包缩略图条点一下滚到那一包
   * （`MediaHeaderView.java:223-248`）；点标题行开整包页（同一处 `:268-270`）。
   * 之前这里是四包预置数据 + emoji 占位，看不出账号里到底装了哪些包。
   */
  @Builder
  StickerView() {
    Column() {
      // 包缩略图条：最近使用在最前（它没有 thumbnail，退回第一颗贴纸的图）
      Scroll() {
        Row() {
          ForEach(this.stickerBlocks(), (pack: StickerBoardPack, index: number) => {
            Column() {
              if (pack.thumbnailPath !== null && pack.thumbnailPath.length > 0) {
                Image(toSandboxUri(pack.thumbnailPath))
                  .width(28)
                  .height(28)
                  .objectFit(ImageFit.Contain)
              } else {
                // 没缩略图退回包名首字母：Android 的包条也是「图为底、字母兜底」，
                // 而不是再画一个 emoji —— 这里已经有真实贴纸图可显示，不需要假图标。
                Text(pack.title.length > 0 ? pack.title.substring(0, 1).toUpperCase() : '★')
                  .fontSize(16)
                  .fontColor(this.T.colors.textSecondary)
              }
            }
            .width(36)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(this.T.radius.sm)
            .backgroundColor(this.currentStickerPackIndex === index ? this.T.colors.surfaceVariant : Color.Transparent)
            .onClick(() => {
              this.currentStickerPackIndex = index;
              this.stickerScroller.scrollToIndex(index, true);
            })
          }, (pack: StickerBoardPack, index: number) => `${index}_${pack.setId}_${pack.thumbnailPath ?? ''}`)
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(44)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .borderWidth({ bottom: 1 })
      .borderColor(this.T.colors.divider)

      if (this.stickerBlocks().length === 0 && this.stickerTrending.length === 0) {
        this.StickerBoardEmptyView()
      } else {
        List({ space: this.T.spacing.xs, scroller: this.stickerScroller }) {
          // 热门区排在已装包**之前**：账号一个包都没装时这里是唯一的装包入口，
          // 排在下面等于让用户滚过一片空白去找它。
          if (this.stickerTrending.length > 0) {
            ListItem() {
              this.StickerTrendingSection()
            }
          }
          ForEach(this.stickerBlocks(), (pack: StickerBoardPack) => {
            ListItem() {
              Column() {
                // 整宽标题行：真实包可点开整包（TDLib covers 只给前 5 张，整包内容在弹层里）
                Row() {
                  Text(pack.title)
                    .fontSize(this.T.typography.caption.fontSize)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.T.colors.textSecondary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)

                  if (pack.setId === STICKER_BOARD_RECENT_SET_ID) {
                    if (this.onClearRecentStickers) {
                      Text('清空')
                        .fontSize(this.T.typography.caption.fontSize)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.T.colors.accent)
                        .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm, top: 2, bottom: 2 })
                        .onClick(() => {
                          if (this.onClearRecentStickers) {
                            this.onClearRecentStickers();
                          }
                        })
                    }
                  } else {
                    Text(pack.hasMore ? `查看其余 ${pack.totalSize - pack.covers.length} 张` : '查看贴纸包')
                      .fontSize(this.T.typography.caption.fontSize)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.T.colors.accent)
                      .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm, top: 2, bottom: 2 })
                      .onClick(() => {
                        this.onOpenStickerSet(pack.setId);
                      })
                  }
                }
                .width('100%')
                .padding({
                  left: this.T.spacing.md,
                  right: this.T.spacing.md,
                  top: this.T.spacing.xs,
                  bottom: 2
                })
                .onClick(() => {
                  if (pack.setId !== STICKER_BOARD_RECENT_SET_ID) {
                    this.onOpenStickerSet(pack.setId);
                  }
                })

                // 封面贴纸：一包一行，取不到本地图的格子退回该贴纸自己的 emoji
                Grid() {
                  ForEach(pack.covers.slice(), (item: StickerSetItem) => {
                    GridItem() {
                      Row() {
                        if (stickerCellImagePath(item) !== null) {
                          Image(toSandboxUri(stickerCellImagePath(item)))
                            .width(56)
                            .height(56)
                            .objectFit(ImageFit.Contain)
                        } else {
                          Text(item.emoji.length > 0 ? item.emoji : '⭐️')
                            .fontSize(40)
                        }
                      }
                      .width('100%')
                      .height(68)
                      .justifyContent(FlexAlign.Center)
                      .alignItems(VerticalAlign.Center)
                      .borderRadius(this.T.radius.sm)
                      .onClick(() => {
                        if (this.onSendSticker) {
                          this.onSendSticker(item);
                        }
                      })
                    }
                  }, (item: StickerSetItem) => stickerCellKey(item))
                }
                .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
                .rowsGap(2)
                .columnsGap(2)
                .width('100%')
                .height(72)
                .scrollBar(BarState.Off)
                .enableScrollInteraction(false)
              }
              .width('100%')
            }
          }, (pack: StickerBoardPack) => stickerBoardPackKey(pack))
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 热门贴纸包区（STICKER-BOARD-102）：整包一行，动作就地完成 —— 与 Android 的
   * trending 区一致（`ChangeStickerSet` 直接装，不跳商店页）。
   *
   * 封面只是装饰：取不到图退回包名首字母，**不因为这个藏掉那一行**（入口本身是装包）。
   */
  @Builder
  StickerTrendingSection() {
    Column() {
      Text('热门贴纸包')
        .fontSize(this.T.typography.caption.fontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.T.colors.textSecondary)
        .width('100%')
        .padding({
          left: this.T.spacing.md,
          right: this.T.spacing.md,
          top: this.T.spacing.xs,
          bottom: 2
        })

      ForEach(this.stickerTrending, (row: StickerTrendingPack) => {
        Row() {
          if (row.coverPath !== null && row.coverPath.length > 0) {
            Image(toSandboxUri(row.coverPath))
              .width(44)
              .height(44)
              .objectFit(ImageFit.Contain)
          } else {
            Text(row.title.length > 0 ? row.title.substring(0, 1).toUpperCase() : '★')
              .fontSize(18)
              .fontColor(this.T.colors.textSecondary)
              .width(44)
              .height(44)
              .textAlign(TextAlign.Center)
          }

          Column() {
            Text(row.title)
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${row.totalSize} 张`)
              .fontSize(this.T.typography.caption.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: this.T.spacing.sm })

          Text(this.trendingActionLabel(row))
            .fontSize(this.T.typography.caption.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(row.isInstalled ? this.T.colors.textSecondary : this.T.colors.accent)
            .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm, top: 4, bottom: 4 })
            .onClick(() => {
              this.triggerTrendingAction(row);
            })
        }
        .width('100%')
        .height(56)
        .padding({ left: this.T.spacing.md, right: this.T.spacing.md })
        .alignItems(VerticalAlign.Center)
        .opacity(this.stickerInstallingSetId === row.setId ? 0.5 : 1)
        .onClick(() => {
          this.onOpenStickerSet(row.setId);
        })
      }, (row: StickerTrendingPack) => stickerTrendingKey(row))
    }
    .width('100%')
  }

  /**
   * 「添加中」优先于 `is_installed`：请求还在途时不能显示成已经装好了；
   * 且同一时刻只放行一包（重复点击会发出第二条 changeStickerSet）。
   */
  private trendingActionLabel(row: StickerTrendingPack): string {
    if (this.stickerInstallingSetId === row.setId) {
      return row.isInstalled ? '移除中…' : '添加中…';
    }
    return row.isInstalled ? '已添加' : '添加';
  }

  private triggerTrendingAction(row: StickerTrendingPack): void {
    if (this.stickerInstallingSetId !== null) {
      return;
    }
    if (row.isInstalled) {
      if (this.onUninstallStickerSet) {
        this.onUninstallStickerSet(row.setId);
      }
      return;
    }
    if (this.onInstallStickerSet) {
      this.onInstallStickerSet(row.setId);
    }
  }

  /**
   * 空板卡：加载中 / 读取失败 / 账号确实没装包，三种得说不同的话 ——
   * 把「请求失败」显示成「还没有安装贴纸包」会把用户支去完全错误的方向。
   */
  @Builder
  StickerBoardEmptyView() {
    Column() {
      if (this.stickerBoardLoading) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(this.T.colors.accent)
        Text('正在读取贴纸包…')
          .fontSize(this.T.typography.caption.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .margin({ top: this.T.spacing.xs })
      } else if (this.stickerBoardError !== null) {
        Text('贴纸包读取失败')
          .fontSize(this.T.typography.body.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.textPrimary)
        Text(this.stickerBoardError)
          .fontSize(this.T.typography.caption.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .margin({ top: this.T.spacing.xs })
        Text('重试')
          .fontSize(this.T.typography.caption.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.accent)
          .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm, top: 4, bottom: 4 })
          .margin({ top: this.T.spacing.sm })
          .onClick(() => {
            this.onStickerBoardVisible();
          })
      } else {
        Text('★')
          .fontSize(34)
          .opacity(0.35)
          .margin({ bottom: this.T.spacing.sm })
        Text('还没有安装贴纸包')
          .fontSize(this.T.typography.body.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.textPrimary)
        Text('点上方热门贴纸包的「添加」即可安装，安装后会出现在这里')
          .fontSize(this.T.typography.caption.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .textAlign(TextAlign.Center)
          .margin({ top: this.T.spacing.xs })
      }
    }
    .layoutWeight(1)
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 板卡实际渲染的块：最近使用（非空时）在最前，其后是真实包。 */
  private stickerBlocks(): StickerBoardPack[] {
    return stickerBoardBlocks(this.stickerPacks, this.recentStickers);
  }

  private getActiveGifs(): GifItem[] {
    const query: string = this.gifSearchQuery.trim().toLowerCase();
    if (query.length > 0) {
      const allGifs: GifItem[] = [];
      const categories: string[] = Object.keys(DEFAULT_GIF_PACKS);
      for (let i = 0; i < categories.length; i++) {
        const items: GifItem[] = DEFAULT_GIF_PACKS[categories[i]];
        for (let j = 0; j < items.length; j++) {
          const it: GifItem = items[j];
          if (it.title.toLowerCase().includes(query) || it.tag.toLowerCase().includes(query)) {
            allGifs.push(it);
          }
        }
      }
      return allGifs;
    }

    if (this.currentGifCategoryIndex === 0) {
      return this.recentGifs.slice();
    }
    const catName: string = GIF_CATEGORIES[this.currentGifCategoryIndex];
    return DEFAULT_GIF_PACKS[catName] !== undefined ? DEFAULT_GIF_PACKS[catName].slice() : [];
  }

  /** GIF-101：GIF 动图搜索面板与动图发送 */
  @Builder
  GifView() {
    Column() {
      // 1. 顶部动图搜索栏
      Row() {
        Text('🔍')
          .fontSize(14)
          .margin({ left: 10, right: 6 })

        TextInput({ placeholder: 'Search GIFs', text: this.gifSearchQuery })
          .layoutWeight(1)
          .height('100%')
          .fontSize(this.T.typography.caption.fontSize)
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => {
            this.gifSearchQuery = value;
          })

        if (this.gifSearchQuery.length > 0) {
          Text('✕')
            .fontSize(14)
            .fontColor(this.T.colors.textSecondary)
            .margin({ right: 10 })
            .onClick(() => {
              this.gifSearchQuery = '';
            })
        }
      }
      .width('100%')
      .height(36)
      .margin({ left: this.T.spacing.md, right: this.T.spacing.md, top: this.T.spacing.xs, bottom: 4 })
      .backgroundColor(this.T.colors.surfaceVariant)
      .borderRadius(this.T.radius.full)
      .alignItems(VerticalAlign.Center)

      // 2. 动图热门分类胶囊滚动条（搜索态隐藏）
      if (this.gifSearchQuery.trim().length === 0) {
        List({ space: 8 }) {
          ForEach(GIF_CATEGORIES, (cat: string, index: number) => {
            ListItem() {
              Row() {
                Text(cat)
                  .fontSize(13)
                  .fontWeight(this.currentGifCategoryIndex === index ? FontWeight.Bold : FontWeight.Normal)
                  .fontColor(this.currentGifCategoryIndex === index ? '#FFFFFF' : this.T.colors.textSecondary)
              }
              .height(28)
              .padding({ left: 12, right: 12 })
              .backgroundColor(this.currentGifCategoryIndex === index ? this.T.colors.accent : this.T.colors.surfaceVariant)
              .borderRadius(this.T.radius.full)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.currentGifCategoryIndex = index;
              })
            }
          })
        }
        .listDirection(Axis.Horizontal)
        .height(36)
        .width('100%')
        .padding({ left: this.T.spacing.md, right: this.T.spacing.md })
        .scrollBar(BarState.Off)
      }

      // 3. 标题与清空栏
      Row() {
        if (this.gifSearchQuery.trim().length > 0) {
          Text(`Search results (${this.getActiveGifs().length})`)
            .fontSize(this.T.typography.caption.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.T.colors.textSecondary)
        } else if (this.currentGifCategoryIndex === 0) {
          Text('Recent GIFs')
            .fontSize(this.T.typography.caption.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.T.colors.textSecondary)
        } else {
          Text(`${GIF_CATEGORIES[this.currentGifCategoryIndex]} · ${this.getActiveGifs().length} GIFs`)
            .fontSize(this.T.typography.caption.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.T.colors.textSecondary)
        }

        Blank()

        if (this.currentGifCategoryIndex === 0 && this.recentGifs.length > 0 && this.gifSearchQuery.trim().length === 0) {
          Text('Clear')
            .fontSize(this.T.typography.caption.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.T.colors.accent)
            .onClick(() => {
              if (this.onClearRecentGifs) {
                this.onClearRecentGifs();
              }
            })
        }
      }
      .width('100%')
      .height(28)
      .padding({ left: this.T.spacing.md, right: this.T.spacing.md })
      .alignItems(VerticalAlign.Center)

      // 4. 网格区或空态
      if (this.currentGifCategoryIndex === 0 && this.recentGifs.length === 0 && this.gifSearchQuery.trim().length === 0) {
        Column() {
          Text('🕒')
            .fontSize(44)
            .margin({ bottom: this.T.spacing.sm })
          Text('No Recent GIFs')
            .fontSize(this.T.typography.body.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.T.colors.textPrimary)
            .margin({ bottom: 4 })
          Text('GIFs you send will appear here')
            .fontSize(this.T.typography.caption.fontSize)
            .fontColor(this.T.colors.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Grid() {
          ForEach(this.getActiveGifs(), (gif: GifItem) => {
            GridItem() {
              Stack({ alignContent: Alignment.BottomStart }) {
                Column() {
                  Text(gif.previewEmoji)
                    .fontSize(38)
                    .margin({ bottom: 4 })
                  Text(gif.title)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.T.colors.textPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)

                Row() {
                  Text('GIF')
                    .fontSize(10)
                    .fontWeight(FontWeight.Bold)
                    .fontColor('#FFFFFF')
                }
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .backgroundColor('#66000000')
                .borderRadius(4)
                .margin({ left: 6, bottom: 6 })
              }
              .width('100%')
              .height(100)
              .backgroundColor(this.T.colors.surfaceVariant)
              .borderRadius(this.T.radius.md)
              .onClick(() => {
                if (this.onSendGif) {
                  this.onSendGif(gif);
                }
              })
            }
          })
        }
        .columnsTemplate('1fr 1fr')
        .rowsGap(8)
        .columnsGap(8)
        .padding({
          left: this.T.spacing.md,
          right: this.T.spacing.md,
          bottom: this.T.spacing.md
        })
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }
}
