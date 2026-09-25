/**
 * entry/src/test/deeplink/DeepLinkQueue.test.ets — 深链交接队列（DEEPLINK-101）。
 *
 * 这个类存在的唯一理由是时序：want 比页面早到。所以测的是「谁先谁后、丢不丢、
 * 会不会自喂」，而不是链接语义。
 */

import { describe, it, expect } from '@ohos/hypium';
import { DEEP_LINK_MAX_PENDING, DeepLinkEnqueueResult, DeepLinkQueue } from '../../main/ets/deeplink/DeepLinkQueue';

class Recorder {
  readonly uris: string[] = [];
  /** 命中的第 index 条抛异常，用来测「坏一条不连带后面几条」。 */
  throwAt: number = -1;

  handle: (uri: string) => void = (uri: string): void => {
    if (this.throwAt === this.uris.length) {
      this.uris.push(uri);
      throw new Error('handler exploded');
    }
    this.uris.push(uri);
  };
}

export default function deepLinkQueueTest() {
  describe('DeepLinkQueueTest', () => {
    it('enqueueBeforeAttach_isQueuedAndFlushedInOrder', 0, () => {
      const queue: DeepLinkQueue = new DeepLinkQueue();
      expect(queue.enqueue('https://t.me/a')).assertEqual('queued');
      expect(queue.enqueue('https://t.me/b')).assertEqual('queued');
      expect(queue.pendingCount()).assertEqual(2);

      const rec: Recorder = new Recorder();
      // 交付顺序必须与入队一致：用户点链接的先后是有意义的。
      expect(queue.attach(rec.handle)).assertEqual(2);
      expect(rec.uris.join(',')).assertEqual('https://t.me/a,https://t.me/b');
      expect(queue.pendingCount()).assertEqual(0);
      expect(queue.isAttached()).assertTrue();
    });

    it('enqueueAfterAttach_deliversImmediately', 0, () => {
      const queue: DeepLinkQueue = new DeepLinkQueue();
      const rec: Recorder = new Recorder();
      expect(queue.attach(rec.handle)).assertEqual(0);
      expect(queue.enqueue('https://t.me/c')).assertEqual('delivered');
      expect(rec.uris.join(',')).assertEqual('https://t.me/c');
      expect(queue.pendingCount()).assertEqual(0);
    });

    it('dedupe_appliesOnlyToUndeliveredBacklog', 0, () => {
      const queue: DeepLinkQueue = new DeepLinkQueue();
      // 没消费者时：同一条重复 want（onCreate + onNewWant 给同一个 uri）吞掉。
      expect(queue.enqueue('https://t.me/a')).assertEqual('queued');
      expect(queue.enqueue('  https://t.me/a  ')).assertEqual('duplicate');
      expect(queue.pendingCount()).assertEqual(1);

      const rec: Recorder = new Recorder();
      queue.attach(rec.handle);
      // 已交付过的链接再来一次是真想再去一趟，不该被吞。
      expect(queue.enqueue('https://t.me/a')).assertEqual('delivered');
      expect(rec.uris.length).assertEqual(2);
    });

    it('emptyAndBlankUri_rejected', 0, () => {
      const queue: DeepLinkQueue = new DeepLinkQueue();
      expect(queue.enqueue('')).assertEqual('empty');
      expect(queue.enqueue('   ')).assertEqual('empty');
      expect(queue.pendingCount()).assertEqual(0);
    });

    it('cap_dropsOldest', 0, () => {
      const queue: DeepLinkQueue = new DeepLinkQueue();
      for (let i = 0; i < DEEP_LINK_MAX_PENDING + 3; i++) {
        queue.enqueue(`https://t.me/u${i}`);
      }
      expect(queue.pendingCount()).assertEqual(DEEP_LINK_MAX_PENDING);
      // 丢的是最旧的三条，留下的是最后 8 条、顺序不变。
      const kept: string[] = queue.pendingUris();
      expect(kept[0]).assertEqual(`https://t.me/u3`);
      expect(kept[kept.length - 1]).assertEqual(`https://t.me/u${DEEP_LINK_MAX_PENDING + 2}`);
    });

    it('handlerThrow_doesNotStallBacklogOrDeliveries', 0, () => {
      const queue: DeepLinkQueue = new DeepLinkQueue();
      queue.enqueue('https://t.me/a');
      queue.enqueue('https://t.me/b');
      queue.enqueue('https://t.me/c');
      const rec: Recorder = new Recorder();
      rec.throwAt = 0; // 第一条抛
      expect(queue.attach(rec.handle)).assertEqual(3);
      // 三条都试过了：坏一条不能连带后面两条不交付。
      expect(rec.uris.length).assertEqual(3);

      const after: DeepLinkEnqueueResult = queue.enqueue('https://t.me/d');
      expect(after).assertEqual('delivered');
      expect(rec.uris.length).assertEqual(4);
    });

    it('detach_stopsDeliveryAndAllowsReattach', 0, () => {
      const queue: DeepLinkQueue = new DeepLinkQueue();
      const first: Recorder = new Recorder();
      queue.attach(first.handle);
      queue.detach();
      expect(queue.isAttached()).assertFalse();

      // 卸下之后重新排队，等下一次 attach 补投（登出 → 再登录的路径）。
      expect(queue.enqueue('https://t.me/e')).assertEqual('queued');
      const second: Recorder = new Recorder();
      expect(queue.attach(second.handle)).assertEqual(1);
      expect(second.uris.join(',')).assertEqual('https://t.me/e');
      expect(first.uris.length).assertEqual(0);
    });

    it('pendingUris_isACopy', 0, () => {
      const queue: DeepLinkQueue = new DeepLinkQueue();
      queue.enqueue('https://t.me/a');
      const snapshot: string[] = queue.pendingUris();
      snapshot.push('https://t.me/injected');
      expect(queue.pendingCount()).assertEqual(1);
      queue.clear();
      expect(queue.pendingCount()).assertEqual(0);
    });
  });
}
