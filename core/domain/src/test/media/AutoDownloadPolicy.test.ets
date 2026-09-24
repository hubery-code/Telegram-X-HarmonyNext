/**
 * core/domain — 自动媒体下载策略单元测试（AUTODL-101）。
 *
 * 守住的回归：
 * 1. 掩码位序是唯一「跨版本可存」的约定 —— 位序一改，用户已存的偏好就会把
 *    「照片」读成「动图」，所以 7 位逐位点亮 + 0..127 全量往返；
 * 2. 默认值必须等于 Android 的兜底（照片/语音/视频便签/动图开，视频/文件/音乐关），
 *    否则第一次打开这个页面看到的是自己造的默认；
 * 3. 读不到策略或读不到会话类型时必须**放行** —— 拦下载比多下载更难被发现，
 *    但「设置还没加载完就把所有媒体挡掉」会让用户以为图片坏了。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  AUTO_DOWNLOAD_KINDS,
  AUTO_DOWNLOAD_SIZE_LIMIT_BYTES,
  AutoDownloadChatScope,
  AutoDownloadFlags,
  AutoDownloadMediaKind,
  AutoDownloadPolicy,
  autoDownloadScopeForChatKind,
  canAutoDownloadMedia,
  isAutoDownloadSizeAllowed,
  shouldAutoDownloadMedia
} from '../../main/ets/media/AutoDownloadPolicy';

function flagsOf(photo: boolean, voice: boolean, videoNote: boolean,
  video: boolean, file: boolean, audio: boolean, gif: boolean): AutoDownloadFlags {
  return new AutoDownloadFlags(photo, voice, videoNote, video, file, audio, gif);
}

export default function autoDownloadPolicyTest() {
  describe('AutoDownloadPolicy', () => {

    it('defaultFlags_matchAndroidFallback', 0, () => {
      const flags: AutoDownloadFlags = AutoDownloadFlags.defaultFlags();
      expect(flags.photo).assertTrue();
      expect(flags.voice).assertTrue();
      expect(flags.videoNote).assertTrue();
      expect(flags.gif).assertTrue();
      expect(flags.video).assertFalse();
      expect(flags.file).assertFalse();
      expect(flags.audio).assertFalse();
      // 三个分区默认同一份兜底
      const policy: AutoDownloadPolicy = AutoDownloadPolicy.defaultPolicy();
      expect(policy.groupFlags.toMask()).assertEqual(flags.toMask());
      expect(policy.channelFlags.toMask()).assertEqual(flags.toMask());
    });

    it('mask_mapsEachKindToItsOwnBit', 0, () => {
      for (let index = 0; index < AUTO_DOWNLOAD_KINDS.length; index++) {
        const kind: AutoDownloadMediaKind = AUTO_DOWNLOAD_KINDS[index];
        const flags: AutoDownloadFlags = AutoDownloadFlags.fromMask(1 << index);
        expect(flags.of(kind)).assertTrue();
        for (const other of AUTO_DOWNLOAD_KINDS) {
          if (other !== kind) {
            expect(flags.of(other)).assertFalse();
          }
        }
      }
    });

    it('mask_roundTripsEveryCombination', 0, () => {
      for (let mask = 0; mask < 128; mask++) {
        expect(AutoDownloadFlags.fromMask(mask).toMask()).assertEqual(mask);
      }
    });

    it('with_returnsNewFlagsAndLeavesSourceAlone', 0, () => {
      const source: AutoDownloadFlags = AutoDownloadFlags.defaultFlags();
      const before: number = source.toMask();
      const next: AutoDownloadFlags = source.with('video', true);
      expect(next.video).assertTrue();
      expect(source.video).assertFalse();
      expect(source.toMask()).assertEqual(before);
      expect(next.with('video', false).toMask()).assertEqual(before);
    });

    it('enabledKinds_followMaskOrderAndStayStable', 0, () => {
      const kinds: AutoDownloadMediaKind[] = AutoDownloadFlags.defaultFlags().enabledKinds();
      expect(kinds.length).assertEqual(4);
      expect(kinds[0]).assertEqual('photo');
      expect(kinds[1]).assertEqual('voice');
      expect(kinds[2]).assertEqual('videoNote');
      expect(kinds[3]).assertEqual('gif');
      expect(new AutoDownloadFlags().enabledKinds().length).assertEqual(0);
      expect(new AutoDownloadFlags().isEnabled()).assertFalse();
    });

    it('storage_roundTripsPerScope', 0, () => {
      const policy: AutoDownloadPolicy = AutoDownloadPolicy.defaultPolicy()
        .withFlags('private', flagsOf(false, true, false, false, false, false, false))
        .withFlags('group', new AutoDownloadFlags())
        .withFlags('channel', flagsOf(true, true, true, true, true, true, true));
      const restored: AutoDownloadPolicy = AutoDownloadPolicy.fromStorageValues(policy.toStorageValues());
      expect(restored.equals(policy)).assertTrue();
      expect(restored.privateFlags.toMask()).assertEqual(policy.privateFlags.toMask());
      expect(restored.groupFlags.isEnabled()).assertFalse();
      expect(restored.channelFlags.toMask()).assertEqual(127);
    });

    it('storage_missingOrBrokenValuesFallBackToDefault', 0, () => {
      const expected: number = AutoDownloadFlags.defaultFlags().toMask();
      const allDefault: AutoDownloadPolicy = AutoDownloadPolicy.fromStorageValues([null, null, null]);
      expect(allDefault.privateFlags.toMask()).assertEqual(expected);
      expect(allDefault.channelFlags.toMask()).assertEqual(expected);
      // 负数 / 非有限值来自被改坏的偏好文件，不能读成「全开」
      const broken: AutoDownloadPolicy = AutoDownloadPolicy.fromStorageValues([-1, NaN, 3.5]);
      expect(broken.privateFlags.toMask()).assertEqual(expected);
      expect(broken.groupFlags.toMask()).assertEqual(expected);
      expect(broken.channelFlags.toMask()).assertEqual(3);
    });

    it('withFlags_doesNotTouchOtherScopes', 0, () => {
      const policy: AutoDownloadPolicy = AutoDownloadPolicy.defaultPolicy();
      const next: AutoDownloadPolicy = policy.withFlags('group', new AutoDownloadFlags());
      expect(next.groupFlags.isEnabled()).assertFalse();
      expect(next.privateFlags.equals(policy.privateFlags)).assertTrue();
      expect(next.channelFlags.equals(policy.channelFlags)).assertTrue();
      expect(policy.groupFlags.isEnabled()).assertTrue();
      expect(next.equals(policy)).assertFalse();
      expect(next.equals(next)).assertTrue();
      expect(next.equals(null)).assertFalse();
    });

    it('scopeForChatKind_mapsOnlyKnownKinds', 0, () => {
      expect(autoDownloadScopeForChatKind('private')).assertEqual('private');
      expect(autoDownloadScopeForChatKind('group')).assertEqual('group');
      expect(autoDownloadScopeForChatKind('channel')).assertEqual('channel');
      const unknown: AutoDownloadChatScope | null = autoDownloadScopeForChatKind('unknown');
      expect(unknown === null).assertTrue();
      expect(autoDownloadScopeForChatKind('saved') === null).assertTrue();
      expect(autoDownloadScopeForChatKind('') === null).assertTrue();
    });

    it('gate_respectsFlagsPerScope', 0, () => {
      const policy: AutoDownloadPolicy = AutoDownloadPolicy.defaultPolicy()
        .withFlags('channel', new AutoDownloadFlags());
      expect(canAutoDownloadMedia(policy, 'private', 'photo')).assertTrue();
      expect(canAutoDownloadMedia(policy, 'group', 'video')).assertFalse();
      expect(canAutoDownloadMedia(policy, 'channel', 'photo')).assertFalse();
      expect(canAutoDownloadMedia(policy, 'channel', 'file')).assertFalse();
    });

    it('gate_allowsWhenPolicyOrKindUnknown', 0, () => {
      // 偏好读不到（首帧、读盘失败）不能把媒体全挡住
      expect(canAutoDownloadMedia(null, 'group', 'photo')).assertTrue();
      expect(canAutoDownloadMedia(null, 'unknown', 'video')).assertTrue();
      const policy: AutoDownloadPolicy = AutoDownloadPolicy.defaultPolicy()
        .withFlags('group', new AutoDownloadFlags());
      expect(canAutoDownloadMedia(policy, 'unknown', 'photo')).assertTrue();
    });

    it('sizeGate_onlyLimitsContainerKinds', 0, () => {
      const limit: number = AUTO_DOWNLOAD_SIZE_LIMIT_BYTES;
      expect(isAutoDownloadSizeAllowed('video', limit)).assertTrue();
      expect(isAutoDownloadSizeAllowed('video', limit + 1)).assertFalse();
      expect(isAutoDownloadSizeAllowed('file', 2 * limit)).assertFalse();
      expect(isAutoDownloadSizeAllowed('audio', 2 * limit)).assertFalse();
      // 照片 / 语音 / 视频便签 / 动图本身有限，不受尺寸闸门约束
      expect(isAutoDownloadSizeAllowed('photo', 2 * limit)).assertTrue();
      expect(isAutoDownloadSizeAllowed('voice', 2 * limit)).assertTrue();
      expect(isAutoDownloadSizeAllowed('videoNote', 2 * limit)).assertTrue();
      expect(isAutoDownloadSizeAllowed('gif', 2 * limit)).assertTrue();
    });

    it('sizeGate_allowsWhenServerGivesNoSize', 0, () => {
      // size<=0 表示服务端没给尺寸（远端未同步完），按放行处理而不是当成 0 字节超大
      expect(isAutoDownloadSizeAllowed('video', 0)).assertTrue();
      expect(isAutoDownloadSizeAllowed('file', -1)).assertTrue();
      expect(isAutoDownloadSizeAllowed('audio', NaN)).assertTrue();
      expect(isAutoDownloadSizeAllowed('video', Infinity)).assertTrue();
    });

    it('shouldAutoDownload_needsBothCheckAndSize', 0, () => {
      const policy: AutoDownloadPolicy = AutoDownloadPolicy.defaultPolicy()
        .withFlags('channel', new AutoDownloadFlags());
      const limit: number = AUTO_DOWNLOAD_SIZE_LIMIT_BYTES;
      // 默认勾了照片 → 小照片放行
      expect(shouldAutoDownloadMedia(policy, 'private', 'photo', 1024)).assertTrue();
      // 默认没勾视频 → 再小也不自动下
      expect(shouldAutoDownloadMedia(policy, 'private', 'video', 1024)).assertFalse();
      // 频道全关 → 连照片都不下
      expect(shouldAutoDownloadMedia(policy, 'channel', 'photo', 1024)).assertFalse();
      // 群组分区把视频打开后，尺寸闸门仍然生效
      const videoOn: AutoDownloadPolicy = policy.withFlags('group', AutoDownloadFlags.defaultFlags().with('video', true));
      expect(shouldAutoDownloadMedia(videoOn, 'group', 'video', limit)).assertTrue();
      expect(shouldAutoDownloadMedia(videoOn, 'group', 'video', limit + 1)).assertFalse();
      // 策略为 null 时走的是「放行 + 闸门」，与聊天页 provider 未注入的语义一致
      expect(shouldAutoDownloadMedia(null, 'group', 'file', limit + 1)).assertFalse();
      expect(shouldAutoDownloadMedia(null, 'group', 'photo', limit + 1)).assertTrue();
      // NaN 尺寸：闸门放行，所以结果只由勾选决定
      expect(shouldAutoDownloadMedia(policy, 'private', 'video', NaN)).assertFalse();
      expect(shouldAutoDownloadMedia(videoOn, 'group', 'video', NaN)).assertTrue();
    });
  });
}
