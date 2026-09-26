/**
 * feature/chat — 动效贴纸（TGS/Lottie）的取数口径（TGS-101）。纯函数，不碰 Kit。
 *
 * 一句话背景：动效贴纸的整档 `.tgs` 是 gzip 过的 Lottie JSON，ArkUI 的 `Image` 解不了，
 * 所以 STICKER-MSG-101 起它一直退回静态缩略图。本端现在接了 `@ohos/lottie` 画它，
 * 而「读 .tgs → inflate → 拿到 JSON 文本」这一步要 File Kit 与 zlib，归 platform 层
 * （`TgsDecoderPort`）；这里只负责说清**哪张贴纸该走动画、给它吃什么路径**。
 *
 * 判据落在**已下盘的本地路径**上：TDLib 的 `file` DTO 没有扩展名字段，下载前无从得知格式
 * （与 `stickerPathIsRenderable` 同一个口径，两者互斥是构造出来的：能当 Lottie 的一定不是位图）。
 */

import { MediaAttachment } from './MediaAttachment';

/** 本端能交给解码器处理的动效贴纸整档扩展名。 */
const LOTTIE_SUFFIXES: string[] = ['tgs', 'json'];

/** 路径结尾是不是动效贴纸的整档格式（未知扩展名一律不算）。 */
export function stickerPathIsLottie(path: string | null): boolean {
  if (path === null || path.length === 0) {
    return false;
  }
  const dot: number = path.lastIndexOf('.');
  if (dot < 0 || dot === path.length - 1) {
    return false;
  }
  const suffix: string = path.substring(dot + 1).toLowerCase();
  for (let i = 0; i < LOTTIE_SUFFIXES.length; i++) {
    if (LOTTIE_SUFFIXES[i] === suffix) {
      return true;
    }
  }
  return false;
}

/**
 * 这条贴纸消息能不能画成动画：必须是贴纸、整档已下盘、且整档是 `.tgs`/`.json`。
 * 返回 null 时气泡停在原来的静态档，不做任何降级判断 —— 那是 `stickerBubbleRender` 的事。
 *
 * 不再要求 fileId：解码产物不落盘，也就不存在「拿什么命名缓存文件」这个问题。
 */
export function stickerAnimationTgsPath(media: MediaAttachment): string | null {
  if (media.kind !== 'sticker' || !media.isDownloaded) {
    return null;
  }
  if (!stickerPathIsLottie(media.localPath)) {
    return null;
  }
  // ArkTS 不在条件之后自动收窄，所以判完再单独落一次类型。
  if (media.localPath === null) {
    return null;
  }
  return media.localPath;
}
