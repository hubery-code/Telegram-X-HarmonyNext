/**
 * feature/chat — 媒体圆钮无障碍槽位单元测试（A11Y-101）。
 *
 * 断的是「按钮在说什么」与「按下去会发生什么」必须一致：同一颗圆钮在下载中念「播放」、
 * 在失败时念「下载」，屏幕朗读用户就会在取消下载的手势上发出下载请求。
 * 优先级（失败 > 上传 > 下载 > 未下载 > 播放/暂停/打开）是这里唯一值得钉住的东西。
 */

import { describe, it, expect } from '@ohos/hypium';
import { A11y } from '@tgx/core-common';
import { mediaCircleA11ySlot } from '../main/ets/model/MediaA11y';

export default function mediaA11yTest(): void {
  describe('MediaA11yTest', () => {
    it('failedState_winsOverEveryOtherFlag', 0, () => {
      expect(mediaCircleA11ySlot(true, true, true, true, true, true)).assertEqual(A11y.RETRY_SEND);
    });

    it('uploadingState_offersCancelUpload', 0, () => {
      expect(mediaCircleA11ySlot(false, true, false, false, false, true)).assertEqual(A11y.CANCEL_UPLOAD);
    });

    it('downloadingState_offersCancelDownload', 0, () => {
      expect(mediaCircleA11ySlot(false, false, true, false, false, true)).assertEqual(A11y.CANCEL_DOWNLOAD);
    });

    it('readyState_offersDownload', 0, () => {
      expect(mediaCircleA11ySlot(false, false, false, false, false, true)).assertEqual(A11y.DOWNLOAD);
    });

    it('downloadedPlayableState_followsPlayback', 0, () => {
      expect(mediaCircleA11ySlot(false, false, false, true, false, true)).assertEqual(A11y.PLAY);
      expect(mediaCircleA11ySlot(false, false, false, true, true, true)).assertEqual(A11y.PAUSE);
    });

    it('downloadedDocumentState_offersOpenFile', 0, () => {
      expect(mediaCircleA11ySlot(false, false, false, true, false, false)).assertEqual(A11y.OPEN_FILE);
    });
  });
}
