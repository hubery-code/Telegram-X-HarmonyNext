import { describe, it, expect } from '@ohos/hypium';
import {
  TdJsonRaw,
  TdFunction,
  TdObject,
  TdUser,
  TdMessage,
  TdOk,
  User,
  Message,
  Ok,
  SendMessage,
  GetMe,
  InputMessageText,
  encodeSendMessage,
  decodeSendMessage,
  decodeGetMe,
  decodeOk,
  TdResponseMap,
  decodeTdObject,
  TD_SCHEMA_HASH
} from '../main/ets/Index';

function responseMapTypeCheck(map: TdResponseMap | null): void {
  expect(map === null).assertTrue();
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
      const record = encoded as Record<string, TdJsonRaw>;
      expect(record['@type']).assertEqual('sendMessage');
      expect(record['chat_id']).assertEqual(123);
      const nested: TdJsonRaw = record['input_message_content'];
      expect(typeof nested === 'object' && nested !== null && !Array.isArray(nested)).assertTrue();
      if (typeof nested === 'object' && nested !== null && !Array.isArray(nested)) {
        expect(nested['@type']).assertEqual('inputMessageText');
      }
    });

    it('requestDecode_extraTagIsPreserved', 0, () => {
      const json: TdJsonRaw = {
        '@type': 'sendMessage',
        'chat_id': 1,
        'topic_id': null,
        'reply_to': null,
        'options': null,
        'reply_markup': null,
        'input_message_content': { '@type': 'inputMessageText', 'text': null, 'link_preview_options': null },
        '@extra': 'request-tag-42'
      };
      const decoded: SendMessage | null = decodeSendMessage(json);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded.extra).assertEqual('request-tag-42');
      const encoded: TdJsonRaw = encodeSendMessage(decoded);
      const record = encoded as Record<string, TdJsonRaw>;
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
      const decoded: GetMe | null = decodeGetMe({ '@type': 'getMe' });
      expect(decoded === null).assertFalse();
      if (decoded !== null) {
        expect(decoded.type).assertEqual('getMe');
      }
    });

    it('okResponse_decodesViaGenericEntryPoint', 0, () => {
      const decoded: TdObject | null = decodeTdObject({ '@type': 'ok', '@extra': 'tag-1' });
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded instanceof Ok).assertTrue();
      if (decoded instanceof Ok) {
        expect(decoded.extra).assertEqual('tag-1');
      }
      const direct: Ok | null = decodeOk({ '@type': 'ok' });
      expect(direct === null).assertFalse();
    });

    it('schemaHash_isExposed', 0, () => {
      expect(TD_SCHEMA_HASH.length).assertEqual(64);
    });
  });
}
