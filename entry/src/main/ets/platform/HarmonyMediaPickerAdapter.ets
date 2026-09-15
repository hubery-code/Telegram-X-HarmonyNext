/**
 * entry — HarmonyOS 系统相册与文件选择器适配器（ARCH-001 / MEDIA-102）。
 *
 * 包装 @kit.MediaLibraryKit (PhotoViewPicker) 与 @kit.CoreFileKit (DocumentViewPicker)，
 * 实现 platform/ports 的 MediaPickerPort 契约，将系统选取结果适配为标准 PickedMedia[]。
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { MediaPickerPort, PickedMedia } from '@tgx/platform-ports';

const DOMAIN: number = 0x0000;
const TAG: string = 'HarmonyMediaPickerAdapter';

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

    const uniqueFileName: string = `${Date.now()}_${Math.floor(Math.random() * 10000)}_${rawName}`;
    const destPath: string = `${uploadDir}/${uniqueFileName}`;

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
}
