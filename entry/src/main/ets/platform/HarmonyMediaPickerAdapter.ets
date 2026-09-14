/**
 * entry — HarmonyOS 系统相册与文件选择器适配器（ARCH-001 / MEDIA-102）。
 *
 * 包装 @kit.MediaLibraryKit (PhotoViewPicker) 与 @kit.CoreFileKit (DocumentViewPicker)，
 * 实现 platform/ports 的 MediaPickerPort 契约，将系统选取结果适配为标准 PickedMedia[]。
 */

import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker } from '@kit.CoreFileKit';
import { MediaPickerPort, PickedMedia } from '@tgx/platform-ports';

export class HarmonyMediaPickerAdapter implements MediaPickerPort {
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
        list.push({
          uri: uri,
          path: uri
        });
      }
      return list;
    } catch (_err) {
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
        list.push({
          uri: uri,
          path: uri
        });
      }
      return list;
    } catch (_err) {
      return [];
    }
  }
}
