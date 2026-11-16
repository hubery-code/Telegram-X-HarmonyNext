/**
 * entry/src/test/share/ShareIntake.test.ets — 系统分享接收入口（SHARE-EXT-101）。
 *
 * 覆盖两层：纯提取函数（want/记录组 → 文本与文件 uri 的判定）与
 * ShareQueue（与 DeepLinkQueue 同一套时序纪律：谁先谁后、丢不丢、会不会自喂）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  ACTION_SEND_DATA,
  ACTION_SEND_MULTIPLE_DATA,
  ReceivedShare,
  SHARE_MAX_PENDING,
  ShareQueue,
  ShareRecordLike,
  isShareAction,
  shareFileUrisFromParams,
  shareTextFromRecords,
  shareTextFromWantParts
} from '../../main/ets/share/ShareIntake';

export default function shareIntakeTest() {
  describe('ShareIntakeTest', () => {
    it('isShareAction_matchesSendActionsOnly', 0, () => {
      expect(isShareAction(ACTION_SEND_DATA)).assertTrue();
      expect(isShareAction(ACTION_SEND_MULTIPLE_DATA)).assertTrue();
      expect(isShareAction('ohos.want.action.viewData')).assertFalse();
      expect(isShareAction('ohos.want.action.home')).assertFalse();
      expect(isShareAction('')).assertFalse();
      expect(isShareAction(undefined)).assertFalse();
      expect(isShareAction(null)).assertFalse();
    });

    it('shareTextFromRecords_takesFirstNonEmptyContent', 0, () => {
      const records: ShareRecordLike[] = [
        { utd: 'general.image', title: 'pic.png', content: '', uri: 'file://a.png' },
        { utd: 'general.plain-text', title: '', content: '  hello world  ', uri: '' }
      ];
      expect(shareTextFromRecords(records)).assertEqual('hello world');
      // 全空（纯文件分享）→ 空串，由上层提示「没有可分享的文本」。
      const fileOnly: ShareRecordLike[] = [
        { utd: 'general.image', title: 'pic.png', content: '', uri: 'file://a.png' }
      ];
      expect(shareTextFromRecords(fileOnly)).assertEqual('');
      expect(shareTextFromRecords([])).assertEqual('');
    });

    it('shareTextFromWantParts_prefersUriButRejectsFileUris', 0, () => {
      expect(shareTextFromWantParts('hello from browser', undefined)).assertEqual('hello from browser');
      // file:// / content:// 是文件引用，不能当正文发出去。
      expect(shareTextFromWantParts('file://data/storage/a.txt', undefined)).assertEqual('');
      expect(shareTextFromWantParts('content://media/a.png', undefined)).assertEqual('');
      expect(shareTextFromWantParts('   ', undefined)).assertEqual('');
    });

    it('shareTextFromWantParts_fallsBackToKnownParamKeys', 0, () => {
      const params: Record<string, Object> = {
        'ohos.extra.param.key.shareAbstract': 'shared abstract',
        'ohos.extra.param.key.contentTitle': 'shared title'
      };
      expect(shareTextFromWantParts('', params)).assertEqual('shared abstract');
      expect(shareTextFromWantParts('', { 'text': 'plain text' })).assertEqual('plain text');
      expect(shareTextFromWantParts('', { 'content': 123 })).assertEqual('');
      expect(shareTextFromWantParts('', undefined)).assertEqual('');
    });

    it('shareFileUrisFromParams_readsStreamList', 0, () => {
      const params: Record<string, Object> = {
        'ability.params.stream': ['file://a.png', 'file://b.png']
      };
      const uris: string[] = shareFileUrisFromParams(params);
      expect(uris.length).assertEqual(2);
      expect(uris[0]).assertEqual('file://a.png');
      // 单个字符串也收下；非字符串元素忽略。
      expect(shareFileUrisFromParams({ 'ability.params.stream': 'file://c.png' }).length).assertEqual(1);
      expect(shareFileUrisFromParams({ 'ability.params.stream': [1, 'file://d.png'] }).length).assertEqual(1);
      expect(shareFileUrisFromParams(undefined).length).assertEqual(0);
      expect(shareFileUrisFromParams({}).length).assertEqual(0);
    });

    it('shareQueue_enqueueBeforeAttach_isQueuedAndFlushedInOrder', 0, () => {
      const queue: ShareQueue = new ShareQueue();
      expect(queue.enqueue(new ReceivedShare('first', []))).assertEqual('queued');
      expect(queue.enqueue(new ReceivedShare('second', ['file://a']))).assertEqual('queued');
      expect(queue.pendingCount()).assertEqual(2);

      const delivered: string[] = [];
      const flushed: number = queue.attach((share: ReceivedShare): void => {
        delivered.push(share.text);
      });
      expect(flushed).assertEqual(2);
      expect(delivered.join(',')).assertEqual('first,second');
      expect(queue.pendingCount()).assertEqual(0);
      expect(queue.isAttached()).assertTrue();
    });

    it('shareQueue_enqueueAfterAttach_deliversImmediately', 0, () => {
      const queue: ShareQueue = new ShareQueue();
      const delivered: string[] = [];
      queue.attach((share: ReceivedShare): void => {
        delivered.push(share.text);
      });
      expect(queue.enqueue(new ReceivedShare('live', []))).assertEqual('delivered');
      expect(delivered.join(',')).assertEqual('live');
    });

    it('shareQueue_dedupe_appliesOnlyToUndeliveredBacklog', 0, () => {
      const queue: ShareQueue = new ShareQueue();
      expect(queue.enqueue(new ReceivedShare('same text', []))).assertEqual('queued');
      expect(queue.enqueue(new ReceivedShare('same text', []))).assertEqual('duplicate');
      expect(queue.pendingCount()).assertEqual(1);

      const delivered: string[] = [];
      queue.attach((share: ReceivedShare): void => {
        delivered.push(share.text);
      });
      // 已交付过的同文分享再来一次是真想再发一趟，不该被吞。
      expect(queue.enqueue(new ReceivedShare('same text', []))).assertEqual('delivered');
      expect(delivered.length).assertEqual(2);
    });

    it('shareQueue_emptyShare_rejected', 0, () => {
      const queue: ShareQueue = new ShareQueue();
      expect(queue.enqueue(new ReceivedShare('   ', []))).assertEqual('empty');
      expect(queue.enqueue(new ReceivedShare('', []))).assertEqual('empty');
      expect(queue.pendingCount()).assertEqual(0);
    });

    it('shareQueue_cap_dropsOldest', 0, () => {
      const queue: ShareQueue = new ShareQueue();
      for (let i = 0; i < SHARE_MAX_PENDING + 3; i++) {
        queue.enqueue(new ReceivedShare(`msg-${i}`, []));
      }
      expect(queue.pendingCount()).assertEqual(SHARE_MAX_PENDING);
      const delivered: string[] = [];
      queue.attach((share: ReceivedShare): void => {
        delivered.push(share.text);
      });
      // 丢的是最旧的三条，留下的是最后 8 条、顺序不变。
      expect(delivered[0]).assertEqual('msg-3');
      expect(delivered[delivered.length - 1]).assertEqual(`msg-${SHARE_MAX_PENDING + 2}`);
    });

    it('shareQueue_handlerThrow_doesNotStallBacklog', 0, () => {
      const queue: ShareQueue = new ShareQueue();
      queue.enqueue(new ReceivedShare('a', []));
      queue.enqueue(new ReceivedShare('b', []));
      queue.enqueue(new ReceivedShare('c', []));
      let count: number = 0;
      queue.attach((share: ReceivedShare): void => {
        count++;
        if (count === 1) {
          throw new Error('handler exploded');
        }
      });
      // 三条都试过了：坏一条不能连带后面两条不交付。
      expect(count).assertEqual(3);
      expect(queue.enqueue(new ReceivedShare('d', []))).assertEqual('delivered');
      expect(count).assertEqual(4);
    });

    it('shareQueue_detach_stopsDeliveryAndAllowsReattach', 0, () => {
      const queue: ShareQueue = new ShareQueue();
      const first: string[] = [];
      queue.attach((share: ReceivedShare): void => {
        first.push(share.text);
      });
      queue.detach();
      expect(queue.isAttached()).assertFalse();

      // 卸下之后重新排队，等下一次 attach 补投（登出 → 再登录的路径）。
      expect(queue.enqueue(new ReceivedShare('later', []))).assertEqual('queued');
      const second: string[] = [];
      queue.attach((share: ReceivedShare): void => {
        second.push(share.text);
      });
      expect(second.join(',')).assertEqual('later');
      expect(first.length).assertEqual(0);
    });
  });
}
