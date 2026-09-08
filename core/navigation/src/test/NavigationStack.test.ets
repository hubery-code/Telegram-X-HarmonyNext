import { describe, it, expect } from '@ohos/hypium';
import { AppRoute, ChatRoute } from '../main/ets/Route';
import { defaultRegistry } from '../main/ets/RouteRegistry';
import { RouteCodec } from '../main/ets/RouteCodec';
import { NavigationStack } from '../main/ets/NavigationStack';
import type { AppError } from '@tgx/core-common';
import { mustOk, mustErr, paramField } from './TestSupport';

function codec(): RouteCodec {
  return new RouteCodec(defaultRegistry());
}

function peekName(stack: NavigationStack): string {
  const route: AppRoute | null = stack.peek();
  return route === null ? '' : route.name;
}

export default function navigationStackTest() {
  describe('NavigationStackTest', () => {
    it('pushPeekPop_lifoOrder', 0, () => {
      const stack: NavigationStack = new NavigationStack();
      expect(stack.getSize()).assertEqual(0);
      expect(stack.peek()).assertNull();
      expect(stack.pop()).assertNull();

      stack.push({ name: 'home' });
      stack.push({ name: 'chat', chatId: 1 });
      expect(stack.getSize()).assertEqual(2);
      expect(peekName(stack)).assertEqual('chat');

      const popped: AppRoute | null = stack.pop();
      expect(popped !== null && popped.name === 'chat').assertTrue();
      expect(stack.getSize()).assertEqual(1);
    });

    it('replace_replacesTop_emptyStackActsAsPush', 0, () => {
      const stack: NavigationStack = new NavigationStack();
      stack.push({ name: 'home' });
      stack.push({ name: 'chat', chatId: 1 });
      stack.replace({ name: 'chat', chatId: 2 });
      expect(stack.getSize()).assertEqual(2);
      const top: AppRoute | null = stack.peek();
      const chat: ChatRoute = top as ChatRoute;
      expect(chat.chatId).assertEqual(2);

      const empty: NavigationStack = new NavigationStack();
      empty.replace({ name: 'settings' });
      expect(empty.getSize()).assertEqual(1);
      expect(peekName(empty)).assertEqual('settings');
    });

    it('popToRoot_keepsFirstEntryOnly', 0, () => {
      const stack: NavigationStack = new NavigationStack();
      stack.push({ name: 'home' });
      stack.push({ name: 'chat', chatId: 1 });
      stack.push({ name: 'settings' });
      stack.popToRoot();
      expect(stack.getSize()).assertEqual(1);
      expect(peekName(stack)).assertEqual('home');
      stack.popToRoot();
      expect(stack.getSize()).assertEqual(1);
    });

    it('serializeRestore_roundTrip', 0, () => {
      const c: RouteCodec = codec();
      const stack: NavigationStack = new NavigationStack();
      stack.push({ name: 'home' });
      stack.push({ name: 'chat', chatId: -1001234567890, threadId: 3 });
      stack.push({ name: 'settingsSection', section: 'notifications' });
      const serialized: string = stack.serialize(c);

      const restored = mustOk(NavigationStack.restore(serialized, c));
      expect(restored.getSize()).assertEqual(3);
      const routes: AppRoute[] = restored.getRoutes();
      expect(JSON.stringify(routes)).assertEqual(JSON.stringify(stack.getRoutes()));
      // 再序列化应逐字节一致（序列化确定性）。
      expect(restored.serialize(c)).assertEqual(serialized);
    });

    it('restore_emptyString_yieldsEmptyStack', 0, () => {
      const restored = mustOk(NavigationStack.restore('', codec()));
      expect(restored.getSize()).assertEqual(0);
    });

    it('restore_dropsConsecutiveDuplicates', 0, () => {
      const c: RouteCodec = codec();
      const serialized: string = 'home\nchat/5\nchat/5\nsettings';
      const restored = mustOk(NavigationStack.restore(serialized, c));
      expect(restored.getSize()).assertEqual(3);
      const routes: AppRoute[] = restored.getRoutes();
      expect(routes[0].name).assertEqual('home');
      expect(routes[1].name).assertEqual('chat');
      expect(routes[2].name).assertEqual('settings');
    });

    it('restore_keepsNonConsecutiveDuplicates', 0, () => {
      const c: RouteCodec = codec();
      const restored = mustOk(NavigationStack.restore('chat/5\nsettings\nchat/5', c));
      expect(restored.getSize()).assertEqual(3);
    });

    it('restore_invalidEntry_rejected', 0, () => {
      const error: AppError = mustErr(NavigationStack.restore('home\nbogus/1', codec()));
      expect(error.kind).assertEqual('parameter');
      expect(paramField(error)).assertEqual('stack');
    });

    it('restore_invalidParamsInEntry_rejected', 0, () => {
      expect(NavigationStack.restore('chat/abc', codec()).isErr()).assertTrue();
    });
  });
}
