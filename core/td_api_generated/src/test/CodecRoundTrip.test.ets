import { describe, it, expect } from '@ohos/hypium';
import {
  TdJsonRaw,
  TdReactionType,
  FormattedText,
  MessageText,
  MessageUnsupported,
  ReactionTypeEmoji,
  UnreadReaction,
  decodeMessageText,
  encodeMessageText,
  decodeMessage,
  encodeMessage,
  decodeUpdateNewMessage,
  decodeTdMessageContent,
  decodeTdReactionType
} from '../main/ets/Index';
import { jsonObj, toJson } from './TestJson';

function normalize(value: TdJsonRaw): string {
  return JSON.stringify(value);
}

function formattedTextJson(text: string): TdJsonRaw {
  const out = jsonObj();
  out['@type'] = 'formattedText';
  out['text'] = text;
  out['entities'] = [];
  return toJson(out);
}

function messageTextJson(text: string): TdJsonRaw {
  const out = jsonObj();
  out['@type'] = 'messageText';
  out['text'] = formattedTextJson(text);
  out['link_preview'] = null;
  out['link_preview_options'] = null;
  return toJson(out);
}

function messageSenderUserJson(userId: number): TdJsonRaw {
  const out = jsonObj();
  out['@type'] = 'messageSenderUser';
  out['user_id'] = userId;
  return toJson(out);
}

function fullMessageJson(id: number, chatId: number, content: TdJsonRaw): Record<string, TdJsonRaw> {
  const out = jsonObj();
  out['@type'] = 'message';
  out['id'] = id;
  out['sender_id'] = messageSenderUserJson(42);
  out['receiver_id'] = null;
  out['chat_id'] = chatId;
  out['sending_state'] = null;
  out['scheduling_state'] = null;
  out['is_outgoing'] = true;
  out['is_pinned'] = false;
  out['is_from_offline'] = false;
  out['can_be_saved'] = true;
  out['has_timestamped_media'] = false;
  out['is_channel_post'] = false;
  out['is_paid_star_suggested_post'] = false;
  out['is_paid_gram_suggested_post'] = false;
  out['contains_unread_mention'] = false;
  out['contains_unread_poll_votes'] = false;
  out['date'] = 1725734400;
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
  out['media_album_id'] = '9223372036854775807';
  out['effect_id'] = '0';
  out['restriction_info'] = null;
  out['summary_language_code'] = '';
  out['content'] = content;
  out['ephemeral_content'] = null;
  out['reply_markup'] = null;
  out['ephemeral_message_id'] = 0;
  out['chat_instance'] = '-10012345678901234';
  return out;
}

export default function codecRoundTripTest() {
  describe('CodecRoundTripTest', () => {
    it('messageText_decodeEncodeRoundTrip', 0, () => {
      const json: TdJsonRaw = messageTextJson('hello');
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
      const reactionType = jsonObj();
      reactionType['@type'] = 'reactionTypeEmoji';
      reactionType['emoji'] = '👍';
      const reaction = jsonObj();
      reaction['@type'] = 'unreadReaction';
      reaction['type'] = toJson(reactionType);
      reaction['sender_id'] = messageSenderUserJson(7);
      reaction['is_big'] = false;
      const reactions: TdJsonRaw[] = [];
      reactions.push(toJson(reaction));

      const message = fullMessageJson(12345678901234, 777, messageTextJson('hi'));
      message['unread_reactions'] = reactions;

      const json: TdJsonRaw = toJson(message);
      const decoded = decodeMessage(json);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      expect(decoded.id).assertEqual(12345678901234);
      expect(decoded.media_album_id).assertEqual('9223372036854775807');
      expect(decoded.chat_instance).assertEqual('-10012345678901234');
      // Union member access via instanceof (ArkTS does not narrow on the
      // discriminant property inside conditionals).
      if (decoded.content !== null && decoded.content instanceof MessageText) {
        expect(decoded.content.text === null).assertFalse();
      } else {
        expect(false).assertTrue();
      }
      expect(decoded.unread_reactions.length).assertEqual(1);
      const unread: UnreadReaction = decoded.unread_reactions[0];
      const reactionTypeDecoded: TdReactionType | null = unread.type_;
      expect(reactionTypeDecoded !== null && reactionTypeDecoded instanceof ReactionTypeEmoji).assertTrue();
      if (reactionTypeDecoded !== null && reactionTypeDecoded instanceof ReactionTypeEmoji) {
        expect(reactionTypeDecoded.emoji).assertEqual('👍');
      }
      const encoded: TdJsonRaw = encodeMessage(decoded);
      expect(normalize(encoded)).assertEqual(normalize(json));
    });

    it('updateNewMessage_unionEntryPointRoundTrip', 0, () => {
      const unsupported = jsonObj();
      unsupported['@type'] = 'messageUnsupported';
      const message = fullMessageJson(1, 55, toJson(unsupported));
      message['is_outgoing'] = false;
      const update = jsonObj();
      update['@type'] = 'updateNewMessage';
      update['message'] = toJson(message);
      const json: TdJsonRaw = toJson(update);

      const decoded = decodeUpdateNewMessage(json);
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      const msg = decoded.message;
      expect(msg === null).assertFalse();
      if (msg === null) {
        return;
      }
      expect(msg.chat_id).assertEqual(55);
      expect(msg.content !== null && msg.content instanceof MessageUnsupported).assertTrue();
    });

    it('unionDecoder_dispatchesKnownConstructor', 0, () => {
      const emoji = jsonObj();
      emoji['@type'] = 'reactionTypeEmoji';
      emoji['emoji'] = '🔥';
      const decoded: TdReactionType | null = decodeTdReactionType(toJson(emoji));
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
      const decoded: TdReactionType | null = decodeTdReactionType(null);
      expect(decoded === null).assertTrue();
      const direct: MessageText | null = decodeMessageText(null);
      expect(direct === null).assertTrue();
      void decodeTdMessageContent;
    });
  });
}
