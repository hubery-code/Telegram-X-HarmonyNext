/**
 * feature/chat — 覆盖层物理返回键收口的单测（CHAT-BACK-101）。
 *
 * 断言视觉层叠顺序的关闭优先级：
 * 谁在最上面就先关谁；当所有覆盖层均未激活时，交回 null 让外部装配层（entry）执行会话退出。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ChatUiState, MessageActionMenuState } from '../main/ets/contract/ChatUiState';
import { StickerSetPreviewState } from '../main/ets/model/StickerSetPreviewState';
import { PollComposerState } from '../main/ets/model/PollView';
import { chatOverlayCloseIntent } from '../main/ets/model/ChatOverlayBack';

export default function chatOverlayBackTest(): void {
  describe('ChatOverlayBack', () => {
    it('idle_returnsNullSoRouterExitsChat', 0, () => {
      expect(chatOverlayCloseIntent(ChatUiState.initial())).assertNull();
    });

    it('menuConfirmDialog_dismissesConfirmDialog', 0, () => {
      const state: ChatUiState = ChatUiState.initial().copyWith({ showMenuConfirmDialog: true });
      expect(chatOverlayCloseIntent(state)?.kind).assertEqual('dismissMenuConfirmDialog');
    });

    it('stickerSetPreview_closesStickerSetPreview', 0, () => {
      const state: ChatUiState = ChatUiState.initial().copyWith({
        stickerSetPreview: new StickerSetPreviewState('pack-1')
      });
      expect(chatOverlayCloseIntent(state)?.kind).assertEqual('closeStickerSetPreview');
    });

    it('searchPanel_closesChatSearch', 0, () => {
      const state: ChatUiState = ChatUiState.initial().copyWith({ showSearch: true });
      expect(chatOverlayCloseIntent(state)?.kind).assertEqual('closeChatSearch');
    });

    it('mediaViewer_closesMediaViewer', 0, () => {
      const state: ChatUiState = ChatUiState.initial().copyWith({ activeViewerIndex: 0 });
      expect(chatOverlayCloseIntent(state)?.kind).assertEqual('closeMediaViewer');
    });

    it('pollComposer_closesPollComposer', 0, () => {
      const state: ChatUiState = ChatUiState.initial().copyWith({
        pollComposer: PollComposerState.draft()
      });
      expect(chatOverlayCloseIntent(state)?.kind).assertEqual('closePollComposer');
    });

    it('attachmentMenu_closesAttachmentMenu', 0, () => {
      const state: ChatUiState = ChatUiState.initial().copyWith({ showAttachmentMenu: true });
      expect(chatOverlayCloseIntent(state)?.kind).assertEqual('closeAttachmentMenu');
    });

    it('actionMenu_dismissesActionMenu', 0, () => {
      const state: ChatUiState = ChatUiState.initial().copyWith({
        actionMenu: new MessageActionMenuState(10, true, false, false, false)
      });
      expect(chatOverlayCloseIntent(state)?.kind).assertEqual('dismissMessageActionMenu');
    });

    it('emojiBoard_closesEmojiBoard', 0, () => {
      const state: ChatUiState = ChatUiState.initial().copyWith({ showEmojiBoard: true });
      expect(chatOverlayCloseIntent(state)?.kind).assertEqual('closeEmojiBoard');
    });

    it('selectionMode_exitsSelection', 0, () => {
      const state: ChatUiState = ChatUiState.initial().copyWith({
        selectionMode: true,
        selectedMessageIds: [1, 2]
      });
      expect(chatOverlayCloseIntent(state)?.kind).assertEqual('exitMessageSelection');
    });

    it('hierarchy_topmostOverlayWins', 0, () => {
      // 确认弹窗高于一切
      const state1: ChatUiState = ChatUiState.initial().copyWith({
        showMenuConfirmDialog: true,
        stickerSetPreview: new StickerSetPreviewState('pack-1'),
        showSearch: true
      });
      expect(chatOverlayCloseIntent(state1)?.kind).assertEqual('dismissMenuConfirmDialog');

      // 媒体查看器高于投票、附件面板与表情键盘
      const state2: ChatUiState = ChatUiState.initial().copyWith({
        activeViewerIndex: 1,
        pollComposer: PollComposerState.draft(),
        showAttachmentMenu: true,
        showEmojiBoard: true
      });
      expect(chatOverlayCloseIntent(state2)?.kind).assertEqual('closeMediaViewer');

      // 附件面板高于气泡菜单与表情键盘
      const state3: ChatUiState = ChatUiState.initial().copyWith({
        showAttachmentMenu: true,
        actionMenu: new MessageActionMenuState(10, true, false, false, false),
        showEmojiBoard: true
      });
      expect(chatOverlayCloseIntent(state3)?.kind).assertEqual('closeAttachmentMenu');

      // 表情键盘高于多选态
      const state4: ChatUiState = ChatUiState.initial().copyWith({
        showEmojiBoard: true,
        selectionMode: true
      });
      expect(chatOverlayCloseIntent(state4)?.kind).assertEqual('closeEmojiBoard');
    });
  });
}
