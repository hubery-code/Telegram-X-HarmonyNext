/**
 * core/domain — GroupRegistry 单元测试（PROFILE-102）。
 *
 * 覆盖：
 * 1. 缓存存取与查询（BasicGroup, Supergroup, BasicGroupFullInfo, SupergroupFullInfo, ChatMember[]）；
 * 2. UpdateBasicGroup / UpdateBasicGroupFullInfo 事件响应与监听器通知；
 * 3. UpdateSupergroup / UpdateSupergroupFullInfo 事件响应与监听器通知；
 * 4. 监听器退订幂等性与 clear 清空行为；
 * 5. 展示辅助函数：formatMemberCount, getGroupAvatarLetters, formatMemberRole；
 * 6. request* TDLib 异步请求与回包反序列化集成。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  BasicGroup,
  BasicGroupFullInfo,
  Supergroup,
  SupergroupFullInfo,
  Usernames,
  ChatMember,
  ChatMemberStatusCreator,
  ChatMemberStatusAdministrator,
  ChatMemberStatusMember,
  ChatMembers,
  encodeBasicGroup,
  encodeBasicGroupFullInfo,
  encodeSupergroup,
  encodeSupergroupFullInfo,
  encodeChatMembers
} from '@tgx/core-td-api-generated';
import {
  AccountScope,
  buildAccountDirectories,
  createDescriptor,
  AccountDirectoryLayout
} from '@tgx/core-account';
import { FakeAppFiles, Subscription } from '@tgx/platform-ports';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEvent,
  TdNativeEventSink,
  TdPendingRequest,
  TdWireObject,
  TdWireValue
} from '@tgx/td-gateway';
import { Result, AppError } from '@tgx/core-common';
import {
  GroupRegistry,
  formatMemberCount,
  getGroupAvatarLetters,
  formatMemberRole
} from '../../main/ets/group/GroupRegistry';

interface SentBridgeRequest {
  readonly clientId: number;
  readonly utf8: string;
}

class TestNativeBridge implements TdNativeBridgeLike {
  version: string = '1.8.67-test';
  readonly sent: SentBridgeRequest[] = [];
  private readonly sinks: Map<number, TdNativeEventSink> = new Map();
  private nextSubId: number = 1;
  private nextSeq: number = 1;

  getVersion(): string {
    return this.version;
  }

  createClient(): number {
    return 1;
  }

  send(clientId: number, requestUtf8: string): void {
    const entry: SentBridgeRequest = { clientId: clientId, utf8: requestUtf8 };
    this.sent.push(entry);
  }

  execute(requestUtf8: string): string | null {
    return '{"@type":"ok"}';
  }

  subscribeUpdates(sink: TdNativeEventSink): number {
    const id: number = this.nextSubId;
    this.nextSubId += 1;
    this.sinks.set(id, sink);
    return id;
  }

  unsubscribe(subscriptionId: number): void {
    this.sinks.delete(subscriptionId);
  }

  getMetrics(): TdNativeBridgeMetrics {
    return {
      queueSize: 0,
      overflowWaitCount: 0,
      droppedCount: 0,
      eventsForwarded: 0,
      subscriptions: this.sinks.size,
      dispatcherRunning: true
    };
  }

  emitUpdate(clientId: number, type: string, fields: Record<string, TdWireValue>): void {
    const payload: TdWireObject = {};
    const keys: string[] = Object.keys(fields);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      payload[key] = fields[key];
    }
    payload['@type'] = type;
    const seq: string = String(this.nextSeq);
    this.nextSeq += 1;

    const rawEvent: TdNativeEvent = {
      schemaVersion: 1,
      clientId: clientId,
      sequence: seq,
      payloadUtf8: JSON.stringify(payload),
      receivedAtMonotonicMs: 0
    };

    const sinkKeys: number[] = Array.from(this.sinks.keys());
    for (let i = 0; i < sinkKeys.length; i++) {
      const sink: TdNativeEventSink | undefined = this.sinks.get(sinkKeys[i]);
      if (sink !== undefined) {
        sink(rawEvent);
      }
    }
  }

  emitResponse(clientId: number, requestId: string, fields: Record<string, TdWireValue>): void {
    const payload: TdWireObject = {};
    const keys: string[] = Object.keys(fields);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
      payload[key] = fields[key];
    }
    const extra: TdWireObject = {};
    extra['requestId'] = requestId;
    payload['@extra'] = extra;

    const rawEvent: TdNativeEvent = {
      schemaVersion: 1,
      clientId: clientId,
      sequence: '0',
      payloadUtf8: JSON.stringify(payload),
      receivedAtMonotonicMs: 0
    };

    const sinkKeys: number[] = Array.from(this.sinks.keys());
    for (let i = 0; i < sinkKeys.length; i++) {
      const sink: TdNativeEventSink | undefined = this.sinks.get(sinkKeys[i]);
      if (sink !== undefined) {
        sink(rawEvent);
      }
    }
  }

  lastSentJson(): Record<string, TdWireValue> {
    const last: SentBridgeRequest = this.sent[this.sent.length - 1];
    return JSON.parse(last.utf8) as Record<string, TdWireValue>;
  }
}

function createScope(bridge: TestNativeBridge): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_group_registry');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_group_registry', 'acct_grp_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

function createSampleBasicGroup(id: number, memberCount: number = 10): BasicGroup {
  const group: BasicGroup = new BasicGroup();
  group.id = id;
  group.member_count = memberCount;
  group.is_active = true;
  return group;
}

function createSampleBasicGroupFullInfo(description: string = 'Test group'): BasicGroupFullInfo {
  const info: BasicGroupFullInfo = new BasicGroupFullInfo();
  info.description = description;
  return info;
}

function createSampleSupergroup(id: number, username: string = 'testchannel', isChannel: boolean = true): Supergroup {
  const sg: Supergroup = new Supergroup();
  sg.id = id;
  if (username.length > 0) {
    const un: Usernames = new Usernames();
    un.editable_username = username;
    un.active_usernames = [username];
    sg.usernames = un;
  }
  sg.is_channel = isChannel;
  sg.member_count = 100;
  return sg;
}

function createSampleSupergroupFullInfo(description: string = 'Supergroup info'): SupergroupFullInfo {
  const info: SupergroupFullInfo = new SupergroupFullInfo();
  info.description = description;
  info.member_count = 100;
  return info;
}

export default function groupRegistryTest(): void {
  describe('GroupRegistry', (): void => {

    it('should store and retrieve BasicGroup in cache', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: GroupRegistry = new GroupRegistry(scope);

      expect(registry.getBasicGroup(101)).assertNull();

      const bg: BasicGroup = createSampleBasicGroup(101, 25);
      registry.putBasicGroup(bg);

      const cached: BasicGroup | null = registry.getBasicGroup(101);
      expect(cached !== null).assertTrue();
      if (cached !== null) {
        expect(cached.id).assertEqual(101);
        expect(cached.member_count).assertEqual(25);
      }

      registry.stop();
    });

    it('should store and retrieve Supergroup in cache', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: GroupRegistry = new GroupRegistry(scope);

      expect(registry.getSupergroup(202)).assertNull();

      const sg: Supergroup = createSampleSupergroup(202, 'tgxchannel', true);
      registry.putSupergroup(sg);

      const cached: Supergroup | null = registry.getSupergroup(202);
      expect(cached !== null).assertTrue();
      if (cached !== null) {
        expect(cached.id).assertEqual(202);
        expect(cached.usernames !== null).assertTrue();
        if (cached.usernames !== null) {
          expect(cached.usernames.editable_username).assertEqual('tgxchannel');
        }
        expect(cached.is_channel).assertTrue();
      }

      registry.stop();
    });

    it('should store BasicGroupFullInfo and notify subscribers', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: GroupRegistry = new GroupRegistry(scope);

      let notifiedCount: number = 0;
      let notifiedDesc: string = '';
      const sub: Subscription = registry.subscribeBasicGroupFullInfo(303, (info: BasicGroupFullInfo): void => {
        notifiedCount += 1;
        notifiedDesc = info.description;
      });

      expect(sub.isActive).assertTrue();

      const info: BasicGroupFullInfo = createSampleBasicGroupFullInfo('Welcome to basic group');
      registry.putBasicGroupFullInfo(303, info);

      expect(notifiedCount).assertEqual(1);
      expect(notifiedDesc).assertEqual('Welcome to basic group');
      expect(registry.getBasicGroupFullInfo(303) !== null).assertTrue();

      sub.unsubscribe();
      expect(sub.isActive).assertFalse();

      registry.putBasicGroupFullInfo(303, createSampleBasicGroupFullInfo('Updated desc'));
      expect(notifiedCount).assertEqual(1);

      registry.stop();
    });

    it('should store SupergroupFullInfo and notify subscribers', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: GroupRegistry = new GroupRegistry(scope);

      let notifiedCount: number = 0;
      const sub: Subscription = registry.subscribeSupergroupFullInfo(404, (_info: SupergroupFullInfo): void => {
        notifiedCount += 1;
      });

      const info: SupergroupFullInfo = createSampleSupergroupFullInfo('Channel announcement');
      registry.putSupergroupFullInfo(404, info);

      expect(notifiedCount).assertEqual(1);
      expect(registry.getSupergroupFullInfo(404) !== null).assertTrue();

      sub.unsubscribe();
      registry.stop();
    });

    it('should store and retrieve SupergroupMembers', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: GroupRegistry = new GroupRegistry(scope);

      expect(registry.getSupergroupMembers(505)).assertNull();

      const member1: ChatMember = new ChatMember();
      member1.tag = 'Lead';
      const member2: ChatMember = new ChatMember();
      member2.tag = 'Member';

      const members: ChatMember[] = [member1, member2];
      registry.putSupergroupMembers(505, members);

      const cached: ChatMember[] | null = registry.getSupergroupMembers(505);
      expect(cached !== null).assertTrue();
      if (cached !== null) {
        expect(cached.length).assertEqual(2);
        expect(cached[0].tag).assertEqual('Lead');
      }

      registry.stop();
    });

    it('should handle updateBasicGroup and updateBasicGroupFullInfo from Gateway', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: GroupRegistry = new GroupRegistry(scope);

      const bg: BasicGroup = createSampleBasicGroup(601, 15);
      const bgFields: Record<string, TdWireValue> = {};
      bgFields['basic_group'] = encodeBasicGroup(bg) as TdWireObject;
      bridge.emitUpdate(scope.clientId, 'updateBasicGroup', bgFields);

      const cachedBg: BasicGroup | null = registry.getBasicGroup(601);
      expect(cachedBg !== null).assertTrue();
      if (cachedBg !== null) {
        expect(cachedBg.member_count).assertEqual(15);
      }

      const fullInfo: BasicGroupFullInfo = createSampleBasicGroupFullInfo('Gateway full info');
      const infoFields: Record<string, TdWireValue> = {};
      infoFields['basic_group_id'] = 601;
      infoFields['basic_group_full_info'] = encodeBasicGroupFullInfo(fullInfo) as TdWireObject;
      bridge.emitUpdate(scope.clientId, 'updateBasicGroupFullInfo', infoFields);

      const cachedInfo: BasicGroupFullInfo | null = registry.getBasicGroupFullInfo(601);
      expect(cachedInfo !== null).assertTrue();
      if (cachedInfo !== null) {
        expect(cachedInfo.description).assertEqual('Gateway full info');
      }

      registry.stop();
    });

    it('should handle updateSupergroup and updateSupergroupFullInfo from Gateway', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: GroupRegistry = new GroupRegistry(scope);

      const sg: Supergroup = createSampleSupergroup(701, 'gwchannel', true);
      const sgFields: Record<string, TdWireValue> = {};
      sgFields['supergroup'] = encodeSupergroup(sg) as TdWireObject;
      bridge.emitUpdate(scope.clientId, 'updateSupergroup', sgFields);

      const cachedSg: Supergroup | null = registry.getSupergroup(701);
      expect(cachedSg !== null).assertTrue();
      if (cachedSg !== null) {
        expect(cachedSg.usernames !== null).assertTrue();
        if (cachedSg.usernames !== null) {
          expect(cachedSg.usernames.editable_username).assertEqual('gwchannel');
        }
      }

      const fullInfo: SupergroupFullInfo = createSampleSupergroupFullInfo('SG Gateway full info');
      const infoFields: Record<string, TdWireValue> = {};
      infoFields['supergroup_id'] = 701;
      infoFields['supergroup_full_info'] = encodeSupergroupFullInfo(fullInfo) as TdWireObject;
      bridge.emitUpdate(scope.clientId, 'updateSupergroupFullInfo', infoFields);

      const cachedInfo: SupergroupFullInfo | null = registry.getSupergroupFullInfo(701);
      expect(cachedInfo !== null).assertTrue();
      if (cachedInfo !== null) {
        expect(cachedInfo.description).assertEqual('SG Gateway full info');
      }

      registry.stop();
    });

    it('should clear all caches on clear', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: GroupRegistry = new GroupRegistry(scope);

      registry.putBasicGroup(createSampleBasicGroup(801));
      registry.putSupergroup(createSampleSupergroup(802));
      expect(registry.getBasicGroup(801) !== null).assertTrue();
      expect(registry.getSupergroup(802) !== null).assertTrue();

      registry.clear();

      expect(registry.getBasicGroup(801)).assertNull();
      expect(registry.getSupergroup(802)).assertNull();

      registry.stop();
    });

    it('should correctly format member counts for groups and channels', 0, (): void => {
      expect(formatMemberCount(1, false)).assertEqual('1 member');
      expect(formatMemberCount(5, false)).assertEqual('5 members');
      expect(formatMemberCount(1, true)).assertEqual('1 subscriber');
      expect(formatMemberCount(100, true)).assertEqual('100 subscribers');
    });

    it('should correctly extract avatar letters from titles', 0, (): void => {
      expect(getGroupAvatarLetters('')).assertEqual('');
      expect(getGroupAvatarLetters('Design')).assertEqual('D');
      expect(getGroupAvatarLetters('Tech News')).assertEqual('TN');
      expect(getGroupAvatarLetters('Alpha Beta Gamma')).assertEqual('AB');
    });

    it('should correctly format member role from status and tag', 0, (): void => {
      const member1: ChatMember = new ChatMember();
      member1.tag = 'Founder';
      expect(formatMemberRole(member1)).assertEqual('Founder');

      const member2: ChatMember = new ChatMember();
      member2.status = new ChatMemberStatusCreator();
      expect(formatMemberRole(member2)).assertEqual('Owner');

      const member3: ChatMember = new ChatMember();
      member3.status = new ChatMemberStatusAdministrator();
      expect(formatMemberRole(member3)).assertEqual('Admin');

      const member4: ChatMember = new ChatMember();
      member4.status = new ChatMemberStatusMember();
      expect(formatMemberRole(member4)).assertEqual('');
    });

    it('should assemble requestBasicGroup and resolve with cached BasicGroup', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: GroupRegistry = new GroupRegistry(scope);

      const res: Result<TdPendingRequest, AppError> = registry.requestBasicGroup(901);
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('getBasicGroup');
      expect(sent['basic_group_id']).assertEqual(901);

      if (res.ok) {
        const bg: BasicGroup = createSampleBasicGroup(901, 42);
        bridge.emitResponse(scope.clientId, res.value.requestId, encodeBasicGroup(bg) as Record<string, TdWireValue>);

        await res.value.promise;

        const cached: BasicGroup | null = registry.getBasicGroup(901);
        expect(cached !== null).assertTrue();
        if (cached !== null) {
          expect(cached.member_count).assertEqual(42);
        }
      }

      registry.stop();
    });

    it('should assemble requestSupergroup and resolve with cached Supergroup', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: GroupRegistry = new GroupRegistry(scope);

      const res: Result<TdPendingRequest, AppError> = registry.requestSupergroup(1001);
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('getSupergroup');
      expect(sent['supergroup_id']).assertEqual(1001);

      if (res.ok) {
        const sg: Supergroup = createSampleSupergroup(1001, 'fastchannel', true);
        bridge.emitResponse(scope.clientId, res.value.requestId, encodeSupergroup(sg) as Record<string, TdWireValue>);

        await res.value.promise;

        const cached: Supergroup | null = registry.getSupergroup(1001);
        expect(cached !== null).assertTrue();
        if (cached !== null) {
          expect(cached.usernames !== null).assertTrue();
          if (cached.usernames !== null) {
            expect(cached.usernames.editable_username).assertEqual('fastchannel');
          }
        }
      }

      registry.stop();
    });

    it('should assemble requestSupergroupMembers and cache member list', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: GroupRegistry = new GroupRegistry(scope);

      const res: Result<TdPendingRequest, AppError> = registry.requestSupergroupMembers(1101, 0, 10);
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('getSupergroupMembers');
      expect(sent['supergroup_id']).assertEqual(1101);

      if (res.ok) {
        const chatMembers: ChatMembers = new ChatMembers();
        chatMembers.total_count = 1;
        const m: ChatMember = new ChatMember();
        m.tag = 'VIP';
        chatMembers.members = [m];

        bridge.emitResponse(scope.clientId, res.value.requestId, encodeChatMembers(chatMembers) as Record<string, TdWireValue>);

        await res.value.promise;

        const cached: ChatMember[] | null = registry.getSupergroupMembers(1101);
        expect(cached !== null).assertTrue();
        if (cached !== null) {
          expect(cached.length).assertEqual(1);
          expect(cached[0].tag).assertEqual('VIP');
        }
      }

      registry.stop();
    });

  });
}
