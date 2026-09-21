/**
 * entry — HarmonyOS 系统相册与文件选择器适配器（ARCH-001 / MEDIA-102 / MEDIA-105）。
 *
 * 包装 @kit.MediaLibraryKit (PhotoViewPicker) 与 @kit.CoreFileKit (DocumentViewPicker)，
 * 实现 platform/ports 的 MediaPickerPort 契约，将系统选取结果适配为标准 PickedMedia[]。
 *
 * MEDIA-105 新增：`pickVideo` —— 除选取与沙箱拷贝外，还负责在**本层**用完
 * AVMetadataExtractor / AVImageGenerator 把视频元数据（时长/宽高）与首帧缩略图补齐。
 * 之所以放在适配器而不是业务层：这两个能力都是系统 Kit，业务 Coordinator 必须 Kit-free
 * （ARCH-001），端口只回传纯数据。任一环节失败都只降级（字段留空），不阻断发送。
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaPickerPort, PickedMedia } from '@tgx/platform-ports';

const DOMAIN: number = 0x0000;
const TAG: string = 'HarmonyMediaPickerAdapter';

/** 缩略图长边上限：对齐 TDLib inputThumbnail 文档「通常不超过 320」。 */
const THUMBNAIL_MAX_SIDE: number = 320;
/** 抽帧时间点：取 0μs 处的关键帧。 */
const THUMBNAIL_TIME_US: number = 0;

export class HarmonyMediaPickerAdapter implements MediaPickerPort {
  private cacheDir: string = '/data/storage/el2/base/cache';

  constructor(cacheDir?: string) {
    if (cacheDir !== undefined && cacheDir.length > 0) {
      this.cacheDir = cacheDir;
    }
  }

  public setCacheDir(cacheDir: string): void {
    if (cacheDir.length > 0) {
      this.cacheDir = cacheDir;
    }
  }

  private copyUriToCache(uri: string, defaultExt: string): PickedMedia {
    let rawName: string = '';
    const lastSlash: number = uri.lastIndexOf('/');
    if (lastSlash >= 0) {
      rawName = uri.substring(lastSlash + 1);
    }
    try {
      rawName = decodeURIComponent(rawName);
    } catch (_e) {
      // ignore decode error
    }
    // 过滤非法字符
    rawName = rawName.replace(/[/\\?%*:|"<>]/g, '_');
    if (rawName.length === 0) {
      rawName = `media_${Date.now()}${defaultExt}`;
    } else if (!rawName.includes('.') && defaultExt.length > 0) {
      rawName = `${rawName}${defaultExt}`;
    }

    const uploadDir: string = `${this.cacheDir}/uploads`;
    try {
      if (!fs.accessSync(uploadDir)) {
        fs.mkdirSync(uploadDir, true);
      }
    } catch (_e) {
      try {
        fs.mkdirSync(uploadDir, true);
      } catch (_err) {
        // directory might exist
      }
    }

    // 去重只体现在父目录名上，最后一段必须保持原始文件名。
    //
    // 根因：TDLib 的 `inputDocument` / `inputVideo` 都没有 `file_name` 字段，
    // 它是拿 `InputFileLocal` 路径的 basename 反推 file_name 的。若像早期实现那样
    // 把 `${ts}_${rand}_` 前缀拼到文件名上，文档/视频气泡的标题就会显示成
    // `1789987100759_8836_mda-xxx.mp4` 这种沙箱缓存名（MEDIA-105 联调实测）。
    // 放进唯一子目录既保证不重名，又让 basename 保持干净。
    let uniqueDir: string = '';
    let guard: number = 0;
    while (guard < 5) {
      uniqueDir = `${uploadDir}/${Date.now()}_${Math.floor(Math.random() * 10000)}`;
      let dirExists: boolean = false;
      try {
        dirExists = fs.accessSync(uniqueDir);
      } catch (_e) {
        dirExists = false;
      }
      if (!dirExists) {
        break;
      }
      guard++;
    }
    try {
      if (!fs.accessSync(uniqueDir)) {
        fs.mkdirSync(uniqueDir, true);
      }
    } catch (_e) {
      try {
        fs.mkdirSync(uniqueDir, true);
      } catch (_err) {
        // directory might exist
      }
    }

    const destPath: string = `${uniqueDir}/${rawName}`;

    let srcFile: fs.File | null = null;
    let destFile: fs.File | null = null;
    let fileSize: number = 0;

    try {
      srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        const stat: fs.Stat = fs.statSync(srcFile.fd);
        fileSize = stat.size;
      } catch (statErr) {
        hilog.warn(DOMAIN, TAG, 'statSync failed on src fd: %{public}s', String(statErr));
      }

      destFile = fs.openSync(destPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.copyFileSync(srcFile.fd, destFile.fd);
      hilog.info(DOMAIN, TAG, 'copied uri=%{public}s to destPath=%{public}s, size=%{public}d',
        uri, destPath, fileSize);
      return {
        uri: uri,
        path: destPath,
        name: rawName,
        size: fileSize
      };
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'copyUriToCache failed for %{public}s: %{public}s', uri, String(err));
      // 降级：如果拷贝失败，返回原始 uri，避免完全阻断
      return {
        uri: uri,
        path: uri,
        name: rawName,
        size: fileSize
      };
    } finally {
      if (srcFile !== null) {
        try {
          fs.closeSync(srcFile);
        } catch (_err) {
          // ignore
        }
      }
      if (destFile !== null) {
        try {
          fs.closeSync(destFile);
        } catch (_err) {
          // ignore
        }
      }
    }
  }

  async pickPhoto(maxSelectNumber: number = 1): Promise<PickedMedia[]> {
    try {
      const photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = maxSelectNumber > 0 ? maxSelectNumber : 1;
      const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(options);
      if (result === null || result.photoUris === null || result.photoUris.length === 0) {
        return [];
      }
      const list: PickedMedia[] = [];
      for (let i = 0; i < result.photoUris.length; i++) {
        const uri: string = result.photoUris[i];
        list.push(this.copyUriToCache(uri, '.jpg'));
      }
      return list;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'pickPhoto failed: %{public}s', String(err));
      return [];
    }
  }

  async pickFile(maxSelectNumber: number = 1): Promise<PickedMedia[]> {
    try {
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = maxSelectNumber > 0 ? maxSelectNumber : 1;
      const result: Array<string> = await documentPicker.select(options);
      if (result === null || result.length === 0) {
        return [];
      }
      const list: PickedMedia[] = [];
      for (let i = 0; i < result.length; i++) {
        const uri: string = result[i];
        list.push(this.copyUriToCache(uri, ''));
      }
      return list;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'pickFile failed: %{public}s', String(err));
      return [];
    }
  }

  /** 保证 $cache/uploads 存在并返回该目录（选取产物与缩略图都落在这里，同属可清理的临时区）。 */
  private ensureUploadDir(): string {
    const uploadDir: string = `${this.cacheDir}/uploads`;
    try {
      if (!fs.accessSync(uploadDir)) {
        fs.mkdirSync(uploadDir, true);
      }
    } catch (_e) {
      try {
        fs.mkdirSync(uploadDir, true);
      } catch (_err) {
        // 目录可能已存在
      }
    }
    return uploadDir;
  }

  /** TDLib 元数据字段（如 duration/videoWidth）是字符串，解析失败返回 NaN。 */
  private static parseMetaNumber(raw: string | undefined): number {
    if (raw === undefined || raw.length === 0) {
      return Number.NaN;
    }
    const parsed: number = Number.parseInt(raw, 10);
    return Number.isFinite(parsed) ? parsed : Number.NaN;
  }

  /**
   * MEDIA-105：补齐视频元数据与首帧缩略图。**全程尽力而为**：
   * 任一步失败只记日志并把对应字段留空，返回已拿到的部分，绝不抛给调用方。
   */
  private async enrichVideo(mediaItem: PickedMedia): Promise<PickedMedia> {
    const physicalPath: string = (mediaItem.path !== undefined && mediaItem.path.length > 0) ? mediaItem.path : '';
    const out: PickedMedia = {
      uri: mediaItem.uri,
      path: mediaItem.path,
      name: mediaItem.name,
      size: mediaItem.size,
      mimeType: mediaItem.mimeType
    };
    if (physicalPath.length === 0) {
      return out;
    }

    let videoWidth: number = 0;
    let videoHeight: number = 0;

    // 1) 元数据：时长 / 宽 / 高
    try {
      const extractor: media.AVMetadataExtractor = await media.createAVMetadataExtractor();
      const fd: fs.File = fs.openSync(physicalPath, fs.OpenMode.READ_ONLY);
      try {
        extractor.fdSrc = { fd: fd.fd };
        const meta: media.AVMetadata = await extractor.fetchMetadata();
        const durationMs: number = HarmonyMediaPickerAdapter.parseMetaNumber(meta.duration);
        if (Number.isFinite(durationMs) && durationMs > 0) {
          out.duration = Math.max(1, Math.round(durationMs / 1000));
        }
        videoWidth = HarmonyMediaPickerAdapter.parseMetaNumber(meta.videoWidth);
        videoHeight = HarmonyMediaPickerAdapter.parseMetaNumber(meta.videoHeight);
        if (Number.isFinite(videoWidth) && videoWidth > 0) {
          out.width = Math.floor(videoWidth);
        } else {
          videoWidth = 0;
        }
        if (Number.isFinite(videoHeight) && videoHeight > 0) {
          out.height = Math.floor(videoHeight);
        } else {
          videoHeight = 0;
        }
      } finally {
        fs.closeSync(fd);
      }
      await extractor.release();
    } catch (metaErr) {
      hilog.warn(DOMAIN, TAG, 'enrichVideo metadata failed: %{public}s', String(metaErr));
    }

    // 2) 首帧缩略图：按已知宽高算等比目标尺寸，避免取帧参数拉伸画面
    try {
      const generator: media.AVImageGenerator = await media.createAVImageGenerator();
      const fd: fs.File = fs.openSync(physicalPath, fs.OpenMode.READ_ONLY);
      let pixelMap: image.PixelMap | undefined = undefined;
      try {
        generator.fdSrc = { fd: fd.fd };
        // 宽高已知时按等比目标尺寸取帧；未知时传 0/0 —— 按 PixelMapParams 语义
        // 「值必须 > 0 且不超过原始尺寸，否则不缩放」即返回原始分辨率。
        const params: media.PixelMapParams = HarmonyMediaPickerAdapter.fitWithin(videoWidth, videoHeight);
        pixelMap = await generator.fetchFrameByTime(
          THUMBNAIL_TIME_US,
          media.AVImageQueryOptions.AV_IMAGE_QUERY_CLOSEST_SYNC,
          params
        );
      } finally {
        fs.closeSync(fd);
      }

      if (pixelMap !== undefined && pixelMap !== null) {
        const info: image.ImageInfo = await pixelMap.getImageInfo();
        const thumbWidth: number = info.size.width > 0 ? info.size.width : 0;
        const thumbHeight: number = info.size.height > 0 ? info.size.height : 0;
        const thumbPath: string =
          `${this.ensureUploadDir()}/thumb_${Date.now()}_${Math.floor(Math.random() * 10000)}.jpg`;

        const packer: image.ImagePacker = image.createImagePacker();
        const destFd: fs.File = fs.openSync(thumbPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
        try {
          await packer.packToFile(pixelMap, destFd.fd, { format: 'image/jpeg', quality: 80 });
        } finally {
          fs.closeSync(destFd);
        }
        await packer.release();

        out.thumbnailPath = thumbPath;
        out.thumbnailWidth = thumbWidth;
        out.thumbnailHeight = thumbHeight;
        hilog.info(DOMAIN, TAG, 'enrichVideo thumbnail ok: %{public}s (%{public}d x %{public}d)',
          thumbPath, thumbWidth, thumbHeight);

        await pixelMap.release();
      }
      await generator.release();
    } catch (thumbErr) {
      hilog.warn(DOMAIN, TAG, 'enrichVideo thumbnail failed: %{public}s', String(thumbErr));
    }

    return out;
  }

  /**
   * 等比缩到长边 <= THUMBNAIL_MAX_SIDE 的目标尺寸（至少 1px）。
   * 宽高未知（<=0）时返回 0/0：PixelMapParams 语义下即为「不缩放，用原始分辨率」。
   */
  private static fitWithin(width: number, height: number): media.PixelMapParams {
    if (width <= 0 || height <= 0) {
      return { width: 0, height: 0 };
    }
    const longest: number = Math.max(width, height);
    const scale: number = longest > THUMBNAIL_MAX_SIDE ? (THUMBNAIL_MAX_SIDE / longest) : 1;
    return {
      width: Math.max(1, Math.round(width * scale)),
      height: Math.max(1, Math.round(height * scale))
    };
  }

  async pickVideo(maxSelectNumber: number = 1): Promise<PickedMedia[]> {
    try {
      const photoPicker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE;
      options.maxSelectNumber = maxSelectNumber > 0 ? maxSelectNumber : 1;
      const result: photoAccessHelper.PhotoSelectResult = await photoPicker.select(options);
      if (result === null || result.photoUris === null || result.photoUris.length === 0) {
        return [];
      }
      const list: PickedMedia[] = [];
      for (let i = 0; i < result.photoUris.length; i++) {
        const uri: string = result.photoUris[i];
        const copied: PickedMedia = this.copyUriToCache(uri, '.mp4');
        list.push(await this.enrichVideo(copied));
      }
      return list;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'pickVideo failed: %{public}s', String(err));
      return [];
    }
  }
}
