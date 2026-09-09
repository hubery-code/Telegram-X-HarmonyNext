import { describe, it, expect } from '@ohos/hypium';
import {
  TdJsonRaw,
  TdFunction,
  TdObject,
  TdUser,
  TdMessage,
  TdOk,
  TdResponseMap,
  User,
  Message,
  Ok,
  GetMe,
  SendMessage,
  InputMessageText,
  encodeSendMessage,
  decodeSendMessage,
  decodeGetMe,
  decodeOk,
  decodeTdObject,
  TD_SCHEMA_HASH
} from '../main/ets/Index';
import { jsonObj, toJson } from './TestJson';

function responseMapTypeCheck(map: TdResponseMap | null): void {
  expect(map === null).assertTrue();
}

function inputMessageTextJson(): TdJsonRaw {
  const content = jsonObj();
  content['@type'] = 'inputMessageText';
  content['text'] = null;
  content['link_preview_options'] = null;
  return toJson(content);
}

export default function requestResponseTest() {
  describe('RequestResponseTest', () => {
    it('requestEncode_usesTdlibWireShape', 0, () => {
      const request: SendMessage = new SendMessage();
      request.chat_id = 123;
      request.topic_id = null;
      request.reply_to = null;
      request.options = null;
      request.reply_markup = null;
      const inputText: InputMessageText = new InputMessageText();
      inputText.text = null;
      inputText.link_preview_options = null;
      request.input_message_content = inputText;

      const encoded: TdJsonRaw = encodeSendMessage(request);
      const record: Record<string, TdJsonRaw> = encoded as Record<string, TdJsonRaw>;
      expect(record['@type']).assertEqual('sendMessage');
      expect(record['chat_id']).assertEqual(123);
      const nested: TdJsonRaw = record['input_message_content'];
      expect(typeof nested === 'object' && nested !== null && !Array.isArray(nested)).assertTrue();
      if (typeof nested === 'object' && nested !== null && !Array.isArray(nested)) {
        expect(nested['@type']).assertEqual('inputMessageText');
      }
    });

    it('requestDecode_extraTagIsPreserved', 0, () => {
      const raw = jsonObj();
      raw['@type'] = 'sendMessage';
      raw['chat_id'] = 1;
      raw['topic_id'] = null;
      raw['reply_to'] = null;
      raw['options'] = null;
      raw['reply_markup'] = null;
      raw['input_message_content'] = inputMessageTextJson();
      raw['@extra'] = 'request-tag-42';
      const decoded: SendMessage | null = decodeSendMessage(toJson(raw));
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded.extra).assertEqual('request-tag-42');
      const encoded: TdJsonRaw = encodeSendMessage(decoded);
      const record: Record<string, TdJsonRaw> = encoded as Record<string, TdJsonRaw>;
      expect(record['@extra']).assertEqual('request-tag-42');
    });

    it('responseMap_isWellFormedAndResultClassesExist', 0, () => {
      // Compile-time guarantee: the generated TdResponseMap interface
      // (request name -> result union) type-checks; runtime spot checks below.
      const user: TdUser = new User();
      expect(user instanceof User).assertTrue();
      const message: TdMessage = new Message();
      expect(message instanceof Message).assertTrue();
      const ok: TdOk = new Ok();
      expect(ok instanceof Ok).assertTrue();
      responseMapTypeCheck(null);
    });

    it('requestClasses_areMembersOfTdFunctionUnion', 0, () => {
      const getMe: GetMe = new GetMe();
      const asFunction: TdFunction = getMe;
      expect(asFunction.type).assertEqual('getMe');
      const raw = jsonObj();
      raw['@type'] = 'getMe';
      const decoded: GetMe | null = decodeGetMe(toJson(raw));
      expect(decoded === null).assertFalse();
      if (decoded !== null) {
        expect(decoded.type).assertEqual('getMe');
      }
    });

    it('okResponse_decodesViaGenericEntryPoint', 0, () => {
      const raw = jsonObj();
      raw['@type'] = 'ok';
      raw['@extra'] = 'tag-1';
      const decoded: TdObject | null = decodeTdObject(toJson(raw));
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded instanceof Ok).assertTrue();
      if (decoded instanceof Ok) {
        expect(decoded.extra).assertEqual('tag-1');
      }
      const okRaw = jsonObj();
      okRaw['@type'] = 'ok';
      const direct: Ok | null = decodeOk(toJson(okRaw));
      expect(direct === null).assertFalse();
    });

    it('schemaHash_isExposed', 0, () => {
      expect(TD_SCHEMA_HASH.length).assertEqual(64);
    });
  });
}
