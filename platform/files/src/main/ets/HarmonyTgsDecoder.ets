/**
 * platform/files — TgsDecoderPort 的 HarmonyOS 实现（TGS-101）。
 *
 * 干的事只有一件：把 TDLib 落在盘上的 `.tgs`（**gzip 过的 Lottie JSON**）解成 JSON 文本。
 * 为什么要我们自己动手：
 * - ArkUI 的 `Image` 解不了 `.tgs`，喂进去只画一片空白（连错误回调都没有）；
 * - `@ohos/lottie` 内置的解包只认 `.zip` / `.lottie` 两种容器（`DataUtil.isCompressdFile`），
 *   gzip 流不在其列；
 * - gzip inflate 在 ArkTS 侧只有 `@ohos.zlib` 的流式接口（`createZipSync` +
 *   `inflateInit2(windowBits)` + `inflate`），没有 `gunzip` 一次性 API，
 *   所以要自己分块喂、自己收块。
 *
 * 产物是**内存里的文本**，不落盘：`.tgs` 本身就是 TDLib 管的持久缓存，
 * 再抄一份 JSON 只会多出「半截文件 / 目录被清理 / 键对不上」三类故障，换不到性能。
 * 这里只留一个小的内存缓存（{@link CACHE_LIMIT} 条），为的是同一张贴纸在会话里
 * 反复进出可视区时不必每帧重跑一遍 inflate —— 上限很小，贴纸包再大也吃不满。
 *
 * 边界：
 * - 只吃**已经在盘上**的路径，不负责下载（下载归 ChatCoordinator/FileRegistry）；
 * - 解压结果超过 {@link MAX_JSON_BYTES} 视为坏档，直接失败而不是把主线程压死；
 * - 输入不是 gzip（没有 `1f 8b` 头）时按**已是 JSON** 处理，
 *   这样 TDLib 哪天直接给 `.json` 也不用再改。
 *
 * 取证口径：gzip 分支**只能在真机/模拟器上验**。Local Test 运行时里 `@ohos.zlib` 的
 * 流式接口是空壳（`inflateInit2`/`inflate` 都回 status 0，但 `getZStream()` 的
 * `totalOut` 是 `undefined`，连自压自解都产出 0 字节），单测只能覆盖到非 gzip 直通道
 * 与两个纯判定；真档解开与否看 `tgs-decoded in=… out=…` 这条 hilog。
 */

import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { buffer } from '@kit.ArkTS';
import { AppError, AppErrors, ok, err, Result } from '@tgx/core-common';
import { AppFilesPort, TgsDecoderPort } from '@tgx/platform-ports';

const DOMAIN: number = 0x0000;
const TAG: string = 'HarmonyTgsDecoder';

/** gzip + 自动识别头部：zlib 里 `windowBits > 15` 即按 gzip 解，`15+16` 是「看头自己判」。 */
const GZIP_WINDOW_BITS: number = 31;
/** 单次 inflate 的输出窗口；循环到 `STREAM_END` 为止。 */
const CHUNK_BYTES: number = 64 * 1024;
/** 分块上限：动图贴纸的 JSON 一般 30 ~ 300 KB，64 KB × 64 = 4 MB，够用且不超预算。 */
const MAX_INFLATE_ROUNDS: number = 64;
/** Lottie JSON 的合理上限。超了就是坏档或恶意档。 */
const MAX_JSON_BYTES: number = 4 * 1024 * 1024;
/** 内存缓存条数；插入序淘汰最旧的一条。 */
const CACHE_LIMIT: number = 32;

/** gzip 的两字节魔数 `1f 8b`。 */
export function bytesAreGzipStream(bytes: Uint8Array): boolean {
  return bytes.length >= 2 && bytes[0] === 0x1f && bytes[1] === 0x8b;
}

/** 是不是一个能交给 lottie 的 JSON 文本（只判「剥掉空白后以 { 开头」，不做语法校验）。 */
export function textLooksLikeLottieJson(text: string): boolean {
  const head: string = text.trimStart().substring(0, 1);
  return head === '{';
}

function asStorageError(origin: string, e: Object): AppError {
  const be: BusinessError = e as BusinessError;
  if (be !== null && be !== undefined && typeof be.code === 'number') {
    return AppErrors.storage('io', `${origin} failed`, false, undefined, `${be.code}:${be.message}`);
  }
  return AppErrors.unknown(origin, `${origin} failed (non-business error)`);
}

/**
 * `zlib` 的入参要的是**整块** `ArrayBuffer`。
 * `Uint8Array` 可以是某个更大 buffer 上的一段视图（`readBytes` 目前不是，但一旦是，
 * 直接取 `.buffer` 会把前面的无关字节一起喂进 inflate，得到一份静默错位的 JSON），
 * 所以视图不精确时先拷一份。
 */
function wholeBuffer(bytes: Uint8Array): ArrayBuffer {
  if (bytes.byteOffset === 0 && bytes.length === bytes.buffer.byteLength) {
    return bytes.buffer as ArrayBuffer;
  }
  const copy: Uint8Array = new Uint8Array(bytes.length);
  copy.set(bytes, 0);
  return copy.buffer as ArrayBuffer;
}

export class HarmonyTgsDecoder implements TgsDecoderPort {
  private readonly files: AppFilesPort;
  /** tgs 绝对路径 → Lottie JSON 文本。Map 保持插入序，所以淘汰取第一个 key。 */
  private readonly cache: Map<string, string> = new Map<string, string>();

  constructor(files: AppFilesPort) {
    this.files = files;
  }

  async decode(tgsPath: string): Promise<Result<string, AppError>> {
    const cached: string | undefined = this.cache.get(tgsPath);
    if (cached !== undefined) {
      return ok<string, AppError>(cached);
    }
    const readRes: Result<Uint8Array, AppError> = this.files.readBytes(tgsPath);
    // ArkTS 只对 `x.ok === true / === false` 收窄判别联合（`!x.ok` 与 else 分支都不算），
    // 所以取值与取错写成一对显式比较分支，而不是「先早返回再往下用」。
    if (readRes.ok === false) {
      return err<string, AppError>(readRes.error);
    }
    if (readRes.ok === true) {
      const raw: Uint8Array = readRes.value;
      let json: Uint8Array | null = null;
      if (bytesAreGzipStream(raw)) {
        const inflated: Result<Uint8Array, AppError> = await this.inflateGzip(raw);
        if (inflated.ok === true) {
          json = inflated.value;
        } else {
          return err<string, AppError>(inflated.error);
        }
      } else {
        // 不是 gzip 就当它已经是 JSON —— TDLib 给 `.json` 整档时不必再绕一圈。
        json = raw;
      }
      if (json === null) {
        return err<string, AppError>(AppErrors.storage('io', 'inflate produced nothing', false));
      }
      const decoded: Uint8Array = json;
      const text: string = buffer.from(decoded).toString('utf-8');
      if (!textLooksLikeLottieJson(text)) {
        hilog.error(DOMAIN, TAG, `tgs-not-json path=%{public}s bytes=%{public}d head=%{public}s`,
          tgsPath, decoded.length, JSON.stringify(text.substring(0, 16)));
        return err<string, AppError>(AppErrors.storage('io', 'decoded tgs is not a Lottie JSON', false));
      }
      hilog.info(DOMAIN, TAG, `tgs-decoded in=%{public}d out=%{public}d path=%{public}s`,
        raw.length, decoded.length, tgsPath);
      this.remember(tgsPath, text);
      return ok<string, AppError>(text);
    }
    return err<string, AppError>(AppErrors.storage('io', 'unreadable tgs', false));
  }

  private remember(tgsPath: string, text: string): void {
    if (this.cache.size >= CACHE_LIMIT) {
      const oldest: string | undefined = this.cache.keys().next().value;
      if (oldest !== undefined) {
        this.cache.delete(oldest);
      }
    }
    this.cache.set(tgsPath, text);
  }

  /**
   * zlib 流式 inflate：一次给一个输出窗口，循环到 `STREAM_END`。
   * 每轮从 `getZStream()` 取 `totalOut`（zlib 只报累计输出量），据此把这一轮的字节切出来。
   */
  private async inflateGzip(src: Uint8Array): Promise<Result<Uint8Array, AppError>> {
    const zip = zlib.createZipSync();
    const chunks: Uint8Array[] = [];
    let totalOut: number = 0;
    try {
      await zip.inflateInit2({ nextIn: wholeBuffer(src), availableIn: src.length }, GZIP_WINDOW_BITS);
      for (let guard = 0; guard < MAX_INFLATE_ROUNDS; guard++) {
        const out = new ArrayBuffer(CHUNK_BYTES);
        const status = await zip.inflate({ nextOut: out, availableOut: CHUNK_BYTES },
          zlib.CompressFlushMode.NO_FLUSH);
        const stream = await zip.getZStream();
        // `ZStream.totalOut` 在类型上是可选的（zlib 只在初始化后才填），缺当「本轮没产出」。
        const produced: number = stream.totalOut === undefined ? totalOut : stream.totalOut;
        const written: number = produced - totalOut;
        if (written > 0) {
          chunks.push(new Uint8Array(out, 0, written));
          totalOut += written;
        }
        if (totalOut > MAX_JSON_BYTES) {
          return err<Uint8Array, AppError>(
            AppErrors.storage('io', `inflated tgs exceeds ${MAX_JSON_BYTES} bytes`, false));
        }
        if (status === zlib.ReturnStatus.STREAM_END) {
          break;
        }
        if (written === 0) {
          // 既没输出也没结束 —— 再转下去只是空转，判定为坏档。
          return err<Uint8Array, AppError>(
            AppErrors.storage('io', `inflate stalled at ${totalOut} bytes (status=${status})`, false));
        }
      }
      const merged: Uint8Array = new Uint8Array(totalOut);
      let offset: number = 0;
      for (let i = 0; i < chunks.length; i++) {
        merged.set(chunks[i], offset);
        offset += chunks[i].length;
      }
      return ok<Uint8Array, AppError>(merged);
    } catch (e) {
      return err<Uint8Array, AppError>(asStorageError('inflateGzip', e));
    }
  }
}
