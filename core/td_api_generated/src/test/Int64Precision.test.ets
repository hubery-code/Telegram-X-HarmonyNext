import { describe, it, expect } from '@ohos/hypium';
import {
  TdJsonRaw,
  UpdateInstalledStickerSets,
  decodeUpdateInstalledStickerSets,
  encodeUpdateInstalledStickerSets,
  EmojiStatusCustomEmojis,
  decodeEmojiStatusCustomEmojis,
  encodeEmojiStatusCustomEmojis,
  decodeMessage,
  encodeMessage
} from '../main/ets/Index';

const BIG_INT64: string = '9223372036854775807';
const BIG_CHAT_ID: string = '-1001234567890123456';

export default function int64PrecisionTest() {
  describe('Int64PrecisionTest', () => {
    it('int64Field_stringValueSurvivesRoundTripExactly', 0, () => {
      const json: TdJsonRaw = {
        '@type': 'message',
        'id': 1,
        'sender_id': null,
        'receiver_id': null,
        'chat_id': 1,
        'sending_state': null,
        'scheduling_state': null,
        'is_outgoing': false,
        'is_pinned': false,
        'is_from_offline': false,
        'can_be_saved': true,
        'has_timestamped_media': false,
        'is_channel_post': false,
        'is_paid_star_suggested_post': false,
        'is_paid_gram_suggested_post': false,
        'contains_unread_mention': false,
        'contains_unread_poll_votes': false,
        'date': 1,
        'edit_date': 0,
        'forward_info': null,
        'import_info': null,
        'interaction_info': null,
        'unread_reactions': [],
        'fact_check': null,
        'suggested_post_info': null,
        'reply_to': null,
        'topic_id': null,
        'self_destruct_type': null,
        'self_destruct_in': 0,
        'auto_delete_in': 0,
        'via_bot_user_id': 0,
        'guest_bot_caller_id': null,
        'sender_business_bot_user_id': 0,
        'sender_boost_count': 0,
        'sender_tag': '',
        'paid_message_star_count': 0,
        'author_signature': '',
        'media_album_id': BIG_INT64,
        'effect_id': '0',
        'restriction_info': null,
        'summary_language_code': '',
        'content': { '@type': 'messageUnsupported' },
        'ephemeral_content': null,
        'reply_markup': null,
        'ephemeral_message_id': 0,
        'chat_instance': BIG_CHAT_ID
      };
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
      const json: TdJsonRaw = {
        '@type': 'updateInstalledStickerSets',
        'sticker_type': { '@type': 'stickerTypeRegular' },
        'sticker_set_ids': [1, 1234567890123]
      };
      const decoded: UpdateInstalledStickerSets | null = decodeUpdateInstalledStickerSets(json);
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
