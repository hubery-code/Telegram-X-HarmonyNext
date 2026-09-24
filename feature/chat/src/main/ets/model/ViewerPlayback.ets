/**
 * feature/chat — 全屏查看器里动态内容的绘制判定（MEDIA-VIEWER-102 / FEAT-P2-006）。
 *
 * 只做纯判定，不碰 ArkUI：给定一条媒体的容器信息与「这一页是不是当前页」，
 * 回答该画播放器、逐帧图片、封面还是下载入口。
 *
 * 两条来自设备的教训决定了这里的形状：
 * 1. **Swiper 会缓存相邻页**（默认 cachedCount 不是 0），所以每一条视频页都会建出一个
 *    `autoPlay(true)` 的播放器 —— 翻到哪页，好几条视频在同时出声。播放器只能给当前页。
 * 2. ForEach 的 item 只在 **key 变化**时重渲（MEDIA-VIEWER-101 换大图档踩过同一个坑），
 *    所以「当前页」这个比特必须进 key，否则翻页后 `if` 分支根本不会重算。
 *
 * 动图（`messageAnimation`）按 TDLib 的定义只有两种容器：GIF 与 MPEG4。
 * GIF 交给 Image 原生逐帧播放（不需要播放器、天然无声循环），MPEG4 才走 Video；
 * 判定优先看 mime，扩展名只认**结尾**那一段 —— `xxx.gif.mp4` 是视频，
 * 而旧实现的 `localPath.indexOf('.mp4') >= 0` 只是在碰运气。
 */

import { MediaAttachment, MediaKind } from './MediaAttachment';

/** 动态内容的容器种类。 */
export type MotionContainer = 'gif' | 'video' | 'unknown';

/** 查看器里一条动态内容页此刻应该画什么。 */
export type ViewerMotionRender = 'player' | 'gif' | 'poster' | 'download';

const GIF_MIME: string = 'image/gif';
const VIDEO_MIME_PREFIX: string = 'video/';
const GIF_EXTENSION: string = 'gif';
const VIDEO_EXTENSIONS: string[] = ['mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi', '3gp', '3g2'];

function trailingExtension(name: string): string {
  const dot: number = name.lastIndexOf('.');
  if (dot < 0 || dot === name.length - 1) {
    return '';
  }
  return name.slice(dot + 1).toLowerCase();
}

/**
 * 容器判定：mime 优先，扩展名兜底。
 * 沙箱里的 TDLib 文件带原始扩展名（设备实测 `..._hq.gif.mp4`），但 mime 才是 TDLib
 * 给的权威值，所以排在前面；两者都读不到时返回 'unknown'，由调用方决定默认档位。
 */
export function motionContainerOf(mimeType: string, fileName: string, localPath: string | null): MotionContainer {
  const mime: string = mimeType.trim().toLowerCase();
  if (mime === GIF_MIME) {
    return 'gif';
  }
  if (mime.indexOf(VIDEO_MIME_PREFIX) === 0) {
    return 'video';
  }
  let ext: string = trailingExtension(fileName);
  if (ext.length === 0 && localPath !== null) {
    ext = trailingExtension(localPath);
  }
  if (ext === GIF_EXTENSION) {
    return 'gif';
  }
  if (VIDEO_EXTENSIONS.indexOf(ext) >= 0) {
    return 'video';
  }
  return 'unknown';
}

/**
 * 动图的容器。TDLib 保证 animation 是 GIF 或 MPEG4，判不出来时按视频档处理：
 * 服务端下发的动图绝大多数已转成 mp4，退回 Image 只会画出一张解不开的图。
 */
export function animationContainer(media: MediaAttachment): MotionContainer {
  const container: MotionContainer = motionContainerOf(media.mimeType, media.fileName, media.localPath);
  return container === 'unknown' ? 'video' : container;
}

/** 本地是否已有可直接喂给渲染端的文件（出站视频未下载完也算有源）。 */
function hasPlayableLocal(media: MediaAttachment): boolean {
  return media.localPath !== null && (media.isDownloaded || media.isUploading);
}

/** 这一条是否需要播放器节点（GIF 容器的动图由 Image 逐帧播，不起播放器）。 */
export function viewerNeedsPlayer(media: MediaAttachment): boolean {
  if (media.kind === 'video') {
    return true;
  }
  if (media.kind === 'animation') {
    return animationContainer(media) !== 'gif';
  }
  return false;
}

/**
 * 只有当前页才允许建播放器。
 * Swiper 的缓存页仍然活着，`autoPlay` 会一起开播；离开当前页即销毁节点，
 * 播放器随之回收 —— 这就是「翻页后上一段还在响」的根治办法。
 */
export function viewerRendersPlayer(index: number, activeIndex: number): boolean {
  return index === activeIndex;
}

/**
 * 查看器动态页的绘制档位（只按 video / animation 两类调用，照片页走图片分支）。
 * `isActive` 为 false 时永不返回 'player'：相邻页只画封面（没有封面就留黑底），
 * 翻页动画期间看不到第二个播放器，也不会有第二条音轨。
 */
export function viewerMotionRender(media: MediaAttachment, isActive: boolean): ViewerMotionRender {
  if (!hasPlayableLocal(media)) {
    // 未落盘：整档都还在路上，先给下载入口（正在下时同一处画进度圈）。
    return 'download';
  }
  if (media.kind === 'animation' && animationContainer(media) === 'gif') {
    return 'gif';
  }
  return isActive ? 'player' : 'poster';
}

/** 缩放与拖拽只对照片开放（视频页交给播放器自己的控制条）。 */
export function viewerZoomable(kind: MediaKind): boolean {
  return kind === 'photo';
}
