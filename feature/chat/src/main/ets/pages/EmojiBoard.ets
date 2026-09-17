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

const EMOJI_CATEGORIES: string[][] = [
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
    '🦀', '🐡', '🐠', '🐟', '🐬', '🐳', '鲨', '🐊', '🐅', '🐆',
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
  ]
];

const CATEGORY_ICONS: string[] = ['😀', '👋', '🐶', '🍔', '⚽', '❤'];

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
  onSelectEmoji: (emoji: string) => void = () => {};
  onDeleteChar: () => void = () => {};
  onSelectSticker: (emoji: string) => void = () => {};

  @State currentMainTab: string = 'emoji';
  @State currentEmojiCategory: number = 0;

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
        .width(44)
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

  /** 表情视图：分类横向条 + 8列 Emoji 网格 */
  @Builder
  EmojiView() {
    Column() {
      // 表情子分类选择条
      Row() {
        ForEach(CATEGORY_ICONS, (icon: string, index: number) => {
          Row() {
            Text(icon)
              .fontSize(18)
              .opacity(this.currentEmojiCategory === index ? 1.0 : 0.45)
          }
          .layoutWeight(1)
          .height(36)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .borderWidth({
            bottom: this.currentEmojiCategory === index ? 2 : 0
          })
          .borderColor(T.colors.accent)
          .onClick(() => {
            this.currentEmojiCategory = index;
          })
        })
      }
      .width('100%')
      .height(36)
      .borderWidth({ bottom: 1 })
      .borderColor(T.colors.divider)

      // 表情 8 列 Grid
      Grid() {
        ForEach(EMOJI_CATEGORIES[this.currentEmojiCategory], (emoji: string) => {
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
    .width('100%')
    .height('100%')
  }

  /** 贴纸视图：贴纸包与大尺寸表情预览 */
  @Builder
  StickerView() {
    Column() {
      Grid() {
        ForEach(SAMPLE_STICKERS, (item: StickerPreviewItem) => {
          GridItem() {
            Column() {
              Text(item.emoji)
                .fontSize(44)
                .margin({ bottom: T.spacing.xs })
              Text(item.title)
                .fontSize(T.typography.caption.fontSize)
                .fontColor(T.colors.textSecondary)
            }
            .width('100%')
            .height(96)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(T.colors.surfaceVariant)
            .borderRadius(T.radius.md)
            .onClick(() => {
              this.onSelectSticker(item.emoji);
              this.onSelectEmoji(item.emoji);
            })
          }
        })
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .rowsGap(T.spacing.sm)
      .columnsGap(T.spacing.sm)
      .padding(T.spacing.md)
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }

  /** GIF 动图视图：动图预览卡片 */
  @Builder
  GifView() {
    Column() {
      Grid() {
        ForEach(SAMPLE_GIFS, (gif: GifPreviewItem) => {
          GridItem() {
            Column() {
              Text(gif.tag)
                .fontSize(36)
                .margin({ bottom: T.spacing.xs })
              Text(gif.title)
                .fontSize(T.typography.caption.fontSize)
                .fontColor(T.colors.textPrimary)
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')
            .height(88)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(T.colors.surfaceVariant)
            .borderRadius(T.radius.md)
            .onClick(() => {
              this.onSelectEmoji(gif.tag);
            })
          }
        })
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsGap(T.spacing.sm)
      .columnsGap(T.spacing.sm)
      .padding(T.spacing.md)
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}
