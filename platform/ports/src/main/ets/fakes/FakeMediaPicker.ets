/**
 * platform/ports — FakeMediaPicker 测试实现。
 * 用于离线单元测试，模拟系统相册/文件选择器的用户交互与结果回传。
 */

import { MediaPickerPort, PickedMedia } from '../MediaPickerPort';

export class FakeMediaPicker implements MediaPickerPort {
  public nextPhotosToReturn: PickedMedia[] = [];
  public nextFilesToReturn: PickedMedia[] = [];
  public pickPhotoCalls: number = 0;
  public pickFileCalls: number = 0;
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

  setPhotosToReturn(photos: PickedMedia[]): void {
    this.nextPhotosToReturn = photos;
  }

  setFilesToReturn(files: PickedMedia[]): void {
    this.nextFilesToReturn = files;
  }

  reset(): void {
    this.nextPhotosToReturn = [];
    this.nextFilesToReturn = [];
    this.pickPhotoCalls = 0;
    this.pickFileCalls = 0;
    this.shouldReject = false;
  }
}
