/**
 * feature/chat — 贴纸消息气泡的绘制档位（STICKER-MSG-101）。
 *
 * 之前这里没有判定：`StickerBubble` 只看「本地有没有文件」，有就把 `localPath` 直接喂给
 * `Image()`。设备实测（Saved Messages，2026-09-26 11:23）动效贴纸包 Uni 的第一条消息
 * 因此**整块画不出来** —— 只剩右下角那颗时间戳胶囊飘在空白上。
 *
 * 根因是 TDLib 的落盘格式：动效（Lottie）贴纸的整档是 `.tgs`（gzip 过的 JSON），
 * ArkUI 的 `Image` 解不开它，而且**不报错、不回调，只画一片空白**；当时本端没有 rlottie /
 * TgsPlayer 之类的解码器（`oh_modules` 里 `lottie|rlottie|tgs` 零命中）。
 * 同一条贴纸的**缩略图**是 `.webp`（`.../thumbnails/<fileId>_109.webp`），板卡里能画出来，
 * 气泡里却因为「整档优先」永远轮不到它 —— 这就是「板卡有图、气泡空白」这对矛盾的全部。
 *
 * TGS-101 起了 `@ohos/lottie`，动效档改画真动画（`'tgs'`），但**这套档位判定原样保留**：
 * 解码口是注入进来的装配事实，没注入、解码失败、动画还没挂上，都退回原来的静态缩略图，
 * 所以「画不开的整档（`.tgs`/`.json`/`.lottie`）退回缩略图，缩略图也没有才退回 emoji 兜底」
 * 这条主线依然成立。
 * 视频容器（`.mp4` 视频贴纸）单独一档走 `Video`；扩展名只认**结尾**那一段，
 * 旧实现里的 `localPath.indexOf('.webm') >= 0` 是在碰运气（`a.webm.log` 也会命中）。
 */

import { MediaAttachment } from './MediaAttachment';
import { stickerAnimationTgsPath } from './StickerAnimation';
import { stickerPathIsRenderable } from './StickerBoard';
import { motionContainerOf } from './ViewerPlayback';

/** 贴纸气泡的五档画法（TGS-101 加了 `'tgs'`）。 */
export type StickerBubbleRender = 'tgs' | 'video' | 'image' | 'thumbnail' | 'emoji';

/**
 * 气泡该画什么：
 * - `'tgs'`：动效贴纸整档（`.tgs`）已落盘，**且装配层给了解码口** —— 画 Lottie 动画；
 * - `'video'`：整档已落盘且是视频容器（视频贴纸），走 `Video` 循环静音播放；
 * - `'image'`：整档已落盘且是位图（webp/png/jpg/gif），`Image` 直接画；
 * - `'thumbnail'`：整档画不开或还没下完，但缩略图是能画的位图 —— 没接解码器时
 *   动效贴纸也停在这一档，同时在整档下载中叠进度圈；
 * - `'emoji'`：两头都没有可画的图，退回贴纸自己的 emoji（无 emoji 再退占位符）。
 *
 * 缩略图本身也要过一遍可画判定：TDLib 的 `thumbnails` 目录里同样躺着 `.tgs`
 * （设备实测 `328260442013040644_1680977305.tgs`），把它当兜底等于再画一次空白。
 *
 * `canAnimate` 是**装配事实**而不是贴纸事实：解码口在 `platform/files`（要 File Kit 与 zlib），
 * 由 entry 注入；没注入（例如单测与预览桩里的 ChatPage）时动效档自动退回静态缩略图，
 * 所以这个参数留在判定里而不是让调用方各写一次 `&&`。
 */
export function stickerBubbleRender(media: MediaAttachment, canAnimate: boolean = false): StickerBubbleRender {
  if (media.localPath !== null && media.isDownloaded) {
    if (canAnimate && stickerAnimationTgsPath(media) !== null) {
      return 'tgs';
    }
    if (motionContainerOf(media.mimeType, media.fileName, media.localPath) === 'video') {
      return 'video';
    }
    if (stickerPathIsRenderable(media.localPath)) {
      return 'image';
    }
  }
  if (media.thumbnailPath !== null && stickerPathIsRenderable(media.thumbnailPath)) {
    return 'thumbnail';
  }
  return 'emoji';
}
