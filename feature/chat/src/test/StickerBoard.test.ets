/**
 * feature/chat — 贴纸板装盘纯函数的单元测试（STICKER-BOARD-101）。
 *
 * 这里守的是「真实账号内容进板卡」的几条判定：
 * - covers 只取 TDLib 给的前 5 张、`size` 大于封面时要标出 `hasMore`（界面上「查看其余 N 张」
 *   直接吃这个差值，算错就是把用户的包数量说错）；
 * - 没有可发送文件句柄的贴纸**不能**上板（点下去发不出去的东西不该出现在发送入口）；
 * - 整包没有一张可用封面时跳过该包（本端不做 Android 的懒加载标题行）；
 * - 包数上限与下载预算：一次装盘最多 8 包 / 30 路下载（SHARED-AUDIO 那次页签切换并发几十路
 *   下载的教训），超预算必须停手，否则这个纯函数就是个下载风暴发生器；
 * - 缩略图取值顺序（包 thumbnail → 首张封面 thumbnail），以及 ForEach 键必须含路径 ——
 *   路径不进键，图刚下载好那一帧不会重建，板卡会永远停在 emoji 占位。
 *
 * STICKER-BOARD-102 补上热门区那几条：热门行**没有封面也要保留**（入口是装包，图只是装饰）、
 * 一包只登记那一张文件、包数上限、装/卸后只同步匹配那一行，以及行键随 `isInstalled` 变化。
 * 还有一条设备取证挖出来的：**解不了的格式不能当图用** —— 动效贴纸包的 thumbnail 往往是
 * .tgs（gzip 的 Lottie JSON），文件确实在盘上，但 ArkUI 的 Image 没有对应解码器，喂过去
 * 就是一块空白；必须跳过它换下一张候选，全都不行才退回包名首字母 / 贴纸自己的 emoji。
 *
 * STICKER-RECENT-101 接上「最近使用」的真实数据源（`getRecentStickers`）后，这里守的是：
 * 顺序**完全照 TDLib**（它自己按最近排，客户端二次排序就是把用户刚发的那颗挪走）、上限
 * `STICKER_BOARD_RECENT_MAX` 之外的格子连下载都不登记（上了屏才有资格占预算），以及沿用
 * 101 那条「没有可发送文件句柄就不上板」。伪包标题是中文界面文案，不是 `'Recent Stickers'`。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  File,
  Sticker,
  StickerSetInfo,
  Thumbnail
} from '@tgx/core-td-api-generated';
import {
  STICKER_BOARD_DOWNLOAD_BUDGET,
  STICKER_BOARD_MAX_COVERS,
  STICKER_BOARD_MAX_PACKS,
  STICKER_BOARD_RECENT_MAX,
  STICKER_BOARD_RECENT_SET_ID,
  STICKER_TRENDING_MAX_PACKS,
  StickerBoardDeps,
  StickerBoardPack,
  StickerTrendingPack,
  recentStickersFromStickers,
  requestStickerBoardDownloads,
  stickerBoardBlocks,
  stickerBoardPackKey,
  stickerBoardPacksFromSetInfos,
  stickerBoardRecentPack,
  stickerBoardThumbnailPath,
  stickerCellImagePath,
  stickerCellKey,
  stickerItemFromSticker,
  stickerItemsFromStickers,
  stickerPathIsRenderable,
  stickerSetShortNameOf,
  stickerTrendingCoverPath,
  stickerTrendingKey,
  stickerTrendingPacksFromSetInfos,
  stickerTrendingWithInstalled
} from '../main/ets/model/StickerBoard';
import { StickerSetItem } from '../main/ets/model/StickerSetPreviewState';

/** 造一个 file：只有 id 有意义，其余字段板卡不读。 */
function makeFile(id: number): File {
  const f: File = new File();
  f.id = id;
  return f;
}

/** 造一个 thumbnail：TDLib 里 thumbnail 带 file，file 可能为 null。 */
function makeThumbnail(id: number): Thumbnail {
  const t: Thumbnail = new Thumbnail();
  t.file = makeFile(id);
  return t;
}

/** 造一颗贴纸：stickerFileId 为 0 时把 sticker 置 null，用来测「无句柄」分支。 */
function makeSticker(setId: string, stickerFileId: number, thumbFileId: number, emoji: string): Sticker {
  const s: Sticker = new Sticker();
  s.set_id = setId;
  s.emoji = emoji;
  s.width = 512;
  s.height = 512;
  s.sticker = stickerFileId > 0 ? makeFile(stickerFileId) : null;
  s.thumbnail = thumbFileId > 0 ? makeThumbnail(thumbFileId) : null;
  return s;
}

function makeSetInfo(
  setId: string,
  title: string,
  size: number,
  covers: Sticker[],
  packThumbId: number
): StickerSetInfo {
  const info: StickerSetInfo = new StickerSetInfo();
  info.id = setId;
  info.title = title;
  info.size = size;
  info.covers = covers;
  info.thumbnail = packThumbId > 0 ? makeThumbnail(packThumbId) : null;
  return info;
}

/** 记录被登记过下载的 fileId，用来断言下载预算与「只下缩略图、不下原图」。 */
class RecordingDeps {
  readonly downloaded: number[] = [];
  private readonly paths: Map<number, string> = new Map();

  deps(): StickerBoardDeps {
    return {
      localPathOf: (fileId: number): string | null => {
        const hit: string | undefined = this.paths.get(fileId);
        return hit === undefined ? null : hit;
      },
      download: (fileId: number): void => {
        this.downloaded.push(fileId);
      }
    };
  }

  havePath(fileId: number, path: string): void {
    this.paths.set(fileId, path);
  }
}

function cover(setId: string, index: number): Sticker {
  return makeSticker(setId, 1000 + index, 2000 + index, '🐼');
}

export default function stickerBoardTest(): void {
  describe('StickerBoardTest', () => {

    it('packMapping_takesCoversAndMarksTruncation', 0, () => {
      const covers: Sticker[] = [cover('7', 1), cover('7', 2), cover('7', 3)];
      const rec = new RecordingDeps();
      const packs: StickerBoardPack[] = stickerBoardPacksFromSetInfos(
        [makeSetInfo('7', 'Pandamonium', 20, covers, 0)],
        rec.deps()
      );

      expect(packs.length).assertEqual(1);
      expect(packs[0].setId).assertEqual('7');
      expect(packs[0].title).assertEqual('Pandamonium');
      expect(packs[0].covers.length).assertEqual(3);
      expect(packs[0].totalSize).assertEqual(20);
      // 「其余多少张」是 UI 直接念给用户听的数字
      expect(packs[0].hasMore).assertTrue();
      expect(packs[0].covers.length < packs[0].totalSize).assertTrue();
    });

    it('coverLimit_neverExceedsTdLibCoverCap', 0, () => {
      const many: Sticker[] = [];
      for (let i = 1; i <= 12; i++) {
        many.push(cover('8', i));
      }
      const rec = new RecordingDeps();
      const packs: StickerBoardPack[] = stickerBoardPacksFromSetInfos(
        [makeSetInfo('8', 'Big', 40, many, 0)],
        rec.deps()
      );
      expect(packs[0].covers.length).assertEqual(STICKER_BOARD_MAX_COVERS);
    });

    it('stickerWithoutFileHandle_isDropped', 0, () => {
      const rec = new RecordingDeps();
      // 没有 sticker 文件 → 发不出去；id 为 0 同理（TDLib 不会给 0，防御性判定）
      const nullFile: Sticker = makeSticker('9', 0, 3001, '🔥');
      const zeroFile: Sticker = makeSticker('9', 0, 3002, '🎉');
      zeroFile.sticker = makeFile(0);
      expect(stickerItemFromSticker(nullFile, rec.deps())).assertNull();
      expect(stickerItemFromSticker(zeroFile, rec.deps())).assertNull();

      const items: StickerSetItem[] = stickerItemsFromStickers([nullFile, zeroFile], rec.deps());
      expect(items.length).assertEqual(0);

      // 整包一张都不可用 → 这个包不上板（不是渲染成只有标题的空行）
      const packs: StickerBoardPack[] = stickerBoardPacksFromSetInfos(
        [makeSetInfo('9', 'Broken', 5, [nullFile, zeroFile], 0)],
        rec.deps()
      );
      expect(packs.length).assertEqual(0);
    });

    it('invalidSetIds_areSkipped', 0, () => {
      const rec = new RecordingDeps();
      const packs: StickerBoardPack[] = stickerBoardPacksFromSetInfos(
        [
          makeSetInfo('', 'Empty id', 3, [cover('a', 1)], 0),
          makeSetInfo('0', 'Zero id', 3, [cover('b', 1)], 0),
          makeSetInfo('11', 'Real', 3, [cover('c', 1)], 0)
        ],
        rec.deps()
      );
      expect(packs.length).assertEqual(1);
      expect(packs[0].setId).assertEqual('11');
    });

    it('packCapAndDownloadBudget_areHardStops', 0, () => {
      const sets: StickerSetInfo[] = [];
      for (let i = 1; i <= 20; i++) {
        const covers: Sticker[] = [];
        for (let j = 1; j <= 5; j++) {
          covers.push(makeSticker(`${i}`, 100 + j, 1000 + i * 10 + j, '🙂'));
        }
        sets.push(makeSetInfo(`${i}`, `Pack ${i}`, 30, covers, 500 + i));
      }
      const rec = new RecordingDeps();
      const packs: StickerBoardPack[] = stickerBoardPacksFromSetInfos(sets, rec.deps());

      // ArkUI 的 Grid 会把所有子项一次建出来，不限量等于把整账号的包铺进首帧
      expect(packs.length).assertEqual(STICKER_BOARD_MAX_PACKS);
      expect(rec.downloaded.length).assertEqual(STICKER_BOARD_DOWNLOAD_BUDGET);
      const seen: Set<number> = new Set();
      for (let i = 0; i < rec.downloaded.length; i++) {
        seen.add(rec.downloaded[i]);
      }
      // 预算要真被扣住，而不是同一批 id 反复登记
      expect(seen.size).assertEqual(STICKER_BOARD_DOWNLOAD_BUDGET);
    });

    it('downloads_coverThumbnailsOnly_neverStickerFiles', 0, () => {
      const covers: Sticker[] = [makeSticker('3', 1001, 2001, '🐼'), makeSticker('3', 1002, 2002, '🎉')];
      const rec = new RecordingDeps();
      const requested: number = requestStickerBoardDownloads(makeSetInfo('3', 'X', 2, covers, 900), rec.deps());

      // 板卡只显示小图：原文件等真发送时由 TDLib 自己取
      expect(rec.downloaded.indexOf(1001)).assertEqual(-1);
      expect(rec.downloaded.indexOf(1002)).assertEqual(-1);
      expect(rec.downloaded.indexOf(900)).assertEqual(0);
      expect(rec.downloaded.length).assertEqual(3);
      expect(requested).assertEqual(3);
    });

    it('downloads_stopOnceBudgetIsSpent', 0, () => {
      const sets: StickerSetInfo[] = [];
      for (let i = 1; i <= 8; i++) {
        const covers: Sticker[] = [];
        for (let j = 1; j <= 5; j++) {
          covers.push(makeSticker(`${i}`, 100 + j, 4000 + i * 10 + j, '🙂'));
        }
        sets.push(makeSetInfo(`${i}`, `Pack ${i}`, 5, covers, 600 + i));
      }
      const rec = new RecordingDeps();
      // 8 包 × (1 包缩略图 + 5 封面缩略图) = 48 > 30：预算用完后的包必须不再登记下载，
      // 但包本身仍要上板（格子退回 emoji，不是把包藏起来）。
      const packs: StickerBoardPack[] = stickerBoardPacksFromSetInfos(sets, rec.deps());
      expect(packs.length).assertEqual(8);
      expect(rec.downloaded.length).assertEqual(STICKER_BOARD_DOWNLOAD_BUDGET);
    });

    it('thumbnailPath_prefersSetThumbnailThenFirstCover', 0, () => {
      const rec = new RecordingDeps();
      rec.havePath(900, '/data/sets/900.webp');
      rec.havePath(2001, '/data/covers/2001.webp');
      const covers: Sticker[] = [makeSticker('4', 1001, 2001, '🐼')];

      const withPackThumb: StickerSetInfo = makeSetInfo('4', 'A', 1, covers, 900);
      expect(stickerBoardThumbnailPath(withPackThumb, rec.deps())).assertEqual('/data/sets/900.webp');

      const withoutPackThumb: StickerSetInfo = makeSetInfo('4', 'A', 1, covers, 0);
      expect(stickerBoardThumbnailPath(withoutPackThumb, rec.deps())).assertEqual('/data/covers/2001.webp');

      // 一个本地路径都没有 → null，由界面退回包名首字母（不画假图）
      const fresh = new RecordingDeps();
      expect(stickerBoardThumbnailPath(withPackThumb, fresh.deps())).assertNull();
    });

    it('blocks_putRecentPseudoPackFirstAndKeepItUnopenable', 0, () => {
      const rec = new RecordingDeps();
      const packs: StickerBoardPack[] = stickerBoardPacksFromSetInfos(
        [makeSetInfo('21', 'Real', 2, [cover('21', 1), cover('21', 2)], 0)],
        rec.deps()
      );
      const recent: StickerSetItem[] = [{
        id: 1001,
        fileId: 1001,
        emoji: '🔥',
        width: 512,
        height: 512,
        localPath: null,
        thumbnailPath: null,
        isDownloaded: false,
        isDownloading: false
      }];

      const blocks: StickerBoardPack[] = stickerBoardBlocks(packs, recent);
      expect(blocks.length).assertEqual(2);
      expect(blocks[0].setId).assertEqual(STICKER_BOARD_RECENT_SET_ID);
      // 伪包不对应任何 setId：点开整包会去请求一个不存在的包
      expect(blocks[0].setId !== '21').assertTrue();
      expect(blocks[1].setId).assertEqual('21');

      // 最近使用为空时不留空行
      const noRecent: StickerBoardPack[] = stickerBoardBlocks(packs, []);
      expect(noRecent.length).assertEqual(1);
    });

    it('recentPack_showsTheWholeRecentList', 0, () => {
      const items: StickerSetItem[] = [];
      for (let i = 1; i <= 9; i++) {
        items.push({
          id: 100 + i,
          fileId: 100 + i,
          emoji: '🙂',
          width: 512,
          height: 512,
          localPath: null,
          thumbnailPath: null,
          isDownloaded: false,
          isDownloading: false
        });
      }
      const pack: StickerBoardPack = stickerBoardRecentPack(items);
      // 真实包受 TDLib covers 的 5 张上限约束；最近使用是本机自己攒的，整段铺开
      expect(pack.covers.length).assertEqual(9);
      expect(pack.hasMore).assertFalse();
      expect(pack.totalSize).assertEqual(9);
    });

    it('recentPack_titleIsTheUiHeader', 0, () => {
      // 这一行标题就是 EmojiBoard 那个整宽标题行念出来的字符串（`EmojiBoard.ets` 直接渲染
      // `pack.title`），所以它必须是界面语言，不是英文占位。
      const item: StickerSetItem = {
        id: 1,
        fileId: 1,
        emoji: '🐼',
        width: 512,
        height: 512,
        localPath: null,
        thumbnailPath: null,
        isDownloaded: false,
        isDownloading: false
      };
      const pack: StickerBoardPack = stickerBoardRecentPack([item]);
      expect(pack.title).assertEqual('最近使用');
      expect(pack.setId).assertEqual(STICKER_BOARD_RECENT_SET_ID);
    });

    it('recentStickers_keepsTdLibOrderAndDropsUnsendable', 0, () => {
      const rec = new RecordingDeps();
      rec.havePath(2001, '/data/recent/2001.webp');
      const stickers: Sticker[] = [
        makeSticker('3', 1001, 2001, '🐼'),
        makeSticker('3', 0, 2002, '🔥'),
        makeSticker('4', 1003, 2003, '🎉')
      ];
      const items: StickerSetItem[] = recentStickersFromStickers(stickers, rec.deps());

      expect(items.length).assertEqual(2);
      // TDLib 已经按「最近」排好；客户端二次排序就是把用户刚发出去的那颗挪走
      expect(items[0].fileId).assertEqual(1001);
      expect(items[1].fileId).assertEqual(1003);
      // 只登记缩略图：板卡显示的是小图，原文件等真发送时 TDLib 自己取
      expect(rec.downloaded.indexOf(2001)).assertEqual(0);
      expect(rec.downloaded.indexOf(1001)).assertEqual(-1);
      expect(rec.downloaded.indexOf(1003)).assertEqual(-1);
      // 丢掉的格子不占下载：那颗贴纸根本不上屏
      expect(rec.downloaded.indexOf(2002)).assertEqual(-1);
      // 已到货的缩略图直接进格子，首帧不用再等一次回灌
      expect(items[0].thumbnailPath).assertEqual('/data/recent/2001.webp');
    });

    it('recentStickers_capsAtDisplayMaxAndStopsRegisteringDownloads', 0, () => {
      const stickers: Sticker[] = [];
      for (let i = 1; i <= STICKER_BOARD_RECENT_MAX + 5; i++) {
        stickers.push(makeSticker('3', 100 + i, 500 + i, '🙂'));
      }
      const rec = new RecordingDeps();
      const items: StickerSetItem[] = recentStickersFromStickers(stickers, rec.deps());
      // TDLib 的列表上限是 200，ArkUI 的 Grid 会把所有子项一次建出来：
      // 显示上限必须在**登记下载之前**收口，否则一次开板就是两百路下载。
      expect(items.length).assertEqual(STICKER_BOARD_RECENT_MAX);
      expect(rec.downloaded.length).assertEqual(STICKER_BOARD_RECENT_MAX);
    });

    it('cellImage_fallsBackToLocalThenThumbnailThenNull', 0, () => {
      const base: StickerSetItem = {
        id: 1,
        fileId: 1,
        emoji: '🐼',
        width: 512,
        height: 512,
        localPath: '/data/local.webp',
        thumbnailPath: '/data/thumb.webp',
        isDownloaded: true,
        isDownloading: false
      };
      expect(stickerCellImagePath(base)).assertEqual('/data/local.webp');

      const thumbOnly: StickerSetItem = {
        id: 1,
        fileId: 1,
        emoji: '🐼',
        width: 512,
        height: 512,
        localPath: null,
        thumbnailPath: '/data/thumb.webp',
        isDownloaded: false,
        isDownloading: false
      };
      expect(stickerCellImagePath(thumbOnly)).assertEqual('/data/thumb.webp');

      const nothing: StickerSetItem = {
        id: 1,
        fileId: 1,
        emoji: '🐼',
        width: 512,
        height: 512,
        localPath: null,
        thumbnailPath: '',
        isDownloaded: false,
        isDownloading: false
      };
      expect(stickerCellImagePath(nothing)).assertNull();
    });

    it('cellImagePath_rejectsAnimatedThumbnailSoThePreviewFallsBackToEmoji', 0, () => {
      // 贴纸包预览弹层（STICKER-PREVIEW-101）：动效贴纸包的原图与缩略图在 TDLib 里
      // **都是** `.tgs`（设备实测 thumbnails 目录里就有 `*_1680977305.tgs`）。
      // 两条路径都画不开时必须返回 null，让界面退回这颗贴纸自己的 emoji ——
      // 返回任何一条都等于在弹层里再画一块空白。
      const animated: StickerSetItem = {
        id: 21,
        fileId: 21,
        emoji: '🦄',
        width: 128,
        height: 128,
        localPath: '/data/stickers/1052321353216032834.tgs',
        thumbnailPath: '/data/thumbnails/1052321353216032834_1680977305.tgs',
        isDownloaded: true,
        isDownloading: false
      };
      expect(stickerCellImagePath(animated)).assertNull();
    });

    it('shortNameOf_findsThePackAcrossGroups', 0, () => {
      // 预览取值链（STICKER-PREVIEW-101）：按 set_id 在板卡与热门榜两组缓存里找短名。
      // 找不到的那一包必须回空串，让调用方退回按 id 问 —— 拿别人的短名去查包更糟。
      const board: StickerSetInfo = makeSetInfo('7', 'Board Pack', 3, [], 0);
      board.name = 'BoardPack';
      const trending: StickerSetInfo = makeSetInfo('8', 'Trending Pack', 4, [], 0);
      trending.name = 'TrendingPack';
      const nameless: StickerSetInfo = makeSetInfo('9', 'No Name', 5, [], 0);

      expect(stickerSetShortNameOf([[board], [trending]], '8')).assertEqual('TrendingPack');
      expect(stickerSetShortNameOf([[board, trending]], '7')).assertEqual('BoardPack');
      expect(stickerSetShortNameOf([[board], [trending]], '404')).assertEqual('');
      expect(stickerSetShortNameOf([[nameless]], '9')).assertEqual('');
    });

    it('cellKey_changesWhenTheImageArrives', 0, () => {
      // 路径不进键 → 「图刚下载好」那一帧 ForEach 不重建，板卡会永远停在 emoji 占位
      const before: StickerSetItem = {
        id: 7,
        fileId: 7,
        emoji: '🎉',
        width: 512,
        height: 512,
        localPath: null,
        thumbnailPath: null,
        isDownloaded: false,
        isDownloading: false
      };
      const after: StickerSetItem = {
        id: 7,
        fileId: 7,
        emoji: '🎉',
        width: 512,
        height: 512,
        localPath: null,
        thumbnailPath: '/data/7.webp',
        isDownloaded: false,
        isDownloading: false
      };
      expect(stickerCellKey(before) === stickerCellKey(after)).assertFalse();
      expect(stickerCellKey(after).indexOf('/data/7.webp') >= 0).assertTrue();
    });

    it('packKey_changesWhenACellImageArrives', 0, () => {
      // 设备实测（STICKER-RECENT-101 取证）：包条那一栏的键含封面路径，缩略图到货后重建出 Image；
      // 同一份数据的整行只以 setId 为键 → ArkUI 沿用旧子树、不重跑 itemBuilder，
      // 于是内层格子明明已经能画图，屏上却永远停在首帧的 emoji 兜底。整行的键必须吃到每格当前的路径。
      const info: StickerSetInfo = makeSetInfo('77', 'Arrival', 3, [cover('77', 1), cover('77', 2)], 0);
      const before: RecordingDeps = new RecordingDeps();
      const after: RecordingDeps = new RecordingDeps();
      after.havePath(2001, '/data/2001.webp');
      const packBefore: StickerBoardPack = stickerBoardPacksFromSetInfos([info], before.deps())[0];
      const packAfter: StickerBoardPack = stickerBoardPacksFromSetInfos([info], after.deps())[0];

      expect(stickerBoardPackKey(packBefore) === stickerBoardPackKey(packAfter)).assertFalse();
      expect(stickerBoardPackKey(packAfter).indexOf('/data/2001.webp') >= 0).assertTrue();
    });

    it('packKey_isStableForSameRowAndDiffersAcrossRows', 0, () => {
      // 键每帧都换等于整行每帧重建：数据没动时必须逐字相同；不同包不能撞键（两包共用同一个缩略图 id）。
      const deps: RecordingDeps = new RecordingDeps();
      deps.havePath(2001, '/data/2001.webp');
      const row: StickerBoardPack = stickerBoardPacksFromSetInfos(
        [makeSetInfo('81', 'A', 2, [cover('81', 1)], 0)], deps.deps())[0];
      const rowAgain: StickerBoardPack = stickerBoardPacksFromSetInfos(
        [makeSetInfo('81', 'A', 2, [cover('81', 1)], 0)], deps.deps())[0];
      const other: StickerBoardPack = stickerBoardPacksFromSetInfos(
        [makeSetInfo('82', 'B', 2, [cover('82', 1)], 0)], deps.deps())[0];

      expect(stickerBoardPackKey(row)).assertEqual(stickerBoardPackKey(rowAgain));
      expect(stickerBoardPackKey(row) === stickerBoardPackKey(other)).assertFalse();
    });

    // ---------- STICKER-BOARD-102：热门贴纸包区 ----------

    it('trending_keepsRowsWithoutAnyCoverImage', 0, () => {
      // 这一行的动作是「装包」，封面只是装饰：因为取不到图就把能装的包藏掉，
      // 等于把唯一的装包入口弄丢（账号一个包没装时这里是唯一来源）。
      const rec = new RecordingDeps();
      const noThumb: StickerSetInfo = makeSetInfo('31', 'NoArt', 12, [cover('31', 1)], 0);
      const rows: StickerTrendingPack[] = stickerTrendingPacksFromSetInfos([noThumb], rec.deps());
      expect(rows.length).assertEqual(1);
      expect(rows[0].coverPath).assertNull();
      expect(rows[0].totalSize).assertEqual(12);
      expect(rows[0].isInstalled).assertFalse();
    });

    it('trending_registersExactlyOneFilePerRow', 0, () => {
      // 与已装盘不同：这里一包只登记那一张封面（≤6 个文件），不铺五格。
      const sets: StickerSetInfo[] = [];
      for (let i = 1; i <= 4; i++) {
        sets.push(makeSetInfo(`${i}`, `T${i}`, 20, [makeSticker(`${i}`, 100 + i, 200 + i, '🙂')], 900 + i));
      }
      const rec = new RecordingDeps();
      const rows: StickerTrendingPack[] = stickerTrendingPacksFromSetInfos(sets, rec.deps());
      expect(rows.length).assertEqual(4);
      expect(rec.downloaded.length).assertEqual(4);
      expect(rec.downloaded.indexOf(901)).assertEqual(0);
      // 单张封面的 fileId 绝不能混进来（那是原文件，板卡不需要）
      expect(rec.downloaded.indexOf(201)).assertEqual(-1);
      expect(rec.downloaded.indexOf(101)).assertEqual(-1);
    });

    it('trending_capsAtMaxPacks', 0, () => {
      const sets: StickerSetInfo[] = [];
      for (let i = 1; i <= 20; i++) {
        sets.push(makeSetInfo(`${i}`, `T${i}`, 5, [cover(`${i}`, 1)], 700 + i));
      }
      const rows: StickerTrendingPack[] = stickerTrendingPacksFromSetInfos(sets, new RecordingDeps().deps());
      expect(rows.length).assertEqual(STICKER_TRENDING_MAX_PACKS);
    });

    it('trending_coverSourceOrder_isSetThumbnailThenFirstCover', 0, () => {
      const rec = new RecordingDeps();
      rec.havePath(900, '/data/sets/900.webp');
      rec.havePath(2001, '/data/covers/2001.webp');
      const covers: Sticker[] = [makeSticker('4', 1001, 2001, '🐼')];

      expect(stickerTrendingCoverPath(makeSetInfo('4', 'A', 1, covers, 900), rec.deps()))
        .assertEqual('/data/sets/900.webp');
      // 包没有缩略图时退回第一张封面的缩略图，而不是空白
      expect(stickerTrendingCoverPath(makeSetInfo('4', 'A', 1, covers, 0), rec.deps()))
        .assertEqual('/data/covers/2001.webp');
      expect(stickerTrendingCoverPath(makeSetInfo('4', 'A', 1, [], 0), rec.deps())).assertNull();
    });

    it('trending_skipsTgsCoverAndFallsToTheNextCandidate', 0, () => {
      // TDLib 给动效贴纸包的 thumbnail 是 .tgs（gzip 的 Lottie JSON）：文件确实在盘上，
      // 但 ArkUI 的 Image 解不了 —— 喂给它就是一块空白，看起来像「图没下下来」。
      const rec = new RecordingDeps();
      rec.havePath(900, '/data/sets/900.tgs');
      rec.havePath(2001, '/data/covers/2001.webp');
      const covers: Sticker[] = [makeSticker('4', 1001, 2001, '🐼')];

      expect(stickerTrendingCoverPath(makeSetInfo('4', 'A', 1, covers, 900), rec.deps()))
        .assertEqual('/data/covers/2001.webp');
      // 解不了的那张已经下过了，不该再登记一次下载
      expect(rec.downloaded.indexOf(900)).assertEqual(-1);

      // 候选全没下过 → 只登记包缩略图那一张（一行一张的口径不变）
      const fresh = new RecordingDeps();
      expect(stickerTrendingCoverPath(makeSetInfo('4', 'A', 1, covers, 900), fresh.deps())).assertNull();
      expect(fresh.downloaded.length).assertEqual(1);
      expect(fresh.downloaded.indexOf(900)).assertEqual(0);
    });

    it('trending_withInstalled_syncsOnlyTheMatchedRow', 0, () => {
      const first: StickerSetInfo = makeSetInfo('41', 'First', 9, [cover('41', 1)], 0);
      const second: StickerSetInfo = makeSetInfo('42', 'Second', 8, [cover('42', 1)], 0);
      const rows: StickerTrendingPack[] = stickerTrendingPacksFromSetInfos(
        [first, second],
        new RecordingDeps().deps()
      );
      expect(rows[0].isInstalled).assertFalse();
      const after: StickerTrendingPack[] = stickerTrendingWithInstalled(rows, '41', true);

      expect(after.length).assertEqual(2);
      expect(after[0].isInstalled).assertTrue();
      expect(after[0].title).assertEqual('First');
      expect(after[0].totalSize).assertEqual(9);
      // 不相干那一行不能被顺手改成已装
      expect(after[1].isInstalled).assertFalse();
      // 键必须变：否则那一行的「添加」不会重绘成「已添加」
      expect(stickerTrendingKey(rows[0]) === stickerTrendingKey(after[0])).assertFalse();
      expect(stickerTrendingKey(rows[1]) === stickerTrendingKey(after[1])).assertTrue();
    });

    it('trending_key_changesWhenImageArrives', 0, () => {
      const before: StickerTrendingPack = new StickerTrendingPack('5', 'X', null, 3, false);
      const after: StickerTrendingPack = new StickerTrendingPack('5', 'X', '/data/5.webp', 3, false);
      expect(stickerTrendingKey(before) === stickerTrendingKey(after)).assertFalse();
    });

    it('pathIsRenderable_rejectsAnimationFormatsOnly', 0, () => {
      expect(stickerPathIsRenderable('/data/a.webp')).assertTrue();
      expect(stickerPathIsRenderable('/data/A.JPG')).assertTrue();
      // 未知扩展名按可渲染处理：别把 TDLib 换的命名规则当错误，误杀正常的图
      expect(stickerPathIsRenderable('/data/5')).assertTrue();
      expect(stickerPathIsRenderable('/data/a.tgs')).assertFalse();
      expect(stickerPathIsRenderable('/data/a.TGS')).assertFalse();
      expect(stickerPathIsRenderable('/data/a.mp4')).assertFalse();
      expect(stickerPathIsRenderable(null)).assertFalse();
      expect(stickerPathIsRenderable('')).assertFalse();
    });

    it('cellImage_tgsOriginalFallsBackToRasterThumbnail', 0, () => {
      // 动效贴纸的原文件就是 .tgs：优先原文件是为了看大图，但解不了的格式必须让位给缩略图，
      // 两样都不行才退回格子自己的 emoji（空白格子会被用户当成「下载坏了」）。
      const tgs: StickerSetItem = {
        id: 3,
        fileId: 3,
        emoji: '',
        width: 512,
        height: 512,
        localPath: '/data/stickers/3.tgs',
        thumbnailPath: '/data/thumbnails/3.webp',
        isDownloaded: true,
        isDownloading: false
      };
      expect(stickerCellImagePath(tgs)).assertEqual('/data/thumbnails/3.webp');

      const tgsOnly: StickerSetItem = {
        id: 3,
        fileId: 3,
        emoji: '🎬',
        width: 512,
        height: 512,
        localPath: '/data/stickers/3.tgs',
        thumbnailPath: null,
        isDownloaded: true,
        isDownloading: false
      };
      expect(stickerCellImagePath(tgsOnly)).assertNull();
      // 键里也不能带那张解不了的图：否则重建出一个空白 Image，比 emoji 占位更糟
      expect(stickerCellKey(tgsOnly).indexOf('.tgs')).assertEqual(-1);
    });

    it('boardThumbnail_skipsUndecodablePackThumbnail', 0, () => {
      const rec = new RecordingDeps();
      rec.havePath(900, '/data/sets/900.tgs');
      rec.havePath(2001, '/data/covers/2001.webp');
      const covers: Sticker[] = [makeSticker('4', 1001, 2001, '🐼')];
      // 已装盘那一区的取值顺序同页签条，但要跳过解不了的格式
      expect(stickerBoardThumbnailPath(makeSetInfo('4', 'A', 1, covers, 900), rec.deps()))
        .assertEqual('/data/covers/2001.webp');
      // 一张可渲染的都没有 → null，由界面退回包名首字母
      const nothing = new RecordingDeps();
      nothing.havePath(900, '/data/sets/900.tgs');
      expect(stickerBoardThumbnailPath(makeSetInfo('4', 'A', 1, covers, 900), nothing.deps())).assertNull();
    });
  });
}
