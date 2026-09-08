import { describe, it, expect } from '@ohos/hypium';
import type { AppError } from '@tgx/core-common';
import type { Result } from '@tgx/core-common';
import { RouteDefinition, RouteName } from '../main/ets/Route';
import { RouteRegistry, defaultRegistry } from '../main/ets/RouteRegistry';

const CHAT_DEF: RouteDefinition = {
  name: 'chat',
  pathTemplate: 'chat/{chatId}',
  params: [
    { name: 'chatId', type: 'int', required: true },
    { name: 'threadId', type: 'int', required: true, min: 1 }
  ]
};

export default function routeRegistryTest() {
  describe('RouteRegistryTest', () => {
    it('register_thenFindByNameAndTemplate', 0, () => {
      const registry: RouteRegistry = new RouteRegistry();
      const result: Result<void, AppError> = registry.register(CHAT_DEF);
      expect(result.isOk()).assertTrue();
      const def: RouteDefinition | null = registry.find('chat');
      expect(def !== null && def.pathTemplate === 'chat/{chatId}').assertTrue();
      expect(registry.pathTemplateFor('chat')).assertEqual('chat/{chatId}');
      expect(registry.find('home')).assertNull();
    });

    it('register_duplicateName_rejected', 0, () => {
      const registry: RouteRegistry = new RouteRegistry();
      expect(registry.register(CHAT_DEF).isOk()).assertTrue();
      const again: Result<void, AppError> = registry.register(CHAT_DEF);
      expect(again.isErr()).assertTrue();
      expect(again.ok === false && again.error.kind === 'internal').assertTrue();
    });

    it('register_duplicateTemplate_rejected', 0, () => {
      const registry: RouteRegistry = new RouteRegistry();
      const other: RouteDefinition = {
        name: 'chatInfo',
        pathTemplate: 'chat/{chatId}',
        params: [{ name: 'chatId', type: 'int', required: true }]
      };
      expect(registry.register(CHAT_DEF).isOk()).assertTrue();
      expect(registry.register(other).isErr()).assertTrue();
    });

    it('register_placeholderMissingInSchema_rejected', 0, () => {
      const registry: RouteRegistry = new RouteRegistry();
      const bad: RouteDefinition = {
        name: 'chat',
        pathTemplate: 'chat/{chatId}',
        params: [{ name: 'other', type: 'int', required: true }]
      };
      const result: Result<void, AppError> = registry.register(bad);
      expect(result.isErr()).assertTrue();
      expect(result.ok === false && result.error.kind === 'parameter').assertTrue();
    });

    it('findByPath_matchesLiteralAndPlaceholderSegments', 0, () => {
      const registry: RouteRegistry = defaultRegistry();
      const chatDef: RouteDefinition | null = registry.findByPath('chat/123');
      expect(chatDef !== null && chatDef.name === 'chat').assertTrue();
      const mediaDef: RouteDefinition | null = registry.findByPath('mediaViewer/1/2');
      expect(mediaDef !== null && mediaDef.name === 'mediaViewer').assertTrue();
      expect(registry.findByPath('chat')).assertNull();
      expect(registry.findByPath('chat/1/2')).assertNull();
      expect(registry.findByPath('nope/1')).assertNull();
    });

    it('defaultRegistry_containsAllBuiltinRoutes', 0, () => {
      const registry: RouteRegistry = defaultRegistry();
      const names: RouteName[] = ['home', 'auth', 'chat', 'chatInfo', 'settings', 'settingsSection', 'search', 'mediaViewer'];
      for (let i: number = 0; i < names.length; i++) {
        const template: string | null = registry.pathTemplateFor(names[i]);
        expect(template !== null).assertTrue();
        expect(registry.find(names[i]) !== null).assertTrue();
      }
    });
  });
}
