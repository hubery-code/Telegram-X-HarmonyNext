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
  AutoDownloadChatScope,
  AutoDownloadFlags,
  AutoDownloadMediaKind,
  AutoDownloadPolicy,
  autoDownloadScopeForChatKind,
  canAutoDownloadMedia
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

    // AUTODL-103：尺寸上限不再是这一层的规则 —— 它按网络档存在
    // `media/MediaDownloadLimits` 里（Android 的 settings_limit_* 三档），
    // 由聊天页的下载门在分区勾选之前先判。这里只留「勾选」这一件事。
  });
}
