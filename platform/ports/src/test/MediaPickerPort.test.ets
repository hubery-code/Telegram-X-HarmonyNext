/**
 * platform/ports — MediaPickerPort 与 FakeMediaPicker 单元测试（MEDIA-102）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { FakeMediaPicker } from '../main/ets/fakes/FakeMediaPicker';
import { PickedMedia } from '../main/ets/MediaPickerPort';

export default function mediaPickerPortTest() {
  describe('MediaPickerPortTest', () => {

    it('pickPhoto_returnsMockedPhotos_andRespectsLimit', 0, async () => {
      const picker: FakeMediaPicker = new FakeMediaPicker();
      const mockPhotos: PickedMedia[] = [
        { uri: 'file://media/photo1.jpg', path: '/sandbox/photo1.jpg', name: 'photo1.jpg', size: 102400 },
        { uri: 'file://media/photo2.jpg', path: '/sandbox/photo2.jpg', name: 'photo2.jpg', size: 204800 }
      ];
      picker.setPhotosToReturn(mockPhotos);

      const single: PickedMedia[] = await picker.pickPhoto(1);
      expect(single.length).assertEqual(1);
      expect(single[0].uri).assertEqual('file://media/photo1.jpg');
      expect(single[0].path).assertEqual('/sandbox/photo1.jpg');
      expect(picker.pickPhotoCalls).assertEqual(1);

      const multiple: PickedMedia[] = await picker.pickPhoto(5);
      expect(multiple.length).assertEqual(2);
      expect(picker.pickPhotoCalls).assertEqual(2);
    });

    it('pickFile_returnsMockedFiles_succeeds', 0, async () => {
      const picker: FakeMediaPicker = new FakeMediaPicker();
      const mockFiles: PickedMedia[] = [
        { uri: 'file://docs/doc.pdf', path: '/sandbox/doc.pdf', name: 'doc.pdf', size: 512000, mimeType: 'application/pdf' }
      ];
      picker.setFilesToReturn(mockFiles);

      const files: PickedMedia[] = await picker.pickFile(1);
      expect(files.length).assertEqual(1);
      expect(files[0].name).assertEqual('doc.pdf');
      expect(picker.pickFileCalls).assertEqual(1);
    });

    it('pickPhoto_handlesRejection_whenConfigured', 0, async () => {
      const picker: FakeMediaPicker = new FakeMediaPicker();
      picker.shouldReject = true;
      picker.rejectError = new Error('Permission denied');

      let caught: boolean = false;
      try {
        await picker.pickPhoto();
      } catch (err) {
        caught = true;
      }
      expect(caught).assertTrue();
    });

    it('pickVideo_returnsMockedVideos_withMetadataAndThumbnail', 0, async () => {
      const picker: FakeMediaPicker = new FakeMediaPicker();
      const mockVideos: PickedMedia[] = [
        {
          uri: 'file://media/video1.mp4',
          path: '/sandbox/video1.mp4',
          name: 'video1.mp4',
          size: 5242880,
          mimeType: 'video/mp4',
          duration: 12,
          width: 1920,
          height: 1080,
          thumbnailPath: '/sandbox/thumb_1.jpg',
          thumbnailWidth: 320,
          thumbnailHeight: 180
        },
        { uri: 'file://media/video2.mp4', path: '/sandbox/video2.mp4', name: 'video2.mp4' }
      ];
      picker.setVideosToReturn(mockVideos);

      const single: PickedMedia[] = await picker.pickVideo(1);
      expect(single.length).assertEqual(1);
      expect(single[0].path).assertEqual('/sandbox/video1.mp4');
      expect(single[0].duration).assertEqual(12);
      expect(single[0].width).assertEqual(1920);
      expect(single[0].height).assertEqual(1080);
      expect(single[0].thumbnailPath).assertEqual('/sandbox/thumb_1.jpg');
      expect(single[0].thumbnailWidth).assertEqual(320);
      expect(single[0].thumbnailHeight).assertEqual(180);
      expect(picker.pickVideoCalls).assertEqual(1);

      const all: PickedMedia[] = await picker.pickVideo(5);
      expect(all.length).assertEqual(2);
      // 第二条没有元数据/缩略图仍是合法输入（模拟抽帧失败），字段应保持 undefined
      expect(all[1].duration === undefined).assertTrue();
      expect(all[1].thumbnailPath === undefined).assertTrue();
      expect(picker.pickVideoCalls).assertEqual(2);
    });

    it('pickVideo_handlesRejection_whenConfigured', 0, async () => {
      const picker: FakeMediaPicker = new FakeMediaPicker();
      picker.shouldReject = true;
      picker.rejectError = new Error('User cancelled');

      let caught: boolean = false;
      try {
        await picker.pickVideo();
      } catch (err) {
        caught = true;
      }
      expect(caught).assertTrue();
      expect(picker.pickVideoCalls).assertEqual(1);
    });

    it('reset_clearsState', 0, async () => {
      const picker: FakeMediaPicker = new FakeMediaPicker();
      picker.setPhotosToReturn([{ uri: 'photo.png' }]);
      await picker.pickPhoto();
      expect(picker.pickPhotoCalls).assertEqual(1);

      picker.reset();
      expect(picker.pickPhotoCalls).assertEqual(0);
      const empty: PickedMedia[] = await picker.pickPhoto();
      expect(empty.length).assertEqual(0);
    });

    it('reset_alsoClearsVideoState', 0, async () => {
      const picker: FakeMediaPicker = new FakeMediaPicker();
      picker.setVideosToReturn([{ uri: 'v.mp4', duration: 3 }]);
      const before: PickedMedia[] = await picker.pickVideo();
      expect(before.length).assertEqual(1);
      expect(picker.pickVideoCalls).assertEqual(1);

      picker.reset();
      expect(picker.pickVideoCalls).assertEqual(0);
      const empty: PickedMedia[] = await picker.pickVideo();
      expect(empty.length).assertEqual(0);
    });

  });
}
