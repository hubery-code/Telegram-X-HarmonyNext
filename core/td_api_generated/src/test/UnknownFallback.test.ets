import { describe, it, expect } from '@ohos/hypium';
import {
  TdJsonRaw,
  TdObject,
  TdMessageContent,
  TdUnknownObject,
  MessageText,
  decodeMessageText,
  encodeMessageText,
  decodeTdMessageContent,
  encodeTdMessageContent,
  decodeTdObject,
  encodeUnknownObject
} from '../main/ets/Index';

export default function unknownFallbackTest() {
  describe('UnknownFallbackTest', () => {
    it('unknownTypeInUnion_fallsBackToUnknownObjectWithoutThrowing', 0, () => {
      const json: TdJsonRaw = { '@type': 'messageFutureConstructor', 'future_field': 42 };
      const decoded: TdMessageContent | null = decodeTdMessageContent(json);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded instanceof TdUnknownObject).assertTrue();
      if (decoded instanceof TdUnknownObject) {
        expect(decoded.type).assertEqual('messageFutureConstructor');
        expect(decoded.raw['future_field']).assertEqual(42);
      }
    });

    it('unknownObject_reEncodePreservesRawJson', 0, () => {
      const json: TdJsonRaw = { '@type': 'futureThing', 'a': 1, 'b': 'x' };
      const decoded: TdObject | null = decodeTdObject(json);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded instanceof TdUnknownObject).assertTrue();
      if (decoded instanceof TdUnknownObject) {
        const encoded: TdJsonRaw = encodeUnknownObject(decoded);
        expect(JSON.stringify(encoded)).assertEqual(JSON.stringify(json));
      }
    });

    it('unknownTopLevelType_decodeTdObjectFallsBack', 0, () => {
      const decoded: TdObject | null = decodeTdObject({ '@type': 'updateFromTheFuture', 'x': true });
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded instanceof TdUnknownObject).assertTrue();
      if (decoded instanceof TdUnknownObject) {
        expect(decoded.type).assertEqual('updateFromTheFuture');
      }
    });

    it('unknownFieldsOnKnownConstructor_areIgnoredWithoutThrowing', 0, () => {
      const json: TdJsonRaw = {
        '@type': 'messageText',
        'text': { '@type': 'formattedText', 'text': 'hi', 'entities': [], 'future_entity_field': 1 },
        'link_preview': null,
        'link_preview_options': null,
        'brand_new_field': { 'nested': [1, 2, 3] }
      };
      const decoded: MessageText | null = decodeMessageText(json);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded.text === null).assertFalse();
      if (decoded.text !== null) {
        expect(decoded.text.text).assertEqual('hi');
      }
      // unknown fields are dropped on encode (documented forward-compat behavior)
      const encoded: TdJsonRaw = encodeMessageText(decoded);
      const roundTripped: MessageText | null = decodeMessageText(encoded);
      expect(roundTripped === null).assertFalse();
      if (roundTripped !== null) {
        expect(roundTripped.text === null).assertFalse();
      }
    });

    it('missingFields_getSchemaDefaultsWithoutThrowing', 0, () => {
      const decoded: MessageText | null = decodeMessageText({ '@type': 'messageText' });
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded.type).assertEqual('messageText');
      expect(decoded.text === null).assertTrue();
    });

    it('unionEncode_unknownMember_roundTripsRaw', 0, () => {
      const json: TdJsonRaw = { '@type': 'messageFutureConstructor', 'future_field': 7 };
      const decoded: TdMessageContent | null = decodeTdMessageContent(json);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      const encoded: TdJsonRaw = encodeTdMessageContent(decoded);
      expect(JSON.stringify(encoded)).assertEqual(JSON.stringify(json));
    });
  });
}
