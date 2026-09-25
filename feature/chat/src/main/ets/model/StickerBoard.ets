/**
 * feature/chat — 表情板贴纸页签的真实数据模型（STICKER-BOARD-101，FEAT-P2-004）。
 *
 * 数据源与版式对齐 Telegram X：贴纸页 = 最近使用（伪包）+ `getInstalledStickerSets(regular)`
 * 的每一包（`ui/EmojiMediaListController.java:1291-1391`），每包一行整宽标题 + 包内封面贴纸内联
 * （`MediaStickersAdapter.java:682-698`、`ui/EmojiMediaListController.java:1357-1372`），
 * 点标题行开整包页（`MediaStickersAdapter.java:268-270`）—— 本端即既有的贴纸包预览弹层。
 *
 * 不另发 `getStickerSet`：TDLib 的 `stickerSetInfo.covers` 本身就是「最多 5 张封面贴纸」，
 * 首屏要显示的就是这几张；整包内容留给点标题后的弹层（同 Android）。
 *
 * 与 Android 的两处有意偏差，都写在下面函数的注释里：包数上限、缩略图下载预算。
 *
 * 100% Kit-free：只吃生成 DTO 与注入的 pathOf / download，因此可全量单测。
 */

import { File, Sticker, StickerSetInfo, Thumbnail } from '@tgx/core-td-api-generated';
import { StickerSetItem } from './StickerSetPreviewState';

/**
 * 包数上限。Android 不限量（`EmojiMediaListController.java:1357-1372` 一路铺完），
 * 因为它按可见区域懒绑定；ArkUI 的 Grid 会把所有子项一次建出来，不设上限就等于
 * 把整账号的贴纸包一次性铺进首帧。
 */
export const STICKER_BOARD_MAX_PACKS: number = 8;

/** 每包展示的封面数上限（TDLib covers 本身就是「up to the first 5」）。 */
export const STICKER_BOARD_MAX_COVERS: number = 5;

/**
 * 一次装盘最多请求多少张缩略图。同 SHARED-AUDIO 那条教训：解析阶段给整页媒体逐个登记
 * 下载，一次页签切换就是几十路并发。超预算的格子退回显示这颗贴纸自己的 emoji（不是假图，
 * 是 TDLib 给的对应表情），发送链路不受影响（发的是 file id，TDLib 自己下载）。
 */
export const STICKER_BOARD_DOWNLOAD_BUDGET: number = 30;

/** 最近使用那一个伪包的 setId；它不对应任何真实 setId。 */
export const STICKER_BOARD_RECENT_SET_ID: string = 'recent';

/**
 * 解析一包所需的注入依赖：只读本地路径 + 登记一次低优先级下载。
 *
 * 路径是**装盘那一刻**从 FileRegistry 取的快照：某张图后来下好了，由协调器拿缓存的
 * `StickerSetInfo` 重新装一次盘（与预览弹层同一口径），模型里因此没有「按 fileId 补路径」
 * 的分支 —— 格子只带 thumbnail 的本地路径、不带它的 fileId，那种补丁对不上。
 */
export interface StickerBoardDeps {
  readonly localPathOf: (fileId: number) => string | null;
  readonly download: (fileId: number) => void;
}

/** 贴纸包在板卡上的一行：整宽标题 + 至多 5 张封面。 */
export class StickerBoardPack {
  readonly setId: string;
  readonly title: string;
  /** 页签条用的小图；TDLib 顺序：包 thumbnail → covers[0] 的 thumbnail → null（只剩首字母）。 */
  readonly thumbnailPath: string | null;
  readonly covers: StickerSetItem[];
  /** TDLib 声明的包内贴纸总数（板卡只铺封面，这个数字用来告诉用户整包还有多少）。 */
  readonly totalSize: number;
  /** 封面是否被截断（真实整包比板上显示的多）。 */
  readonly hasMore: boolean;

  constructor(
    setId: string,
    title: string,
    thumbnailPath: string | null,
    covers: StickerSetItem[],
    totalSize: number,
    hasMore: boolean
  ) {
    this.setId = setId;
    this.title = title;
    this.thumbnailPath = thumbnailPath;
    this.covers = covers;
    this.totalSize = totalSize;
    this.hasMore = hasMore;
  }
}

/**
 * 一颗 TDLib sticker → 板卡格子。
 *
 * 返回 null 的唯一条件是「没有可发送的文件句柄」（`sticker.sticker` 为 null 或 id 0）：
 * 那种格子点下去什么也发不出，宁可不上板。
 */
export function stickerItemFromSticker(sticker: Sticker, deps: StickerBoardDeps): StickerSetItem | null {
  const targetFile: File | null = sticker.sticker;
  if (targetFile === null || targetFile.id === 0) {
    return null;
  }
  const thumbFile: File | null = stickerThumbnailFile(sticker);
  const fileId: number = targetFile.id;
  const thumbId: number = thumbFile === null ? 0 : thumbFile.id;
  return {
    id: fileId,
    fileId: fileId,
    emoji: sticker.emoji,
    width: sticker.width,
    height: sticker.height,
    localPath: deps.localPathOf(fileId),
    thumbnailPath: thumbId > 0 ? deps.localPathOf(thumbId) : null,
    isDownloaded: false,
    isDownloading: false
  };
}

/** 整串 sticker → 格子；null 项被丢弃，其余保持 TDLib 给的顺序。 */
export function stickerItemsFromStickers(
  stickers: readonly Sticker[],
  deps: StickerBoardDeps,
  limit: number = STICKER_BOARD_MAX_COVERS
): StickerSetItem[] {
  const items: StickerSetItem[] = [];
  for (let i = 0; i < stickers.length && items.length < limit; i++) {
    const item: StickerSetItem | null = stickerItemFromSticker(stickers[i], deps);
    if (item !== null) {
      items.push(item);
    }
  }
  return items;
}

/**
 * `getInstalledStickerSets` 的回包 → 板卡包列表。
 *
 * 没有可用封面的包直接跳过：Android 会留一行标题再懒加载（`MediaStickersAdapter.java:306-311`），
 * 本端不做懒加载，留一个只有标题的空行比不显示这个包更容易被读成「坏了」。
 * 下载预算用完后格子退回 emoji，包本身仍然上板。
 */
export function stickerBoardPacksFromSetInfos(
  sets: readonly StickerSetInfo[],
  deps: StickerBoardDeps
): StickerBoardPack[] {
  const packs: StickerBoardPack[] = [];
  let budget: number = STICKER_BOARD_DOWNLOAD_BUDGET;
  for (let i = 0; i < sets.length && packs.length < STICKER_BOARD_MAX_PACKS; i++) {
    const info: StickerSetInfo = sets[i];
    if (info.id === '' || info.id === '0') {
      continue;
    }
    const covers: StickerSetItem[] = stickerItemsFromStickers(info.covers, deps);
    if (covers.length === 0) {
      continue;
    }
    if (budget > 0) {
      budget -= requestStickerBoardDownloads(info, deps);
    }
    packs.push(new StickerBoardPack(
      info.id,
      info.title,
      stickerBoardThumbnailPath(info, deps),
      covers,
      info.size,
      info.size > covers.length
    ));
  }
  return packs;
}

/**
 * 为一包登记需要下的图：包 thumbnail + 各 cover 的 thumbnail（不是贴纸原文件 ——
 * 板卡只显示 512 以内的小图，原文件等真发送时由 TDLib 取）。
 * 返回登记了几个 fileId，供上层扣下载预算。
 */
export function requestStickerBoardDownloads(info: StickerSetInfo, deps: StickerBoardDeps): number {
  let requested: number = 0;
  const packThumb: File | null = thumbnailFileOf(info.thumbnail);
  if (packThumb !== null && packThumb.id > 0) {
    deps.download(packThumb.id);
    requested++;
  }
  for (let i = 0; i < info.covers.length; i++) {
    const coverThumb: File | null = stickerThumbnailFile(info.covers[i]);
    if (coverThumb !== null && coverThumb.id > 0) {
      deps.download(coverThumb.id);
      requested++;
    }
  }
  return requested;
}

/** 页签条小图的取值顺序照 Android：包 thumbnail → covers[0] 的 thumbnail → 无（`TGStickerSetInfo.java:91-144`）。 */
export function stickerBoardThumbnailPath(info: StickerSetInfo, deps: StickerBoardDeps): string | null {
  const packThumb: File | null = thumbnailFileOf(info.thumbnail);
  if (packThumb !== null && packThumb.id > 0) {
    const path: string | null = deps.localPathOf(packThumb.id);
    if (path !== null && path.length > 0) {
      return path;
    }
  }
  for (let i = 0; i < info.covers.length; i++) {
    const coverThumb: File | null = stickerThumbnailFile(info.covers[i]);
    if (coverThumb !== null && coverThumb.id > 0) {
      const path: string | null = deps.localPathOf(coverThumb.id);
      if (path !== null && path.length > 0) {
        return path;
      }
    }
  }
  return null;
}

/**
 * 最近使用那一个伪包：不对应任何 setId，因此不能被点开成整包。
 *
 * 与真实包不同，这里**不截断**：真实包受 TDLib `covers` 的 5 张上限约束，而最近使用是本机
 * 攒出来的用户自己的列表，Android 也是整段铺开（`EmojiMediaListController` 的 recent section）。
 */
export function stickerBoardRecentPack(items: readonly StickerSetItem[]): StickerBoardPack {
  const covers: StickerSetItem[] = items.slice(0);
  return new StickerBoardPack(
    STICKER_BOARD_RECENT_SET_ID,
    'Recent Stickers',
    covers.length > 0 ? firstRenderablePath(covers[0]) : null,
    covers,
    items.length,
    false
  );
}

/**
 * 板卡实际渲染的块：最近使用（非空时）在最前，其后是真实包 —— Android 是同一张列表里的
 * 伪包在前（`ui/EmojiMediaListController.java:1313-1372`）。
 */
export function stickerBoardBlocks(packs: readonly StickerBoardPack[], recent: readonly StickerSetItem[]): StickerBoardPack[] {
  const blocks: StickerBoardPack[] = [];
  if (recent.length > 0) {
    blocks.push(stickerBoardRecentPack(recent));
  }
  for (let i = 0; i < packs.length; i++) {
    blocks.push(packs[i]);
  }
  return blocks;
}

function firstRenderablePath(item: StickerSetItem): string | null {
  if (item.thumbnailPath !== null && item.thumbnailPath.length > 0) {
    return item.thumbnailPath;
  }
  return item.localPath !== null && item.localPath.length > 0 ? item.localPath : null;
}

/** 格子该显示哪张图：原文件本地路径 → 缩略图本地路径 → 都没有则 null（由界面退回 emoji）。 */
export function stickerCellImagePath(item: StickerSetItem): string | null {
  if (item.localPath !== null && item.localPath.length > 0) {
    return item.localPath;
  }
  return item.thumbnailPath !== null && item.thumbnailPath.length > 0 ? item.thumbnailPath : null;
}

/** ForEach 键：路径必须进键，否则「图刚下载好」那一帧不会重建 Image（与预览弹层同一口径）。 */
export function stickerCellKey(item: StickerSetItem): string {
  const path: string | null = stickerCellImagePath(item);
  return `${item.fileId}_${path === null ? '' : path}`;
}

function thumbnailFileOf(thumbnail: Thumbnail | null): File | null {
  return thumbnail === null ? null : thumbnail.file;
}

function stickerThumbnailFile(sticker: Sticker): File | null {
  return thumbnailFileOf(sticker.thumbnail);
}

/** 一次装盘的进度表达：`isLoaded` 与 `isLoading` 分开，才有「装过但这次失败」这种状态。 */
export interface StickerBoardOptions {
  readonly packs?: StickerBoardPack[];
  readonly isLoading?: boolean;
  readonly isLoaded?: boolean;
  readonly errorMessage?: string | null;
}

export class StickerBoardState {
  readonly packs: StickerBoardPack[];
  readonly isLoading: boolean;
  /** 已经成功装过一次盘；决定页签打开时是否还要再发一次请求。 */
  readonly isLoaded: boolean;
  readonly errorMessage: string | null;

  constructor(
    packs: StickerBoardPack[] = [],
    isLoading: boolean = false,
    isLoaded: boolean = false,
    errorMessage: string | null = null
  ) {
    this.packs = packs;
    this.isLoading = isLoading;
    this.isLoaded = isLoaded;
    this.errorMessage = errorMessage;
  }

  static initial(): StickerBoardState {
    return new StickerBoardState([], false, false, null);
  }

  copyWith(options: StickerBoardOptions): StickerBoardState {
    return new StickerBoardState(
      options.packs !== undefined ? options.packs : this.packs,
      options.isLoading !== undefined ? options.isLoading : this.isLoading,
      options.isLoaded !== undefined ? options.isLoaded : this.isLoaded,
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage
    );
  }

  /** 最近使用之外有没有真实包。空板卡 + 空最近才是 Android 的那句 NoStickerSets。 */
  hasPacks(): boolean {
    return this.packs.length > 0;
  }
}
