import { describe, it, expect } from '@ohos/hypium';
import {
  TdJsonRaw,
  EmojiStatusCustomEmojis,
  UpdateInstalledStickerSets,
  decodeEmojiStatusCustomEmojis,
  encodeEmojiStatusCustomEmojis,
  decodeUpdateInstalledStickerSets,
  decodeMessage,
  encodeMessage
} from '../main/ets/Index';
import { jsonObj, toJson } from './TestJson';

const BIG_INT64: string = '9223372036854775807';
const BIG_CHAT_ID: string = '-1001234567890123456';

function messageJsonWithInt64(): TdJsonRaw {
  const content = jsonObj();
  content['@type'] = 'messageUnsupported';
  const out = jsonObj();
  out['@type'] = 'message';
  out['id'] = 1;
  out['sender_id'] = null;
  out['receiver_id'] = null;
  out['chat_id'] = 1;
  out['sending_state'] = null;
  out['scheduling_state'] = null;
  out['is_outgoing'] = false;
  out['is_pinned'] = false;
  out['is_from_offline'] = false;
  out['can_be_saved'] = true;
  out['has_timestamped_media'] = false;
  out['is_channel_post'] = false;
  out['is_paid_star_suggested_post'] = false;
  out['is_paid_gram_suggested_post'] = false;
  out['contains_unread_mention'] = false;
  out['contains_unread_poll_votes'] = false;
  out['date'] = 1;
  out['edit_date'] = 0;
  out['forward_info'] = null;
  out['import_info'] = null;
  out['interaction_info'] = null;
  out['unread_reactions'] = [];
  out['fact_check'] = null;
  out['suggested_post_info'] = null;
  out['reply_to'] = null;
  out['topic_id'] = null;
  out['self_destruct_type'] = null;
  out['self_destruct_in'] = 0;
  out['auto_delete_in'] = 0;
  out['via_bot_user_id'] = 0;
  out['guest_bot_caller_id'] = null;
  out['sender_business_bot_user_id'] = 0;
  out['sender_boost_count'] = 0;
  out['sender_tag'] = '';
  out['paid_message_star_count'] = 0;
  out['author_signature'] = '';
  out['media_album_id'] = BIG_INT64;
  out['effect_id'] = '0';
  out['restriction_info'] = null;
  out['summary_language_code'] = '';
  out['content'] = toJson(content);
  out['ephemeral_content'] = null;
  out['reply_markup'] = null;
  out['ephemeral_message_id'] = 0;
  out['chat_instance'] = BIG_CHAT_ID;
  return toJson(out);
}

export default function int64PrecisionTest() {
  describe('Int64PrecisionTest', () => {
    it('int64Field_stringValueSurvivesRoundTripExactly', 0, () => {
      const json: TdJsonRaw = messageJsonWithInt64();
      const decoded = decodeMessage(json);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      // 2^63-1 and a large negative id are NOT exactly representable as
      // doubles; string typing must preserve them bit-exactly.
      expect(decoded.media_album_id).assertEqual(BIG_INT64);
      expect(decoded.chat_instance).assertEqual(BIG_CHAT_ID);
      const encoded: TdJsonRaw = encodeMessage(decoded);
      expect(JSON.stringify(encoded)).assertEqual(JSON.stringify(json));
      const decoded2 = decodeMessage(encoded);
      expect(decoded2 === null).assertFalse();
      if (decoded2 !== null) {
        expect(decoded2.media_album_id).assertEqual(BIG_INT64);
        expect(decoded2.chat_instance).assertEqual(BIG_CHAT_ID);
      }
    });

    it('int64Field_numberInputIsConvertedToString', 0, () => {
      // TDLib JSON may deliver small int64 values as JSON numbers.
      const stickerType = jsonObj();
      stickerType['@type'] = 'stickerTypeRegular';
      const out = jsonObj();
      out['@type'] = 'updateInstalledStickerSets';
      out['sticker_type'] = toJson(stickerType);
      out['sticker_set_ids'] = [1, 1234567890123];
      const decoded: UpdateInstalledStickerSets | null = decodeUpdateInstalledStickerSets(toJson(out));
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded.sticker_set_ids.length).assertEqual(2);
      expect(decoded.sticker_set_ids[0]).assertEqual('1');
      expect(decoded.sticker_set_ids[1]).assertEqual('1234567890123');
    });

    it('vectorInt64_stringValuesSurviveRoundTrip', 0, () => {
      const ids: string[] = ['1', '9007199254740993', '9223372036854775807'];
      const obj: EmojiStatusCustomEmojis = new EmojiStatusCustomEmojis();
      obj.custom_emoji_ids = ids;
      const encoded: TdJsonRaw = encodeEmojiStatusCustomEmojis(obj);
      const decoded: EmojiStatusCustomEmojis | null = decodeEmojiStatusCustomEmojis(encoded);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded.custom_emoji_ids.length).assertEqual(3);
      expect(decoded.custom_emoji_ids[1]).assertEqual('9007199254740993');
      expect(decoded.custom_emoji_ids[2]).assertEqual('9223372036854775807');
    });
  });
}
