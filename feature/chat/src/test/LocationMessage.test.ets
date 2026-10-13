/**
 * feature/chat — 位置与场所消息解析与视图模型单元测试（LOCATION-MSG-101）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  AccountScope,
  buildAccountDirectories,
  createDescriptor,
  AccountDirectoryLayout
} from '@tgx/core-account';
import { FakeAppFiles } from '@tgx/platform-ports';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEventSink
} from '@tgx/td-gateway';
import { Result, AppError } from '@tgx/core-common';
import {
  Message,
  MessageLocation,
  MessageVenue,
  Location,
  Venue,
  MessageText,
  FormattedText
} from '@tgx/core-td-api-generated';
import { LocationCard } from '../main/ets/model/LocationCard';
import { MessageItem } from '../main/ets/model/MessageItem';
import { ChatCoordinator, extractLocationCard } from '../main/ets/coordinator/ChatCoordinator';

class TestNativeBridge implements TdNativeBridgeLike {
  version: string = '1.8.67-test';
  readonly sent: string[] = [];
  private readonly sinks: Map<number, TdNativeEventSink> = new Map();
  private nextSubId: number = 1;

  getVersion(): string {
    return this.version;
  }

  createClient(): number {
    return 1;
  }

  send(clientId: number, requestUtf8: string): void {
    this.sent.push(requestUtf8);
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
}

function createScope(bridge: TestNativeBridge): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_location_msg');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_location_msg', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

function makeLocationMsg(id: number, lat: number, lon: number, accuracy: number = 0): Message {
  const m = new Message();
  m.id = id;
  m.chat_id = 42;
  m.date = 1700000000;
  m.is_outgoing = false;
  const content = new MessageLocation();
  content.type = 'messageLocation';
  const loc = new Location();
  loc.type = 'location';
  loc.latitude = lat;
  loc.longitude = lon;
  loc.horizontal_accuracy = accuracy;
  content.location = loc;
  m.content = content;
  return m;
}

function makeVenueMsg(id: number, lat: number, lon: number, title: string, address: string): Message {
  const m = new Message();
  m.id = id;
  m.chat_id = 42;
  m.date = 1700000000;
  m.is_outgoing = false;
  const content = new MessageVenue();
  content.type = 'messageVenue';
  const venue = new Venue();
  venue.type = 'venue';
  venue.title = title;
  venue.address = address;
  const loc = new Location();
  loc.type = 'location';
  loc.latitude = lat;
  loc.longitude = lon;
  loc.horizontal_accuracy = 8;
  venue.location = loc;
  content.venue = venue;
  m.content = content;
  return m;
}

export default function locationMessageTest(): void {
  describe('LocationMessageTest', () => {

    it('locationCard_constructorAndDefaults', 0, () => {
      const card = new LocationCard(39.9042, 116.4074);
      expect(card.latitude).assertEqual(39.9042);
      expect(card.longitude).assertEqual(116.4074);
      expect(card.horizontalAccuracy).assertEqual(0);
      expect(card.title).assertEqual('');
      expect(card.address).assertEqual('');
      expect(card.isVenue).assertFalse();

      const venueCard = new LocationCard(31.2304, 121.4737, 5, 'Oriental Pearl', 'Century Ave', true);
      expect(venueCard.latitude).assertEqual(31.2304);
      expect(venueCard.longitude).assertEqual(121.4737);
      expect(venueCard.horizontalAccuracy).assertEqual(5);
      expect(venueCard.title).assertEqual('Oriental Pearl');
      expect(venueCard.address).assertEqual('Century Ave');
      expect(venueCard.isVenue).assertTrue();
    });

    it('messageItem_locationDefaultAndWithLocation', 0, () => {
      const defaultItem = new MessageItem(1, 'Hello', 1000, false, 'Alice');
      expect(defaultItem.location).assertNull();

      const card = new LocationCard(39.9042, 116.4074, 10, 'Palace Museum', 'Jingshan Front St', true);
      const withLocItem = defaultItem.withLocation(card);
      expect(withLocItem.messageId).assertEqual(defaultItem.messageId);
      expect(withLocItem.text).assertEqual(defaultItem.text);
      expect(withLocItem.location !== null).assertTrue();
      expect(withLocItem.location!.latitude).assertEqual(39.9042);
      expect(withLocItem.location!.title).assertEqual('Palace Museum');
      expect(withLocItem.location!.isVenue).assertTrue();

      const clearedItem = withLocItem.withLocation(null);
      expect(clearedItem.location).assertNull();
    });

    it('extractLocationCard_handlesLocationContent', 0, () => {
      const content = new MessageLocation();
      content.type = 'messageLocation';
      const loc = new Location();
      loc.type = 'location';
      loc.latitude = 40.7128;
      loc.longitude = -74.0060;
      loc.horizontal_accuracy = 12;
      content.location = loc;

      const card = extractLocationCard(content);
      expect(card !== null).assertTrue();
      expect(card!.latitude).assertEqual(40.7128);
      expect(card!.longitude).assertEqual(-74.0060);
      expect(card!.horizontalAccuracy).assertEqual(12);
      expect(card!.title).assertEqual('');
      expect(card!.address).assertEqual('');
      expect(card!.isVenue).assertFalse();
    });

    it('extractLocationCard_handlesVenueContent', 0, () => {
      const content = new MessageVenue();
      content.type = 'messageVenue';
      const venue = new Venue();
      venue.type = 'venue';
      venue.title = 'Eiffel Tower';
      venue.address = 'Champ de Mars, Paris';
      const loc = new Location();
      loc.type = 'location';
      loc.latitude = 48.8584;
      loc.longitude = 2.2945;
      loc.horizontal_accuracy = 6;
      venue.location = loc;
      content.venue = venue;

      const card = extractLocationCard(content);
      expect(card !== null).assertTrue();
      expect(card!.latitude).assertEqual(48.8584);
      expect(card!.longitude).assertEqual(2.2945);
      expect(card!.horizontalAccuracy).assertEqual(6);
      expect(card!.title).assertEqual('Eiffel Tower');
      expect(card!.address).assertEqual('Champ de Mars, Paris');
      expect(card!.isVenue).assertTrue();
    });

    it('extractLocationCard_handlesNullAndOtherContentTypes', 0, () => {
      expect(extractLocationCard(null)).assertNull();

      const textContent = new MessageText();
      textContent.type = 'messageText';
      textContent.text = new FormattedText();
      textContent.text.text = 'Just text';
      expect(extractLocationCard(textContent)).assertNull();

      const emptyLoc = new MessageLocation();
      emptyLoc.type = 'messageLocation';
      emptyLoc.location = null;
      expect(extractLocationCard(emptyLoc)).assertNull();

      const emptyVenue = new MessageVenue();
      emptyVenue.type = 'messageVenue';
      emptyVenue.venue = null;
      expect(extractLocationCard(emptyVenue)).assertNull();
    });

    it('chatCoordinator_mapMessage_mapsLocationMessageToMessageItem', 0, () => {
      const bridge = new TestNativeBridge();
      const scope = createScope(bridge);
      const coordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const locMsg = makeLocationMsg(1001, 35.6762, 139.6503, 20);
      const item = coordinator.mapMessage(locMsg);

      expect(item.messageId).assertEqual(1001);
      expect(item.text).assertEqual('');
      expect(item.location !== null).assertTrue();
      expect(item.location!.latitude).assertEqual(35.6762);
      expect(item.location!.longitude).assertEqual(139.6503);
      expect(item.location!.horizontalAccuracy).assertEqual(20);
      expect(item.location!.isVenue).assertFalse();
    });

    it('chatCoordinator_mapMessage_mapsVenueMessageToMessageItem', 0, () => {
      const bridge = new TestNativeBridge();
      const scope = createScope(bridge);
      const coordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const venueMsg = makeVenueMsg(1002, 51.5007, -0.1246, 'Big Ben', 'Westminster, London');
      const item = coordinator.mapMessage(venueMsg);

      expect(item.messageId).assertEqual(1002);
      expect(item.text).assertEqual('');
      expect(item.location !== null).assertTrue();
      expect(item.location!.latitude).assertEqual(51.5007);
      expect(item.location!.longitude).assertEqual(-0.1246);
      expect(item.location!.title).assertEqual('Big Ben');
      expect(item.location!.address).assertEqual('Westminster, London');
      expect(item.location!.isVenue).assertTrue();
    });

  });
}
