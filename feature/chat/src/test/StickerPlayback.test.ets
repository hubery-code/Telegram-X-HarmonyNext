/**
 * feature/chat — 动效贴纸播放态记账单测（TGS-102）。
 *
 * 钉住四件事：
 * - **窗口内才续播**：重建挤在几百毫秒里，命中窗口就从记录帧接着演；滑走再回来已过窗口，
 *   按首演重放（与 Android「重新入镜再演一次」一致），否则一条播过的贴纸会永远停在末帧；
 * - **演完的标志压过帧号**：`complete` 之后迟到的 `enterFrame` 不能把它拽回'resume'；
 * - **空 key 不记账**：拿不到消息 id 的桩渲染一律首演，也不污染账本；
 * - **淘汰按最近推进**：容量满了先踢最久没推进的那条，而不是最先插进来的那条。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  PLAYBACK_LEDGER_LIMIT,
  RESUME_WINDOW_MS,
  StickerPlaybackLedger,
  StickerPlayPlan,
  StickerPlayRecord,
  stickerPlayPlan
} from '../main/ets/model/StickerPlayback';

const T0: number = 1000000;

export default function stickerPlaybackTest() {
  describe('StickerPlaybackTest', () => {

    it('pure_plan_first_when_there_is_no_record', 0, () => {
      const plan: StickerPlayPlan = stickerPlayPlan(null, T0);
      expect(plan.mode).assertEqual('first');
      expect(plan.frame).assertEqual(0);
    });

    it('pure_plan_window_boundary_is_inclusive', 0, () => {
      const rec: StickerPlayRecord = new StickerPlayRecord(12.5, false, T0);
      expect(stickerPlayPlan(rec, T0 + RESUME_WINDOW_MS).mode).assertEqual('resume');
      expect(stickerPlayPlan(rec, T0 + RESUME_WINDOW_MS + 1).mode).assertEqual('first');
    });

    it('pure_plan_finished_wins_over_frame', 0, () => {
      const rec: StickerPlayRecord = new StickerPlayRecord(179, true, T0);
      const plan: StickerPlayPlan = stickerPlayPlan(rec, T0 + 10);
      expect(plan.mode).assertEqual('finished');
      // 末帧位置取自记录里实际推进到的那一帧，不去猜 totalFrames
      expect(plan.frame).assertEqual(179);
    });

    it('ledger_resumes_at_the_recorded_frame', 0, () => {
      const ledger: StickerPlaybackLedger = new StickerPlaybackLedger();
      ledger.noteFrame('41', 0, T0);
      ledger.noteFrame('41', 37.25, T0 + 120);
      const plan: StickerPlayPlan = ledger.plan('41', T0 + 200);
      expect(plan.mode).assertEqual('resume');
      expect(plan.frame).assertEqual(37.25);
    });

    it('ledger_late_frame_after_complete_does_not_replay', 0, () => {
      const ledger: StickerPlaybackLedger = new StickerPlaybackLedger();
      ledger.noteFrame('42', 178, T0);
      ledger.noteFinished('42', 179, T0 + 50);
      // 销毁前最后一帧的回调晚到：只能刷新时刻，不能改帧号也不能翻回未演完
      ledger.noteFrame('42', 12, T0 + 60);
      const plan: StickerPlayPlan = ledger.plan('42', T0 + 100);
      expect(plan.mode).assertEqual('finished');
      expect(plan.frame).assertEqual(179);
    });

    it('ledger_finished_without_prior_progress_still_reports_last_frame', 0, () => {
      const ledger: StickerPlaybackLedger = new StickerPlaybackLedger();
      ledger.noteFinished('43', 60, T0);
      const plan: StickerPlayPlan = ledger.plan('43', T0 + 10);
      expect(plan.mode).assertEqual('finished');
      expect(plan.frame).assertEqual(60);
    });

    it('ledger_stale_entry_degrades_to_first', 0, () => {
      const ledger: StickerPlaybackLedger = new StickerPlaybackLedger();
      ledger.noteFrame('44', 20, T0);
      expect(ledger.plan('44', T0 + RESUME_WINDOW_MS + 500).mode).assertEqual('first');
      // 过期记录不清掉：它只是不再被采信，等新挂载把它推回窗口内即可
      ledger.noteFrame('44', 0, T0 + 3000);
      expect(ledger.plan('44', T0 + 3100).mode).assertEqual('resume');
    });

    it('empty_key_never_accounts', 0, () => {
      const ledger: StickerPlaybackLedger = new StickerPlaybackLedger();
      ledger.noteFrame('', 30, T0);
      ledger.noteFrame(null, 30, T0);
      ledger.noteFinished('', 30, T0);
      expect(ledger.size()).assertEqual(0);
      expect(ledger.get('')).assertNull();
      expect(ledger.get(null)).assertNull();
      expect(ledger.plan(null, T0).mode).assertEqual('first');
    });

    it('same_sticker_in_two_messages_keeps_separate_progress', 0, () => {
      // fileId 是贴纸包共享的，所以账本按消息 id 记：第二条不能因为第一条演完就不演
      const ledger: StickerPlaybackLedger = new StickerPlaybackLedger();
      ledger.noteFrame('101', 10, T0);
      ledger.noteFinished('101', 180, T0 + 20);
      expect(ledger.plan('101', T0 + 30).mode).assertEqual('finished');
      expect(ledger.plan('102', T0 + 30).mode).assertEqual('first');
    });

    it('eviction_follows_last_progress', 0, () => {
      const ledger: StickerPlaybackLedger = new StickerPlaybackLedger(3);
      ledger.noteFrame('a', 1, T0);
      ledger.noteFrame('b', 1, T0 + 1);
      ledger.noteFrame('c', 1, T0 + 2);
      // a 被推回队尾，容量满时该先踢 b
      ledger.noteFrame('a', 2, T0 + 3);
      ledger.noteFrame('d', 1, T0 + 4);
      expect(ledger.size()).assertEqual(3);
      expect(ledger.get('b')).assertNull();
      expect(ledger.get('a') === null).assertFalse();
      expect(ledger.get('c') === null).assertFalse();
      expect(ledger.get('d') === null).assertFalse();
    });

    it('default_limit_is_the_documented_one', 0, () => {
      expect(PLAYBACK_LEDGER_LIMIT).assertEqual(128);
      expect(RESUME_WINDOW_MS).assertEqual(1500);
    });
  });
}
