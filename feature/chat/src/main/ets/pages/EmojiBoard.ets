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

import { LightTheme } from '@tgx/core-design-system';
import { StickerSetItem, StickerPack, DEFAULT_STICKER_PACKS } from '../model/StickerSetPreviewState';
import { GifItem, GIF_CATEGORIES, DEFAULT_RECENT_GIFS, DEFAULT_GIF_PACKS } from '../model/GifItem';

const T = LightTheme;

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

/** STICKER-101：贴纸包 Tab 图标（0 为 Recent 最近使用） */
const STICKER_PACK_TABS: string[] = ['🕒', '🔥', '🐱', '😎'];

@Component
export struct EmojiBoard {
  onSelectEmoji: (emoji: string) => void = () => {};
  onDeleteChar: () => void = () => {};
  onSelectSticker: (emoji: string) => void = () => {};
  onSendSticker?: (item: StickerSetItem) => void;
  onClearRecentStickers?: () => void;
  onSendGif?: (item: GifItem) => void;
  onClearRecentGifs?: () => void;
  onOpenStickerSet: (setId: string) => void = () => {};
  onClearRecent?: () => void;

  /** EMOJI-101：由父层回灌的最近使用表情列表 */
  @Prop recentEmojis: string[] = [];
  /** STICKER-101：由父层回灌的最近使用贴纸列表 */
  @Prop recentStickers: StickerSetItem[] = [];
  /** GIF-101：由父层回灌的最近使用动图列表 */
  @Prop recentGifs: GifItem[] = [];

  @State currentMainTab: string = 'emoji';
  @State currentEmojiCategory: number = 0;
  @State currentStickerPackIndex: number = 0;
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
              .fillColor(this.currentMainTab === 'emoji' ? T.colors.accent : T.colors.textSecondary)
          }
          .height('100%')
          .padding({ left: T.spacing.md, right: T.spacing.md })
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
              .fillColor(this.currentMainTab === 'sticker' ? T.colors.accent : T.colors.textSecondary)
          }
          .height('100%')
          .padding({ left: T.spacing.md, right: T.spacing.md })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.currentMainTab = 'sticker';
          })

          // GIF Tab
          Row() {
            Image($r('app.media.ic_gif'))
              .width(22)
              .height(22)
              .fillColor(this.currentMainTab === 'gif' ? T.colors.accent : T.colors.textSecondary)
          }
          .height('100%')
          .padding({ left: T.spacing.md, right: T.spacing.md })
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
            .fillColor(T.colors.textSecondary)
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
      .borderColor(T.colors.divider)
      .backgroundColor(T.colors.surface)
    }
    .width('100%')
    .height(280)
    .backgroundColor(T.colors.surface)
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
                .backgroundColor(this.currentEmojiCategory === index ? T.colors.accent : Color.Transparent)
                .borderRadius(1)
            }
            .padding({ left: T.spacing.sm, right: T.spacing.sm })
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
      .borderColor(T.colors.divider)

      // 表情主体展示区（分类 0 为 Recent，分类 1..7 为内置各组）
      if (this.currentEmojiCategory === 0) {
        if (this.recentEmojis.length > 0) {
          Column() {
            // Recent 顶栏（展示标题与清空入口）
            Row() {
              Text('Recent')
                .fontSize(T.typography.caption.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(T.colors.textSecondary)

              Blank()

              Text('Clear')
                .fontSize(T.typography.caption.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(T.colors.accent)
                .padding({ left: T.spacing.sm, right: T.spacing.sm, top: 4, bottom: 4 })
                .borderRadius(T.radius.sm)
                .onClick(() => {
                  if (this.onClearRecent) {
                    this.onClearRecent();
                  }
                })
            }
            .width('100%')
            .padding({ left: T.spacing.md, right: T.spacing.md, top: T.spacing.xs, bottom: T.spacing.xs })

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
                  .borderRadius(T.radius.sm)
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
              left: T.spacing.xs,
              right: T.spacing.xs,
              bottom: T.spacing.xs
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
              .margin({ bottom: T.spacing.sm })
            Text('No Recent Emojis')
              .fontSize(T.typography.body.fontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(T.colors.textPrimary)
            Text('Emojis you send will appear here')
              .fontSize(T.typography.caption.fontSize)
              .fontColor(T.colors.textSecondary)
              .margin({ top: T.spacing.xs })
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
              .borderRadius(T.radius.sm)
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
          left: T.spacing.xs,
          right: T.spacing.xs,
          top: T.spacing.xs,
          bottom: T.spacing.xs
        })
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 贴纸视图（STICKER-101）：贴纸包横向导航 + 5列大图网格 / 最近贴纸双模 */
  @Builder
  StickerView() {
    Column() {
      // 贴纸包分类横向滚动选择条：🕒 Recent + 🔥 Hot Cherry + 🐱 Cute Animals + 😎 Cool Moods
      Scroll() {
        Row() {
          ForEach(STICKER_PACK_TABS, (icon: string, index: number) => {
            Column() {
              Row() {
                Text(icon)
                  .fontSize(18)
                  .opacity(this.currentStickerPackIndex === index ? 1.0 : 0.45)
              }
              .height(34)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)

              // 选中高亮指示条
              Row()
                .width(28)
                .height(2)
                .backgroundColor(this.currentStickerPackIndex === index ? T.colors.accent : Color.Transparent)
                .borderRadius(1)
            }
            .padding({ left: T.spacing.sm, right: T.spacing.sm })
            .height(36)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.currentStickerPackIndex = index;
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
      .borderColor(T.colors.divider)

      // 贴纸主体展示区（分类 0 为 Recent，分类 1..3 为内置贴纸包）
      if (this.currentStickerPackIndex === 0) {
        if (this.recentStickers.length > 0) {
          Column() {
            // Recent 顶栏（展示标题与清空入口）
            Row() {
              Text('Recent Stickers')
                .fontSize(T.typography.caption.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(T.colors.textSecondary)

              Blank()

              Text('Clear')
                .fontSize(T.typography.caption.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(T.colors.accent)
                .padding({ left: T.spacing.sm, right: T.spacing.sm, top: 4, bottom: 4 })
                .borderRadius(T.radius.sm)
                .onClick(() => {
                  if (this.onClearRecentStickers) {
                    this.onClearRecentStickers();
                  }
                })
            }
            .width('100%')
            .padding({ left: T.spacing.md, right: T.spacing.md, top: T.spacing.xs, bottom: T.spacing.xs })

            // 最近使用贴纸网格 (5列，72vp高度)
            Grid() {
              ForEach(this.recentStickers.slice(), (item: StickerSetItem) => {
                GridItem() {
                  Row() {
                    Text(item.emoji)
                      .fontSize(44)
                  }
                  .width('100%')
                  .height(72)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(VerticalAlign.Center)
                  .borderRadius(T.radius.sm)
                  .onClick(() => {
                    if (this.onSendSticker) {
                      this.onSendSticker(item);
                    }
                    this.onSelectSticker(item.emoji);
                  })
                }
              })
            }
            .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
            .rowsGap(4)
            .columnsGap(4)
            .padding({
              left: T.spacing.xs,
              right: T.spacing.xs,
              bottom: T.spacing.xs
            })
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .height('100%')
        } else {
          // 最近贴纸为空时的优雅提示
          Column() {
            Text('🕒')
              .fontSize(38)
              .opacity(0.4)
              .margin({ bottom: T.spacing.sm })
            Text('No Recent Stickers')
              .fontSize(T.typography.body.fontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(T.colors.textPrimary)
            Text('Stickers you send will appear here')
              .fontSize(T.typography.caption.fontSize)
              .fontColor(T.colors.textSecondary)
              .margin({ top: T.spacing.xs })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      } else {
        // 内置贴纸包展示
        Column() {
          // 贴纸包顶部快捷预览条
          Row() {
            Row() {
              Text(DEFAULT_STICKER_PACKS[this.currentStickerPackIndex - 1].icon)
                .fontSize(18)
                .margin({ right: T.spacing.xs })
              Text(`${DEFAULT_STICKER_PACKS[this.currentStickerPackIndex - 1].title} · ${DEFAULT_STICKER_PACKS[this.currentStickerPackIndex - 1].stickers.length} stickers`)
                .fontSize(T.typography.caption.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(T.colors.textPrimary)
            }
            .layoutWeight(1)

            Row() {
              Text('查看贴纸包')
                .fontSize(T.typography.caption.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(T.colors.accent)
            }
            .padding({ left: T.spacing.sm, right: T.spacing.sm, top: 4, bottom: 4 })
            .backgroundColor(T.colors.surfaceVariant)
            .borderRadius(T.radius.full)
            .onClick(() => {
              this.onOpenStickerSet(DEFAULT_STICKER_PACKS[this.currentStickerPackIndex - 1].id);
            })
          }
          .width('100%')
          .padding({ left: T.spacing.md, right: T.spacing.md, top: T.spacing.xs, bottom: T.spacing.xs })
          .alignItems(VerticalAlign.Center)

          // 贴纸大图网格 (5列，72vp高度)
          Grid() {
            ForEach(DEFAULT_STICKER_PACKS[this.currentStickerPackIndex - 1].stickers.slice(), (item: StickerSetItem) => {
              GridItem() {
                Row() {
                  Text(item.emoji)
                    .fontSize(44)
                }
                .width('100%')
                .height(72)
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .borderRadius(T.radius.sm)
                .onClick(() => {
                  if (this.onSendSticker) {
                    this.onSendSticker(item);
                  }
                  this.onSelectSticker(item.emoji);
                })
              }
            })
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
          .rowsGap(4)
          .columnsGap(4)
          .padding({
            left: T.spacing.xs,
            right: T.spacing.xs,
            bottom: T.spacing.xs
          })
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
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
          .fontSize(T.typography.caption.fontSize)
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => {
            this.gifSearchQuery = value;
          })

        if (this.gifSearchQuery.length > 0) {
          Text('✕')
            .fontSize(14)
            .fontColor(T.colors.textSecondary)
            .margin({ right: 10 })
            .onClick(() => {
              this.gifSearchQuery = '';
            })
        }
      }
      .width('100%')
      .height(36)
      .margin({ left: T.spacing.md, right: T.spacing.md, top: T.spacing.xs, bottom: 4 })
      .backgroundColor(T.colors.surfaceVariant)
      .borderRadius(T.radius.full)
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
                  .fontColor(this.currentGifCategoryIndex === index ? '#FFFFFF' : T.colors.textSecondary)
              }
              .height(28)
              .padding({ left: 12, right: 12 })
              .backgroundColor(this.currentGifCategoryIndex === index ? T.colors.accent : T.colors.surfaceVariant)
              .borderRadius(T.radius.full)
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
        .padding({ left: T.spacing.md, right: T.spacing.md })
        .scrollBar(BarState.Off)
      }

      // 3. 标题与清空栏
      Row() {
        if (this.gifSearchQuery.trim().length > 0) {
          Text(`Search results (${this.getActiveGifs().length})`)
            .fontSize(T.typography.caption.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(T.colors.textSecondary)
        } else if (this.currentGifCategoryIndex === 0) {
          Text('Recent GIFs')
            .fontSize(T.typography.caption.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(T.colors.textSecondary)
        } else {
          Text(`${GIF_CATEGORIES[this.currentGifCategoryIndex]} · ${this.getActiveGifs().length} GIFs`)
            .fontSize(T.typography.caption.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(T.colors.textSecondary)
        }

        Blank()

        if (this.currentGifCategoryIndex === 0 && this.recentGifs.length > 0 && this.gifSearchQuery.trim().length === 0) {
          Text('Clear')
            .fontSize(T.typography.caption.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(T.colors.accent)
            .onClick(() => {
              if (this.onClearRecentGifs) {
                this.onClearRecentGifs();
              }
            })
        }
      }
      .width('100%')
      .height(28)
      .padding({ left: T.spacing.md, right: T.spacing.md })
      .alignItems(VerticalAlign.Center)

      // 4. 网格区或空态
      if (this.currentGifCategoryIndex === 0 && this.recentGifs.length === 0 && this.gifSearchQuery.trim().length === 0) {
        Column() {
          Text('🕒')
            .fontSize(44)
            .margin({ bottom: T.spacing.sm })
          Text('No Recent GIFs')
            .fontSize(T.typography.body.fontSize)
            .fontWeight(FontWeight.Bold)
            .fontColor(T.colors.textPrimary)
            .margin({ bottom: 4 })
          Text('GIFs you send will appear here')
            .fontSize(T.typography.caption.fontSize)
            .fontColor(T.colors.textSecondary)
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
                    .fontColor(T.colors.textPrimary)
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
              .backgroundColor(T.colors.surfaceVariant)
              .borderRadius(T.radius.md)
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
          left: T.spacing.md,
          right: T.spacing.md,
          bottom: T.spacing.md
        })
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
  }
}
