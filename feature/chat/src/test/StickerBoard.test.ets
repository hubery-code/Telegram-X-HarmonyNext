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
  STICKER_BOARD_RECENT_SET_ID,
  StickerBoardDeps,
  StickerBoardPack,
  requestStickerBoardDownloads,
  stickerBoardBlocks,
  stickerBoardPacksFromSetInfos,
  stickerBoardRecentPack,
  stickerBoardThumbnailPath,
  stickerCellImagePath,
  stickerCellKey,
  stickerItemFromSticker,
  stickerItemsFromStickers
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
  });
}
