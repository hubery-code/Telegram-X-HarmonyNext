/**
 * feature/profile — 音乐/语音行纯函数单元测试（SHARED-AUDIO）。
 *
 * 守住的行为：
 * 1. 标题/副标题三条分支与 Android `TD.getTitle` / `TD.getSubtitle` 同口径
 *    （performer+title → 时长 → 文件大小），别在页面里各写一套；
 * 2. 语音行标题是「昵称 → 自己发的『我』→ 空串」，空串才允许组件回落到「语音消息」，
 *    绝不把裸 user id 印到界面上；
 * 3. 按 Tab 局部替换/追加：音乐页追加不能冲掉语音页已经到手的数据，反之亦然；
 * 4. 落盘回灌只动命中且原本没有路径的那一行，没命中就返回 null（调用方据此不刷状态）。
 */

import { describe, expect, it } from '@ohos/hypium';
import {
  SharedAudioItem,
  SharedContentRows,
  SharedMediaItem
} from '../main/ets/contract/SharedContentItems';
import {
  audioSessionMetadata,
  audioSubtitleOf,
  audioTitleOf,
  formatSharedDuration,
  voiceTitleOf,
  withSharedAudioPath
} from '../main/ets/model/SharedContentFormat';
import { AudioPlaybackMetadata } from '@tgx/platform-ports';
import {
  mergeSharedRows,
  SHARED_TAB_AUDIO,
  SHARED_TAB_MEDIA,
  SHARED_TAB_VOICE
} from '../main/ets/model/SharedContentSearch';

function audio(fileId: number, localPath: string | null = null): SharedAudioItem {
  return new SharedAudioItem(fileId, localPath, `T${fileId}`, 'A', 'sub', 60, 1700000000);
}

export default function sharedAudioRowsTest(): void {
  describe('SharedAudioRowsTest', (): void => {

    it('audioTitle_prefersTagThenFileNameWithoutExtension', 0, () => {
      expect(audioTitleOf('moon.mp3', 'Moon River')).assertEqual('Moon River');
      expect(audioTitleOf('moon.mp3', '')).assertEqual('moon');
      // 无扩展名 / 隐藏文件式名字（点在 0）都不该被削成空串。
      expect(audioTitleOf('track', '')).assertEqual('track');
      expect(audioTitleOf('.mp3', '')).assertEqual('.mp3');
      expect(audioTitleOf('', '')).assertEqual('');
    });

    it('audioSubtitle_threeBranchesLikeAndroid', 0, () => {
      expect(audioSubtitleOf('Andy', 'Moon River', 214, 1024)).assertEqual('Andy - Moon River');
      expect(audioSubtitleOf('Andy', '', 214, 1024)).assertEqual('Andy');
      expect(audioSubtitleOf('', 'Moon River', 214, 1024)).assertEqual('3:34');
      expect(audioSubtitleOf('', '', 214, 1024)).assertEqual('1.0 KB');
      expect(formatSharedDuration(3720)).assertEqual('1:02:00');
    });

    it('voiceTitle_neverLeaksBareUserId', 0, () => {
      expect(voiceTitleOf('张三', false)).assertEqual('张三');
      expect(voiceTitleOf('', true)).assertEqual('我');
      // 昵称还没到 + 不是自己发的 → 空串，由组件回落「语音消息」。
      expect(voiceTitleOf('', false)).assertEqual('');
    });

    it('mergeSharedRows_replacesAndAppendsOnlyItsOwnTab', 0, () => {
      const current: SharedContentRows = new SharedContentRows({
        media: [new SharedMediaItem(1, null, true)],
        audios: [audio(11)],
        voices: [audio(21)]
      });

      const replaced: SharedContentRows =
        mergeSharedRows(current, SHARED_TAB_AUDIO, new SharedContentRows({ audios: [audio(12)] }), false);
      expect(replaced.audios.length).assertEqual(1);
      expect(replaced.audios[0].fileId).assertEqual(12);
      expect(replaced.voices.length).assertEqual(1);
      expect(replaced.voices[0].fileId).assertEqual(21);
      expect(replaced.media.length).assertEqual(1);

      const appended: SharedContentRows =
        mergeSharedRows(replaced, SHARED_TAB_VOICE, new SharedContentRows({ voices: [audio(22)] }), true);
      expect(appended.voices.length).assertEqual(2);
      expect(appended.voices[1].fileId).assertEqual(22);
      expect(appended.audios.length).assertEqual(1);

      // 媒体页的续页不会把音频数组顺手清掉（早期三数组签名就是靠位置传，最容易在这里错）。
      const mediaPage: SharedContentRows =
        mergeSharedRows(appended, SHARED_TAB_MEDIA, new SharedContentRows({ media: [] }), true);
      expect(mediaPage.voices.length).assertEqual(2);
      expect(mediaPage.audios.length).assertEqual(1);
    });

    it('withSharedAudioPath_fillsOnlyTheMatchedEmptyRow', 0, () => {
      const items: SharedAudioItem[] = [audio(11), audio(12, '/already.mp3')];

      const filled: SharedAudioItem[] | null = withSharedAudioPath(items, 11, '/sandbox/11.mp3');
      expect(filled !== null).assertTrue();
      expect(filled !== null ? filled[0].localPath : '').assertEqual('/sandbox/11.mp3');
      // 标题等展示字段原样保留。
      expect(filled !== null ? filled[0].title : '').assertEqual('T11');
      expect(filled !== null ? filled[1].localPath : '').assertEqual('/already.mp3');

      // 没命中（或已经有路径）时返回 null，调用方据此不派发无意义的状态回灌。
      expect(withSharedAudioPath(items, 99, '/x.mp3')).assertNull();
      expect(withSharedAudioPath(items, 12, '/y.mp3')).assertNull();
    });

    it('audioSessionMetadata_mapsRowsForLockScreenCard', 0, () => {
      // 音乐行：标题/表演者给 TD 的元数据，时长秒→毫秒（AVSession 全按毫秒计）。
      const music: SharedAudioItem = audio(11);
      const musicMeta: AudioPlaybackMetadata = audioSessionMetadata(music, false, 'El CLUB');
      expect(musicMeta.assetId).assertEqual('11');
      expect(musicMeta.title).assertEqual('T11');
      expect(musicMeta.artist).assertEqual('A');
      expect(musicMeta.durationMs).assertEqual(60000);

      // 语音行标题为空：锁屏上不能印一堆随机落盘文件名，回落到「语音消息」，
      // 第二行留给会话名（表演者为空时才用 contextTitle）。
      const voice: SharedAudioItem = new SharedAudioItem(21, null, '', '', '0:07, 128 KB', 7);
      const voiceMeta: AudioPlaybackMetadata = audioSessionMetadata(voice, true, 'be hu');
      expect(voiceMeta.title).assertEqual('语音消息');
      expect(voiceMeta.artist).assertEqual('be hu');
      expect(voiceMeta.durationMs).assertEqual(7000);

      // 音乐行没标题时保持空串，交给 entry 侧按文件名兜底（那里才知道路径）。
      const bare: SharedAudioItem = new SharedAudioItem(31, null, '', 'Perf', '3:34', 214);
      expect(audioSessionMetadata(bare, false, '频道').title).assertEqual('');
      expect(audioSessionMetadata(bare, false, '频道').artist).assertEqual('Perf');
    });
  });
}
