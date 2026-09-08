import { describe, it, expect } from '@ohos/hypium';
import {
  TdJsonRaw,
  FormattedText,
  MessageText,
  decodeMessageText,
  encodeMessageText,
  decodeMessage,
  encodeMessage,
  decodeUpdateNewMessage,
  decodeTdMessageContent,
  UnreadReaction,
  ReactionType,
  ReactionTypeEmoji,
  decodeReactionType
} from '../main/ets/Index';

function normalize(value: TdJsonRaw): string {
  return JSON.stringify(value);
}

export default function codecRoundTripTest() {
  describe('CodecRoundTripTest', () => {
    it('messageText_decodeEncodeRoundTrip', 0, () => {
      const json: TdJsonRaw = {
        '@type': 'messageText',
        'text': { '@type': 'formattedText', 'text': 'hello', 'entities': [] },
        'link_preview': null,
        'link_preview_options': null
      };
      const decoded: MessageText | null = decodeMessageText(json);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded.type).assertEqual('messageText');
      expect(decoded.text === null).assertFalse();
      const text: FormattedText | null = decoded.text;
      if (text === null) {
        return;
      }
      expect(text.text).assertEqual('hello');
      const encoded: TdJsonRaw = encodeMessageText(decoded);
      expect(normalize(encoded)).assertEqual(normalize(json));
    });

    it('message_fullObjectRoundTripWithUnionsAndVectors', 0, () => {
      const json: TdJsonRaw = {
        '@type': 'message',
        'id': 12345678901234,
        'sender_id': { '@type': 'messageSenderUser', 'user_id': 42 },
        'receiver_id': null,
        'chat_id': 777,
        'sending_state': null,
        'scheduling_state': null,
        'is_outgoing': true,
        'is_pinned': false,
        'is_from_offline': false,
        'can_be_saved': true,
        'has_timestamped_media': false,
        'is_channel_post': false,
        'is_paid_star_suggested_post': false,
        'is_paid_gram_suggested_post': false,
        'contains_unread_mention': false,
        'contains_unread_poll_votes': false,
        'date': 1725734400,
        'edit_date': 0,
        'forward_info': null,
        'import_info': null,
        'interaction_info': null,
        'unread_reactions': [
          { '@type': 'unreadReaction', 'type': { '@type': 'reactionTypeEmoji', 'emoji': '👍' }, 'sender_id': { '@type': 'messageSenderUser', 'user_id': 7 }, 'is_big': false }
        ],
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
        'media_album_id': '9223372036854775807',
        'effect_id': '0',
        'restriction_info': null,
        'summary_language_code': '',
        'content': { '@type': 'messageText', 'text': { '@type': 'formattedText', 'text': 'hi', 'entities': [] }, 'link_preview': null, 'link_preview_options': null },
        'ephemeral_content': null,
        'reply_markup': null,
        'ephemeral_message_id': 0,
        'chat_instance': '-10012345678901234'
      };
      const decoded = decodeMessage(json);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded.id).assertEqual(12345678901234);
      expect(decoded.media_album_id).assertEqual('9223372036854775807');
      expect(decoded.chat_instance).assertEqual('-10012345678901234');
      // union member access through the discriminant
      if (decoded.content !== null && decoded.content.type === 'messageText') {
        expect(decoded.content.text === null).assertFalse();
      } else {
        expect(false).assertTrue();
      }
      expect(decoded.unread_reactions.length).assertEqual(1);
      const reaction: UnreadReaction = decoded.unread_reactions[0];
      const reactionType: ReactionType | null = reaction.type;
      expect(reactionType !== null && reactionType.type === 'reactionTypeEmoji').assertTrue();
      if (reactionType !== null && reactionType instanceof ReactionTypeEmoji) {
        expect(reactionType.emoji).assertEqual('👍');
      }
      const encoded: TdJsonRaw = encodeMessage(decoded);
      expect(normalize(encoded)).assertEqual(normalize(json));
    });

    it('updateNewMessage_unionEntryPointRoundTrip', 0, () => {
      const json: TdJsonRaw = {
        '@type': 'updateNewMessage',
        'message': {
          '@type': 'message',
          'id': 1,
          'sender_id': null,
          'receiver_id': null,
          'chat_id': 55,
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
          'media_album_id': '0',
          'effect_id': '0',
          'restriction_info': null,
          'summary_language_code': '',
          'content': { '@type': 'messageUnsupported' },
          'ephemeral_content': null,
          'reply_markup': null,
          'ephemeral_message_id': 0,
          'chat_instance': '0'
        }
      };
      const decoded = decodeUpdateNewMessage(json);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded.message.chat_id).assertEqual(55);
      expect(decoded.message.content !== null && decoded.message.content.type === 'messageUnsupported').assertTrue();
    });

    it('unionDecoder_dispatchesKnownConstructor', 0, () => {
      const decoded: ReactionType | null = decodeReactionType({ '@type': 'reactionTypeEmoji', 'emoji': '🔥' });
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded instanceof ReactionTypeEmoji).assertTrue();
      if (decoded instanceof ReactionTypeEmoji) {
        expect(decoded.emoji).assertEqual('🔥');
      }
    });

    it('unionDecoder_nullInputReturnsNull', 0, () => {
      const decoded: ReactionType | null = decodeReactionType(null);
      expect(decoded === null).assertTrue();
      const direct: MessageText | null = decodeMessageText(null);
      expect(direct === null).assertTrue();
      void decodeTdMessageContent;
    });
  });
}
