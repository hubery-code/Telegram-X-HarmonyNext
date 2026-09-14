import { describe, it, expect } from '@ohos/hypium';
import { EntryNavigationController } from '../../main/ets/navigation/EntryNavigationController';
import { AppRoute, ChatRoute, SearchRoute } from '@tgx/core-navigation';

export default function entryNavigationTest() {
  describe('EntryNavigationController', () => {

    it('initializes with default auth route', 0, () => {
      const controller = new EntryNavigationController();
      expect(controller.getSize()).assertEqual(1);
      expect(controller.getCurrentRoute().name).assertEqual('auth');
      expect(controller.hasRoute('auth')).assertTrue();
      expect(controller.hasRoute('home')).assertFalse();
    });

    it('custom initial route works', 0, () => {
      const controller = new EntryNavigationController({ name: 'home' });
      expect(controller.getSize()).assertEqual(1);
      expect(controller.getCurrentRoute().name).assertEqual('home');
    });

    it('navigateTo pushes routes and notifies listeners', 0, () => {
      const controller = new EntryNavigationController({ name: 'home' });
      let transitionCount: number = 0;
      let latestRoute: AppRoute | null = null;
      let prevRoute: AppRoute | null = null;

      controller.subscribe((curr: AppRoute, prev: AppRoute | null) => {
        transitionCount++;
        latestRoute = curr;
        prevRoute = prev;
      });

      const searchRoute: SearchRoute = { name: 'search', query: 'alice' };
      controller.navigateTo(searchRoute);

      expect(controller.getSize()).assertEqual(2);
      expect(controller.getCurrentRoute().name).assertEqual('search');
      expect(transitionCount).assertEqual(1);
      expect(latestRoute !== null && (latestRoute as AppRoute).name === 'search').assertTrue();
      expect(prevRoute !== null && (prevRoute as AppRoute).name === 'home').assertTrue();

      const chatRoute: ChatRoute = { name: 'chat', chatId: 1001 };
      controller.navigateTo(chatRoute);

      expect(controller.getSize()).assertEqual(3);
      expect(controller.getCurrentRoute().name).assertEqual('chat');
      expect(transitionCount).assertEqual(2);
      expect(latestRoute !== null && (latestRoute as AppRoute).name === 'chat').assertTrue();
      expect(prevRoute !== null && (prevRoute as AppRoute).name === 'search').assertTrue();
    });

    it('pop handles back stack correctly', 0, () => {
      const controller = new EntryNavigationController({ name: 'home' });
      controller.navigateTo({ name: 'search' });
      controller.navigateTo({ name: 'chat', chatId: 2002 });

      expect(controller.getSize()).assertEqual(3);

      // Back from chat -> search
      const popped1 = controller.pop();
      expect(popped1).assertTrue();
      expect(controller.getSize()).assertEqual(2);
      expect(controller.getCurrentRoute().name).assertEqual('search');

      // Back from search -> home
      const popped2 = controller.pop();
      expect(popped2).assertTrue();
      expect(controller.getSize()).assertEqual(1);
      expect(controller.getCurrentRoute().name).assertEqual('home');

      // Back from root home -> returns false, does not pop root
      const popped3 = controller.pop();
      expect(popped3).assertFalse();
      expect(controller.getSize()).assertEqual(1);
      expect(controller.getCurrentRoute().name).assertEqual('home');
    });

    it('replaceRoot resets navigation stack to single root', 0, () => {
      const controller = new EntryNavigationController({ name: 'home' });
      controller.navigateTo({ name: 'search' });
      controller.navigateTo({ name: 'chat', chatId: 3003 });

      expect(controller.getSize()).assertEqual(3);

      // Simulate logout: replaceRoot back to auth
      controller.replaceRoot({ name: 'auth' });
      expect(controller.getSize()).assertEqual(1);
      expect(controller.getCurrentRoute().name).assertEqual('auth');
      expect(controller.hasRoute('chat')).assertFalse();
      expect(controller.hasRoute('search')).assertFalse();
      expect(controller.hasRoute('home')).assertFalse();
      expect(controller.hasRoute('auth')).assertTrue();
    });

    it('popToRoot returns to first entry in stack', 0, () => {
      const controller = new EntryNavigationController({ name: 'home' });
      controller.navigateTo({ name: 'settings' });
      controller.navigateTo({ name: 'settingsSection', section: 'notifications' });

      expect(controller.getSize()).assertEqual(3);

      controller.popToRoot();
      expect(controller.getSize()).assertEqual(1);
      expect(controller.getCurrentRoute().name).assertEqual('home');
    });

    it('search to chat and back preserves search in stack', 0, () => {
      const controller = new EntryNavigationController({ name: 'home' });

      // 1. Open search with query
      controller.navigateTo({ name: 'search', query: 'tgx' });
      expect(controller.hasRoute('search')).assertTrue();

      // 2. Open chat from search
      controller.navigateTo({ name: 'chat', chatId: 4004 });
      expect(controller.hasRoute('search')).assertTrue();
      expect(controller.hasRoute('chat')).assertTrue();
      expect(controller.getCurrentRoute().name).assertEqual('chat');

      // 3. User navigates back
      controller.pop();
      expect(controller.getCurrentRoute().name).assertEqual('search');
      expect((controller.getCurrentRoute() as SearchRoute).query).assertEqual('tgx');
      expect(controller.hasRoute('chat')).assertFalse();
      expect(controller.hasRoute('search')).assertTrue();
    });

    it('handleDeepLink parses tg://chat and navigates', 0, () => {
      const controller = new EntryNavigationController({ name: 'home' });

      const result = controller.handleDeepLink('tg://chat?chatId=5005');
      expect(result.ok).assertTrue();
      expect(controller.getCurrentRoute().name).assertEqual('chat');
      expect((controller.getCurrentRoute() as ChatRoute).chatId).assertEqual(5005);
      expect(controller.getSize()).assertEqual(2);
    });

    it('handleDeepLink parses https://t.me/chat/{chatId} and navigates', 0, () => {
      const controller = new EntryNavigationController({ name: 'home' });

      const result = controller.handleDeepLink('https://t.me/chat/6006');
      expect(result.ok).assertTrue();
      expect(controller.getCurrentRoute().name).assertEqual('chat');
      expect((controller.getCurrentRoute() as ChatRoute).chatId).assertEqual(6006);
    });

    it('handleDeepLink rejects invalid URI and keeps current route', 0, () => {
      const controller = new EntryNavigationController({ name: 'home' });

      const result = controller.handleDeepLink('invalid://scheme');
      expect(result.ok).assertFalse();
      expect(controller.getCurrentRoute().name).assertEqual('home');
      expect(controller.getSize()).assertEqual(1);
    });

    it('serialize and restore preserves navigation stack state', 0, () => {
      const controller = new EntryNavigationController({ name: 'home' });
      controller.navigateTo({ name: 'search', query: 'secret' });
      controller.navigateTo({ name: 'chat', chatId: 7007 });

      const serialized = controller.serialize();
      expect(serialized.length > 0).assertTrue();

      // Restore into a fresh controller
      const freshController = new EntryNavigationController({ name: 'auth' });
      const restoreResult = freshController.restore(serialized);
      expect(restoreResult.ok).assertTrue();
      expect(freshController.getSize()).assertEqual(3);
      expect(freshController.getCurrentRoute().name).assertEqual('chat');
      expect((freshController.getCurrentRoute() as ChatRoute).chatId).assertEqual(7007);
    });

    it('restore fails cleanly on corrupted data', 0, () => {
      const controller = new EntryNavigationController({ name: 'home' });
      const restoreResult = controller.restore('malformed/invalid/path/data???');
      expect(restoreResult.ok).assertFalse();
      // Stack remains intact
      expect(controller.getSize()).assertEqual(1);
      expect(controller.getCurrentRoute().name).assertEqual('home');
    });

    it('unsubscribe removes listener', 0, () => {
      const controller = new EntryNavigationController({ name: 'home' });
      let callCount = 0;
      const unsub = controller.subscribe(() => {
        callCount++;
      });

      controller.navigateTo({ name: 'settings' });
      expect(callCount).assertEqual(1);

      unsub();
      controller.navigateTo({ name: 'search' });
      expect(callCount).assertEqual(1);
    });

  });
}
