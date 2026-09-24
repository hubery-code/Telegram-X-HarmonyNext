/**
 * core/domain — 会话发言权模型单元测试（CHAN-SEND-2）。
 *
 * 守住的回归：
 * 1. permissions 缺失必须当成「全放开」——读不到权限不等于没权限，否则用户被锁在输入栏外；
 * 2. 九位映射按位置传参，翻错一位就会「图片能发、视频不能发」这类查不出来的错，
 *    所以逐位单独点亮做映射断言；
 * 3. 附件面板各项可用性只由对应那一位决定，不可用项仍要出现在列表里（点了出提示，不是入口消失）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ChatPermissions } from '@tgx/core-td-api-generated';
import {
  AttachmentEntry,
  ATTACHMENT_FILE,
  ATTACHMENT_GALLERY,
  ATTACHMENT_POLL,
  ATTACHMENT_VIDEO,
  attachmentRestrictionLabel,
  buildAttachmentEntries,
  canRecordVoice,
  canSendAnyMedia,
  ChatSendRights,
  sendRightsFromPermissions
} from '../../main/ets/chat/ChatSendRights';

/** 全 false 的 TDLib permissions；调用方再点亮自己要验证的那一位。 */
function emptyPermissions(): ChatPermissions {
  return new ChatPermissions();
}

export default function chatSendRightsTest(): void {
  describe('ChatSendRightsTest', () => {

    it('missingPermissionsMeansUnrestricted', 0, () => {
      const rights: ChatSendRights = sendRightsFromPermissions(null);
      expect(rights.basic).assertTrue();
      expect(rights.polls).assertTrue();
      expect(canSendAnyMedia(rights)).assertTrue();
      expect(canRecordVoice(rights)).assertTrue();
    });

    it('mapsEachPermissionBitToItsOwnRight', 0, () => {
      // 逐位点亮：任何一次位置传参写反都会在这里暴露（九参构造最容易串位）。
      const flags: string[] = [
        'can_send_basic_messages',
        'can_send_audios',
        'can_send_documents',
        'can_send_photos',
        'can_send_videos',
        'can_send_video_notes',
        'can_send_voice_notes',
        'can_send_polls',
        'can_send_other_messages'
      ];
      const expected: boolean[][] = [];
      for (let i = 0; i < flags.length; i++) {
        const permissions: ChatPermissions = emptyPermissions();
        if (i === 0) {
          permissions.can_send_basic_messages = true;
        } else if (i === 1) {
          permissions.can_send_audios = true;
        } else if (i === 2) {
          permissions.can_send_documents = true;
        } else if (i === 3) {
          permissions.can_send_photos = true;
        } else if (i === 4) {
          permissions.can_send_videos = true;
        } else if (i === 5) {
          permissions.can_send_video_notes = true;
        } else if (i === 6) {
          permissions.can_send_voice_notes = true;
        } else if (i === 7) {
          permissions.can_send_polls = true;
        } else {
          permissions.can_send_other_messages = true;
        }
        const rights: ChatSendRights = sendRightsFromPermissions(permissions);
        expected.push([
          rights.basic, rights.audios, rights.documents, rights.photos, rights.videos,
          rights.videoNotes, rights.voiceNotes, rights.polls, rights.otherMessages
        ]);
      }
      for (let row = 0; row < flags.length; row++) {
        for (let col = 0; col < flags.length; col++) {
          expect(expected[row][col]).assertEqual(row === col);
        }
      }
    });

    it('sameAs_detectsSingleBitDifference', 0, () => {
      const all: ChatSendRights = new ChatSendRights();
      expect(all.sameAs(sendRightsFromPermissions(null))).assertTrue();
      const noPoll: ChatSendRights = new ChatSendRights(true, true, true, true, true, true, true, false, true);
      expect(all.sameAs(noPoll)).assertFalse();
      expect(noPoll.sameAs(new ChatSendRights(true, true, true, true, true, true, true, false, true))).assertTrue();
    });

    it('attachmentEntries_followMediaBitsIndependently', 0, () => {
      // 只放开图片：Gallery 可用，Video / File / Poll 不可用。
      const permissions: ChatPermissions = emptyPermissions();
      permissions.can_send_photos = true;
      const entries: AttachmentEntry[] = buildAttachmentEntries(sendRightsFromPermissions(permissions));
      expect(entries.length).assertEqual(4);
      expect(entries[0].key).assertEqual(ATTACHMENT_GALLERY);
      expect(entries[1].key).assertEqual(ATTACHMENT_VIDEO);
      expect(entries[2].key).assertEqual(ATTACHMENT_FILE);
      expect(entries[3].key).assertEqual(ATTACHMENT_POLL);
      expect(entries[0].enabled).assertTrue();
      expect(entries[1].enabled).assertFalse();
      expect(entries[2].enabled).assertFalse();
      expect(entries[3].enabled).assertFalse();
    });

    it('attachmentEntries_readOnlyChatKeepsAllEntriesVisible', 0, () => {
      // 受限频道不能让入口凭空消失：条目齐、全不可用，点了由提示解释原因。
      const permissions: ChatPermissions = emptyPermissions();
      permissions.can_send_basic_messages = true;
      const entries: AttachmentEntry[] = buildAttachmentEntries(sendRightsFromPermissions(permissions));
      expect(entries.length).assertEqual(4);
      for (let i = 0; i < entries.length; i++) {
        expect(entries[i].enabled).assertFalse();
        expect(attachmentRestrictionLabel(entries[i]).length > 0).assertTrue();
      }
    });

    it('restrictionLabel_emptyForEnabledAndDistinctPerKind', 0, () => {
      const labels: string[] = [];
      const keys: string[] = [ATTACHMENT_GALLERY, ATTACHMENT_VIDEO, ATTACHMENT_FILE, ATTACHMENT_POLL];
      for (let i = 0; i < keys.length; i++) {
        const disabled: AttachmentEntry = new AttachmentEntry(keys[i], false);
        labels.push(attachmentRestrictionLabel(disabled));
        expect(attachmentRestrictionLabel(new AttachmentEntry(keys[i], true))).assertEqual('');
      }
      // 四种受限原因文案不得雷同，否则用户看不出到底是哪一类被禁。
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < labels.length; i++) {
        seen.add(labels[i]);
      }
      expect(seen.size).assertEqual(4);
      expect(attachmentRestrictionLabel(new AttachmentEntry('unknown', false)).length > 0).assertTrue();
    });

    it('canSendAnyMedia_ignoresBasicOnlyRight', 0, () => {
      // 只能发文本：附件入口整体没有意义，输入栏仍要保留。
      const textOnly: ChatSendRights = new ChatSendRights(true, false, false, false, false, false, false, false, false);
      expect(canSendAnyMedia(textOnly)).assertFalse();
      expect(textOnly.basic).assertTrue();
      const onlyStickers: ChatSendRights = new ChatSendRights(false, false, false, false, false, false, false, false, true);
      expect(canSendAnyMedia(onlyStickers)).assertTrue();
    });

    it('canRecordVoice_acceptsEitherVoiceOrVideoNote', 0, () => {
      expect(canRecordVoice(new ChatSendRights(true, true, true, true, true, false, true, true, true))).assertTrue();
      expect(canRecordVoice(new ChatSendRights(true, true, true, true, true, true, false, true, true))).assertTrue();
      expect(canRecordVoice(new ChatSendRights(true, true, true, true, true, false, false, true, true))).assertFalse();
    });
  });
}
