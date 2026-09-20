/**
 * feature/chat — 贴纸包详情与预览状态（STICKER-PREVIEW-101）。
 *
 * 承载点击聊天内贴纸或表情板贴纸包时的详情预览弹窗数据：
 * - 贴纸包元信息：setId, title, name, isInstalled, isArchived, isOfficial
 * - 贴纸列表：stickers (StickerSetItem[])
 * - 交互状态：isLoading (初始拉取中), isChanging (安装/移除进行中), errorMessage
 */

export interface StickerSetItem {
  readonly id: number;
  readonly fileId: number;
  readonly emoji: string;
  readonly width: number;
  readonly height: number;
  readonly localPath: string | null;
  readonly thumbnailPath: string | null;
  readonly isDownloaded: boolean;
  readonly isDownloading: boolean;
}

export class StickerSetPreviewState {
  readonly setId: string;
  readonly title: string;
  readonly name: string;
  readonly isInstalled: boolean;
  readonly isArchived: boolean;
  readonly isOfficial: boolean;
  readonly stickers: StickerSetItem[];
  readonly isLoading: boolean;
  readonly isChanging: boolean;
  readonly errorMessage: string | null;

  constructor(
    setId: string = '',
    title: string = '',
    name: string = '',
    isInstalled: boolean = false,
    isArchived: boolean = false,
    isOfficial: boolean = false,
    stickers: StickerSetItem[] = [],
    isLoading: boolean = false,
    isChanging: boolean = false,
    errorMessage: string | null = null
  ) {
    this.setId = setId;
    this.title = title;
    this.name = name;
    this.isInstalled = isInstalled;
    this.isArchived = isArchived;
    this.isOfficial = isOfficial;
    this.stickers = stickers;
    this.isLoading = isLoading;
    this.isChanging = isChanging;
    this.errorMessage = errorMessage;
  }

  copyWith(
    title?: string,
    name?: string,
    isInstalled?: boolean,
    isArchived?: boolean,
    isOfficial?: boolean,
    stickers?: StickerSetItem[],
    isLoading?: boolean,
    isChanging?: boolean,
    errorMessage?: string | null
  ): StickerSetPreviewState {
    return new StickerSetPreviewState(
      this.setId,
      title !== undefined ? title : this.title,
      name !== undefined ? name : this.name,
      isInstalled !== undefined ? isInstalled : this.isInstalled,
      isArchived !== undefined ? isArchived : this.isArchived,
      isOfficial !== undefined ? isOfficial : this.isOfficial,
      stickers !== undefined ? stickers : this.stickers,
      isLoading !== undefined ? isLoading : this.isLoading,
      isChanging !== undefined ? isChanging : this.isChanging,
      errorMessage !== undefined ? errorMessage : this.errorMessage
    );
  }
}

/** STICKER-101：贴纸包元信息与内部贴纸集合（对标 Telegram X StickerSection 体系） */
export interface StickerPack {
  readonly id: string;
  readonly title: string;
  readonly icon: string;
  readonly stickers: StickerSetItem[];
}

const MAKE_STICKER = (id: number, emoji: string): StickerSetItem => ({
  id: id,
  fileId: id,
  emoji: emoji,
  width: 512,
  height: 512,
  localPath: null,
  thumbnailPath: null,
  isDownloaded: true,
  isDownloading: false
});

/** STICKER-101：默认内置贴纸包 */
export const DEFAULT_STICKER_PACKS: StickerPack[] = [
  {
    id: '1',
    title: 'Hot Cherry',
    icon: '🔥',
    stickers: [
      MAKE_STICKER(1001, '🔥'),
      MAKE_STICKER(1002, '🎉'),
      MAKE_STICKER(1003, '🚀'),
      MAKE_STICKER(1004, '😎'),
      MAKE_STICKER(1005, '👍'),
      MAKE_STICKER(1006, '❤️'),
      MAKE_STICKER(1007, '☕'),
      MAKE_STICKER(1008, '⭐'),
      MAKE_STICKER(1009, '👏'),
      MAKE_STICKER(1010, '🥳'),
      MAKE_STICKER(1011, '🌟'),
      MAKE_STICKER(1012, '🎯'),
      MAKE_STICKER(1013, '🏆'),
      MAKE_STICKER(1014, '💡'),
      MAKE_STICKER(1015, '✨')
    ]
  },
  {
    id: '2',
    title: 'Cute Animals',
    icon: '🐱',
    stickers: [
      MAKE_STICKER(1016, '🐱'),
      MAKE_STICKER(1017, '🐶'),
      MAKE_STICKER(1018, '🐼'),
      MAKE_STICKER(1019, '🦊'),
      MAKE_STICKER(1020, '🐰'),
      MAKE_STICKER(1021, '🐻'),
      MAKE_STICKER(1022, '🐨'),
      MAKE_STICKER(1023, '🐯'),
      MAKE_STICKER(1024, '🦁'),
      MAKE_STICKER(1025, '🐸'),
      MAKE_STICKER(1026, '🐵'),
      MAKE_STICKER(1027, '🐧'),
      MAKE_STICKER(1028, '🐥'),
      MAKE_STICKER(1029, '🦄'),
      MAKE_STICKER(1030, '🐙')
    ]
  },
  {
    id: '3',
    title: 'Cool Moods',
    icon: '😎',
    stickers: [
      MAKE_STICKER(1031, '🤩'),
      MAKE_STICKER(1032, '🤠'),
      MAKE_STICKER(1033, '😇'),
      MAKE_STICKER(1034, '🤔'),
      MAKE_STICKER(1035, '🧐'),
      MAKE_STICKER(1036, '🤫'),
      MAKE_STICKER(1037, '🤭'),
      MAKE_STICKER(1038, '🤯'),
      MAKE_STICKER(1039, '🥱'),
      MAKE_STICKER(1040, '🤤'),
      MAKE_STICKER(1041, '😋'),
      MAKE_STICKER(1042, '😜'),
      MAKE_STICKER(1043, '🤪'),
      MAKE_STICKER(1044, '🥳'),
      MAKE_STICKER(1045, '😴')
    ]
  }
];

/** STICKER-101：默认最近使用贴纸 */
export const DEFAULT_RECENT_STICKERS: readonly StickerSetItem[] = [
  MAKE_STICKER(1001, '🔥'),
  MAKE_STICKER(1004, '😎'),
  MAKE_STICKER(1018, '🐼'),
  MAKE_STICKER(1002, '🎉'),
  MAKE_STICKER(1006, '❤️')
];

