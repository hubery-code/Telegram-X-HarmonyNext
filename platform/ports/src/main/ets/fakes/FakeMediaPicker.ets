/**
 * platform/ports — FakeMediaPicker 测试实现。
 * 用于离线单元测试，模拟系统相册/文件选择器的用户交互与结果回传。
 *
 * MEDIA-105：补 pickVideo —— 除回传 uri/path 外，还模拟适配器尽力填写的
 * duration / width / height / thumbnailPath（这些字段在真机上来自
 * AVMetadataExtractor 与 AVImageGenerator，测试里由用例直接注入）。
 */

import { MediaPickerPort, PickedMedia } from '../MediaPickerPort';

export class FakeMediaPicker implements MediaPickerPort {
  public nextPhotosToReturn: PickedMedia[] = [];
  public nextFilesToReturn: PickedMedia[] = [];
  public nextVideosToReturn: PickedMedia[] = [];
  public pickPhotoCalls: number = 0;
  public pickFileCalls: number = 0;
  public pickVideoCalls: number = 0;
  public shouldReject: boolean = false;
  public rejectError: Error = new Error('User cancelled');

  async pickPhoto(maxSelectNumber: number = 1): Promise<PickedMedia[]> {
    this.pickPhotoCalls += 1;
    if (this.shouldReject) {
      throw this.rejectError;
    }
    return [...this.nextPhotosToReturn.slice(0, maxSelectNumber)];
  }

  async pickFile(maxSelectNumber: number = 1): Promise<PickedMedia[]> {
    this.pickFileCalls += 1;
    if (this.shouldReject) {
      throw this.rejectError;
    }
    return [...this.nextFilesToReturn.slice(0, maxSelectNumber)];
  }

  async pickVideo(maxSelectNumber: number = 1): Promise<PickedMedia[]> {
    this.pickVideoCalls += 1;
    if (this.shouldReject) {
      throw this.rejectError;
    }
    return [...this.nextVideosToReturn.slice(0, maxSelectNumber)];
  }

  setPhotosToReturn(photos: PickedMedia[]): void {
    this.nextPhotosToReturn = photos;
  }

  setFilesToReturn(files: PickedMedia[]): void {
    this.nextFilesToReturn = files;
  }

  setVideosToReturn(videos: PickedMedia[]): void {
    this.nextVideosToReturn = videos;
  }

  reset(): void {
    this.nextPhotosToReturn = [];
    this.nextFilesToReturn = [];
    this.nextVideosToReturn = [];
    this.pickPhotoCalls = 0;
    this.pickFileCalls = 0;
    this.pickVideoCalls = 0;
    this.shouldReject = false;
  }
}
