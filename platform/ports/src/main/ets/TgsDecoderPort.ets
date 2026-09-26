/**
 * platform/ports — TGS 动图贴纸的解码口（TGS-101）。
 *
 * 为什么需要单独一个口：Telegram 的动效贴纸整档是 `.tgs` —— **gzip 过的 Lottie JSON**。
 * ArkUI 的 `Image` 解不开它（不报错、不回调，只画一片空白），必须有人把它解成 JSON 文本，
 * 而这一步需要 File Kit 读盘与 `@ohos.zlib` 的 inflate —— 两样都不能进 feature/*
 * （reducer / coordinator 的 Kit-free 红线），于是落在 platform 层。
 *
 * 契约口径：**只到文本为止**。
 * - 输入是 TDLib 已经下盘的 .tgs **绝对路径**（本口不负责下载，也不判断文件是否存在）；
 * - 输出是 Lottie JSON **文本**，交给组件侧 `JSON.parse` 后喂给 lottie 的 `animationData`；
 * - 不解 `path` 那条路：`@ohos/lottie` 的沙盒分支要 `getContext().filesDir`，
 *   在它的异步 worker 里拿不拿得到 context 我们赌不起，而 `animationData`
 *   （`AnimationItem.loadAnimation` 的第一个分支）直接进 `setupAnimation`，零文件 IO。
 * - 落盘缓存同理不做：`.tgs` 本身就是持久缓存，inflate 是毫秒级的，
 *   多解一次的代价远小于「半截 JSON / 目录被清 / 键对不上」这三类坑。
 */

import { AppError, Result } from '@tgx/core-common';

export interface TgsDecoderPort {
  /**
   * 把 `tgsPath` 指向的 `.tgs`（gzip 流；不是 gzip 就按已是 JSON 处理）解成 Lottie JSON 文本。
   * 失败回 `AppError`，调用方退回静态缩略图 —— 这一口没有「部分成功」。
   */
  decode(tgsPath: string): Promise<Result<string, AppError>>;
}
