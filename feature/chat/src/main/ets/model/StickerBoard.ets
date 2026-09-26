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
 * 最近使用一行的格子数上限。Android 折叠态显示 10 张、点「展开」铺完
 * （`config/Config.java:194` DEFAULT_SHOW_RECENT_STICKERS_COUNT、
 * `ui/EmojiMediaListController.java:877-883`）；本端没有折叠档，所以取一个能一次滚完、
 * 又不会把 Grid 铺爆的数（TDLib 服务端给的列表上限是 200，全铺等于把首帧交给两百个 Image）。
 */
export const STICKER_BOARD_RECENT_MAX: number = 20;

/**
 * ArkUI `Image` 解不了的格式。TDLib 把动效贴纸（Lottie）当普通文件落盘，扩展名 `.tgs`
 * 内容是 gzip 过的 JSON —— Android 有 rlottie 能播（`TgsPlayer`），本端没有对应解码器，
 * 直接喂给 Image 只会得到一块**空白**：看起来像「图没下下来」，其实是根本解不了。
 * 所以这些路径一律当作「没有图」，退回包名首字母 / 贴纸自己的 emoji。
 *
 * 判据只能落在**已下盘的本地路径**上：本端用的 TDLib `file` DTO 没有 name/extension
 * 字段，下载前无从得知格式（于是可能白下一张 .tgs，预算已把这种浪费限死在几十张内）。
 */
const STICKER_NON_RASTER_SUFFIXES: string[] = ['tgs', 'json', 'lottie', 'mp4', 'mov', 'm4v', 'webm', 'avi', 'mkv'];

/** 这个本地路径能不能交给 Image 渲染（未知扩展名按可以处理，别把正常的图误杀）。 */
export function stickerPathIsRenderable(path: string | null): boolean {
  if (path === null || path.length === 0) {
    return false;
  }
  const dot: number = path.lastIndexOf('.');
  if (dot < 0 || dot === path.length - 1) {
    return true;
  }
  const suffix: string = path.substring(dot + 1).toLowerCase();
  for (let i = 0; i < STICKER_NON_RASTER_SUFFIXES.length; i++) {
    if (STICKER_NON_RASTER_SUFFIXES[i] === suffix) {
      return false;
    }
  }
  return true;
}

/**
 * 热门区最多几包，且**每行只登记一张封面**（不像已装包那样一包五格）。
 * 一次页签打开的总下载因此是「已装盘预算 30 + 热门 6」，而不是把两个榜都铺成网格。
 */
export const STICKER_TRENDING_MAX_PACKS: number = 6;

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
    if (path !== null && stickerPathIsRenderable(path)) {
      return path;
    }
  }
  for (let i = 0; i < info.covers.length; i++) {
    const coverThumb: File | null = stickerThumbnailFile(info.covers[i]);
    if (coverThumb !== null && coverThumb.id > 0) {
      const path: string | null = deps.localPathOf(coverThumb.id);
      if (path !== null && stickerPathIsRenderable(path)) {
        return path;
      }
    }
  }
  return null;
}

/**
 * 最近使用那一个伪包：不对应任何 setId，因此不能被点开成整包。
 *
 * 与真实包不同，这里**不截断**：真实包受 TDLib `covers` 的 5 张上限约束，而最近使用是
 * TDLib 自己的列表（`getRecentStickers`），Android 也是整段铺开（`EmojiMediaListController` 的 recent section）。
 */
export function stickerBoardRecentPack(items: readonly StickerSetItem[]): StickerBoardPack {
  const covers: StickerSetItem[] = items.slice(0);
  return new StickerBoardPack(
    STICKER_BOARD_RECENT_SET_ID,
    '最近使用',
    covers.length > 0 ? firstRenderablePath(covers[0]) : null,
    covers,
    items.length,
    false
  );
}

/**
 * `getRecentStickers(is_attached=false)` 的回包 → 最近使用那一行的格子。
 *
 * 顺序完全照 TDLib（它已经按「最近」排好，客户端不再二次排序），丢掉落不了地的 null 项，
 * 超过 `STICKER_BOARD_RECENT_MAX` 的部分**连下载都不登记** —— 上限外的格子根本不上屏。
 * 只登记缩略图：与真实包的格子同口径（板卡显示的是 512 以内的小图，原图等真发送时 TDLib 自己取）。
 */
export function recentStickersFromStickers(
  stickers: readonly Sticker[],
  deps: StickerBoardDeps
): StickerSetItem[] {
  const items: StickerSetItem[] = [];
  for (let i = 0; i < stickers.length && items.length < STICKER_BOARD_RECENT_MAX; i++) {
    const sticker: Sticker = stickers[i];
    const item: StickerSetItem | null = stickerItemFromSticker(sticker, deps);
    if (item === null) {
      continue;
    }
    const thumbFile: File | null = stickerThumbnailFile(sticker);
    if (thumbFile !== null && thumbFile.id > 0) {
      deps.download(thumbFile.id);
    }
    items.push(item);
  }
  return items;
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
  if (item.thumbnailPath !== null && stickerPathIsRenderable(item.thumbnailPath)) {
    return item.thumbnailPath;
  }
  return item.localPath !== null && stickerPathIsRenderable(item.localPath) ? item.localPath : null;
}

/** 格子该显示哪张图：原文件本地路径 → 缩略图本地路径 → 都没有则 null（由界面退回 emoji）。 */
export function stickerCellImagePath(item: StickerSetItem): string | null {
  if (item.localPath !== null && stickerPathIsRenderable(item.localPath)) {
    return item.localPath;
  }
  return item.thumbnailPath !== null && stickerPathIsRenderable(item.thumbnailPath) ? item.thumbnailPath : null;
}

/** ForEach 键：路径必须进键，否则「图刚下载好」那一帧不会重建 Image（与预览弹层同一口径）。 */
export function stickerCellKey(item: StickerSetItem): string {
  const path: string | null = stickerCellImagePath(item);
  return `${item.fileId}_${path === null ? '' : path}`;
}

/**
 * 板卡一整行的 ForEach 键：`setId` + 每一格当前画的是哪张图。
 *
 * ArkUI 对同键项**沿用旧子树**，不会重跑 itemBuilder —— 所以只写 `pack.setId` 时，
 * 缩略图到货后那一整行（含内层格子的 ForEach）都还是首帧的 emoji 兜底。
 * 设备实测：包条那一栏的键含路径，正常显示独角兽；同一份数据的整行却停在 😂。
 */
export function stickerBoardPackKey(pack: StickerBoardPack): string {
  let signature: string = '';
  for (let i = 0; i < pack.covers.length; i++) {
    signature += `/${stickerCellKey(pack.covers[i])}`;
  }
  return `${pack.setId}_${signature}`;
}

/**
 * 按 setId 在几组 `StickerSetInfo` 里找包名（TDLib 的短名 `name`）；找不到返回 ''。
 *
 * 为什么预览弹层需要短名：`getStickerSet(set_id)` 在 TDLib 里不是本地查表，它会拿
 * `inputStickerSetID(id, access_hash)` 实发一次 `messages.getStickerSet`，而列表接口
 * （已装盘 / 热门榜）给到的那一层缓存并不带可用的 access_hash —— 设备实测：对真实包
 * （含已安装的）恒返回 `406 STICKERSET_INVALID`，也就是预览从来没出过图。
 * `searchStickerSet(name)` 走的是 `inputStickerSetShortName`，与 Telegram X 的
 * `MessagesController.loadStickerSet(shortName)` 同一条路，回的同样是完整 `StickerSet`。
 *
 * 只在**本地已经见过**这一包时才拿得到短名（板卡 / 榜单的 DTO 缓存），所以调用方仍要
 * 保留按 id 的兜底：消息气泡那种只有 `stickerSetId` 的入口没有名字可用。
 *
 * 另记一条设备实测（2026-09-26，PROGRESS 第十五轮）：短名那条路在本机同样回
 * `406 STICKERSET_INVALID` —— 已安装、t.me 公开可访问的包（`ConcernedFroge`）也一样，
 * 而同一个 id + access_hash 走 `changeStickerSet` 装包是成功的。也就是这两条查询在本
 * build 的 TDLib/服务端组合下都拿不到整包，不是短名算错。取值链按 id → 短名依次兜底，
 * 两个都失败才报错；预览要真出图得先解决这一层（native 侧）。
 */
export function stickerSetShortNameOf(
  groups: readonly (readonly StickerSetInfo[])[],
  setId: string
): string {
  for (let g = 0; g < groups.length; g++) {
    const group: readonly StickerSetInfo[] = groups[g];
    for (let i = 0; i < group.length; i++) {
      if (group[i].id === setId && group[i].name.length > 0) {
        return group[i].name;
      }
    }
  }
  return '';
}

/**
 * 热门贴纸包里的一行（STICKER-BOARD-102）。
 *
 * 与已装包那一种行不同：这里只给一张封面 + 一个「添加」，不铺五格 —— Android 的
 * trending 区（`EmojiLayoutTrendingController` + `MediaStickersAdapter` 的
 * `TYPE_HEADER_TRENDING`）也是整包一张图，点开才进整包详情。
 */
export class StickerTrendingPack {
  readonly setId: string;
  readonly title: string;
  readonly coverPath: string | null;
  readonly totalSize: number;
  readonly isInstalled: boolean;

  constructor(
    setId: string,
    title: string,
    coverPath: string | null,
    totalSize: number,
    isInstalled: boolean
  ) {
    this.setId = setId;
    this.title = title;
    this.coverPath = coverPath;
    this.totalSize = totalSize;
    this.isInstalled = isInstalled;
  }
}

/**
 * `getTrendingStickerSets` 的回包 → 热门区。
 *
 * **不跳过没有封面的包**（与已装板卡相反）：这一行的动作是「装包」，封面只是装饰，
 * 因为取不到图就把一个能装的包藏掉，等于把入口本身弄丢。
 */
export function stickerTrendingPacksFromSetInfos(
  sets: readonly StickerSetInfo[],
  deps: StickerBoardDeps
): StickerTrendingPack[] {
  const rows: StickerTrendingPack[] = [];
  for (let i = 0; i < sets.length && rows.length < STICKER_TRENDING_MAX_PACKS; i++) {
    const info: StickerSetInfo = sets[i];
    if (info.id === '' || info.id === '0') {
      continue;
    }
    rows.push(new StickerTrendingPack(
      info.id,
      info.title,
      stickerTrendingCoverPath(info, deps),
      info.size,
      info.is_installed
    ));
  }
  return rows;
}

/** 行图取值同页签条（包 thumbnail → 首个封面 thumbnail），拿不到就顺手登记那一张。 */
export function stickerTrendingCoverPath(info: StickerSetInfo, deps: StickerBoardDeps): string | null {
  const candidates: number[] = trendingRowFileIds(info);
  for (let i = 0; i < candidates.length; i++) {
    const path: string | null = deps.localPathOf(candidates[i]);
    if (path !== null && path.length > 0) {
      // 下回来了但 ArkUI 解不了（.tgs）：换下一张候选，别把它当封面，也别再下一次。
      if (stickerPathIsRenderable(path)) {
        return path;
      }
      continue;
    }
    // 一行只登记一张：先来的那张没下过就等它到货，到货后由协调器重算这一区。
    deps.download(candidates[i]);
    return null;
  }
  return null;
}

/** 一行的候选图：包 thumbnail → 各封面 sticker 的 thumbnail（去重，保持 TDLib 给的顺序）。 */
function trendingRowFileIds(info: StickerSetInfo): number[] {
  const ids: number[] = [];
  const packThumb: File | null = thumbnailFileOf(info.thumbnail);
  if (packThumb !== null && packThumb.id > 0) {
    ids.push(packThumb.id);
  }
  for (let i = 0; i < info.covers.length; i++) {
    const coverThumb: File | null = stickerThumbnailFile(info.covers[i]);
    if (coverThumb !== null && coverThumb.id > 0 && ids.indexOf(coverThumb.id) < 0) {
      ids.push(coverThumb.id);
    }
  }
  return ids;
}

/** 装/卸成功后同步那一行：TDLib 的推送晚于本地结果，界面不能还挂着「添加」。 */
export function stickerTrendingWithInstalled(
  rows: readonly StickerTrendingPack[],
  setId: string,
  isInstalled: boolean
): StickerTrendingPack[] {
  return rows.map(
    (row: StickerTrendingPack): StickerTrendingPack => row.setId === setId
      ? new StickerTrendingPack(row.setId, row.title, row.coverPath, row.totalSize, isInstalled)
      : row
  );
}

/** ForEach 键：封面路径进键，图到货才会重建那一行。 */
export function stickerTrendingKey(row: StickerTrendingPack): string {
  return `${row.setId}_${row.coverPath === null ? '' : row.coverPath}_${row.isInstalled ? 1 : 0}`;
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
  readonly trending?: StickerTrendingPack[];
  readonly trendingRequested?: boolean;
  readonly installingSetId?: string | null;
  readonly recentRequested?: boolean;
}

export class StickerBoardState {
  readonly packs: StickerBoardPack[];
  readonly isLoading: boolean;
  /** 已经成功装过一次盘；决定页签打开时是否还要再发一次请求。 */
  readonly isLoaded: boolean;
  readonly errorMessage: string | null;
  /** 热门贴纸包（`getTrendingStickerSets`）：Android 也是直接铺在贴纸页里，没有商店页。 */
  readonly trending: StickerTrendingPack[];
  /**
   * 榜**问过了**（不等于问成功了）。榜单只是入口装饰，失败不重试、也不占错误槽位；
   * 真正让它重读的是装/卸一包 —— TDLib 的榜会把已装的那一包换掉。
   */
  readonly trendingRequested: boolean;
  /** 正在装/卸的那一包；只允许同时在途一包（重复点击不该发出第二条 changeStickerSet）。 */
  readonly installingSetId: string | null;
  /**
   * 最近使用**问过了**（同 `trendingRequested`：不等于问成功）。
   * 「一次会话内只问一次 TDLib」这条口径要和榜单、已装盘一致，否则反复切页签就是反复打网络。
   */
  readonly recentRequested: boolean;

  constructor(
    packs: StickerBoardPack[] = [],
    isLoading: boolean = false,
    isLoaded: boolean = false,
    errorMessage: string | null = null,
    trending: StickerTrendingPack[] = [],
    trendingRequested: boolean = false,
    installingSetId: string | null = null,
    recentRequested: boolean = false
  ) {
    this.packs = packs;
    this.isLoading = isLoading;
    this.isLoaded = isLoaded;
    this.errorMessage = errorMessage;
    this.trending = trending;
    this.trendingRequested = trendingRequested;
    this.installingSetId = installingSetId;
    this.recentRequested = recentRequested;
  }

  static initial(): StickerBoardState {
    return new StickerBoardState([], false, false, null, [], false, null, false);
  }

  copyWith(options: StickerBoardOptions): StickerBoardState {
    return new StickerBoardState(
      options.packs !== undefined ? options.packs : this.packs,
      options.isLoading !== undefined ? options.isLoading : this.isLoading,
      options.isLoaded !== undefined ? options.isLoaded : this.isLoaded,
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage,
      options.trending !== undefined ? options.trending : this.trending,
      options.trendingRequested !== undefined ? options.trendingRequested : this.trendingRequested,
      options.installingSetId !== undefined ? options.installingSetId : this.installingSetId,
      options.recentRequested !== undefined ? options.recentRequested : this.recentRequested
    );
  }

  /** 最近使用之外有没有真实包。空板卡 + 空最近才是 Android 的那句 NoStickerSets。 */
  hasPacks(): boolean {
    return this.packs.length > 0;
  }
}
