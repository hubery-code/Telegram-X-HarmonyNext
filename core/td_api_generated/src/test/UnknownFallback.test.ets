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
import { jsonObj, toJson } from './TestJson';

function formattedTextJson(text: string): Record<string, TdJsonRaw> {
  const out = jsonObj();
  out['@type'] = 'formattedText';
  out['text'] = text;
  out['entities'] = [];
  return out;
}

export default function unknownFallbackTest() {
  describe('UnknownFallbackTest', () => {
    it('unknownTypeInUnion_fallsBackToUnknownObjectWithoutThrowing', 0, () => {
      const raw = jsonObj();
      raw['@type'] = 'messageFutureConstructor';
      raw['future_field'] = 42;
      const json: TdJsonRaw = toJson(raw);
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
      const raw = jsonObj();
      raw['@type'] = 'futureThing';
      raw['a'] = 1;
      raw['b'] = 'x';
      const json: TdJsonRaw = toJson(raw);
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
      const raw = jsonObj();
      raw['@type'] = 'updateFromTheFuture';
      raw['x'] = true;
      const decoded: TdObject | null = decodeTdObject(toJson(raw));
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
      const text = formattedTextJson('hi');
      text['future_entity_field'] = 1;
      const raw = jsonObj();
      raw['@type'] = 'messageText';
      raw['text'] = toJson(text);
      raw['link_preview'] = null;
      raw['link_preview_options'] = null;
      raw['brand_new_field'] = 7;
      const json: TdJsonRaw = toJson(raw);

      const decoded: MessageText | null = decodeMessageText(json);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded.text === null).assertFalse();
      if (decoded.text !== null) {
        expect(decoded.text.text).assertEqual('hi');
      }
      // Unknown fields are dropped on encode (documented forward-compat behavior).
      const encoded: TdJsonRaw = encodeMessageText(decoded);
      const roundTripped: MessageText | null = decodeMessageText(encoded);
      expect(roundTripped === null).assertFalse();
      if (roundTripped !== null) {
        expect(roundTripped.text === null).assertFalse();
      }
    });

    it('missingFields_getSchemaDefaultsWithoutThrowing', 0, () => {
      const raw = jsonObj();
      raw['@type'] = 'messageText';
      const decoded: MessageText | null = decodeMessageText(toJson(raw));
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded.type).assertEqual('messageText');
      expect(decoded.text === null).assertTrue();
    });

    it('unionEncode_unknownMember_roundTripsRaw', 0, () => {
      const raw = jsonObj();
      raw['@type'] = 'messageFutureConstructor';
      raw['future_field'] = 7;
      const json: TdJsonRaw = toJson(raw);
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
