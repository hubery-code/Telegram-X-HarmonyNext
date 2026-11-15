/**
 * feature/chat — 覆盖层的物理返回键收口（CHAT-BACK-101）。
 *
 * 会话页的每一种子页/弹层/面板都是 `ChatPage.build()` 里叠在同一层 Stack 上的覆盖层，
 * 不是系统导航栈里的独立页面。
 *
 * 覆盖层关闭优先级严格依照 `ChatPage.ets` 中 Stack 的视觉层叠顺序（后渲染的在上层），
 * 最顶层先关：
 * 1. showMenuConfirmDialog：⋮ 菜单破坏性操作确认弹窗（顶层模态）
 * 2. stickerSetPreview !== null：贴纸包详情与添加弹窗（全屏遮罩抽屉）
 * 3. showSearch：聊天内搜索面板（顶部覆盖搜索条与结果列表）
 * 4. activeViewerIndex >= 0：全屏媒体查看器
 * 5. pollComposer !== null：发起投票面板（半透明遮罩抽屉）
 * 6. showAttachmentMenu：附件选择面板抽屉
 * 7. actionMenu !== null：长按气泡的操作菜单
 * 8. showEmojiBoard：表情与贴纸键盘抽屉
 * 9. selectionMode：多选转发状态（返回则退出多选态，不退群聊）
 * 10. topicManage.confirmDeleteTopicId：话题删除确认（FORUM-104，列表覆盖层内最顶层）
 * 11. topicManage.menuTopicId：话题长按菜单（FORUM-104）
 * 12. topicManage.dialogOpen：创建/编辑话题弹窗（FORUM-104）
 * 13. showForumTopics：话题列表覆盖层（FORUM-101 当轮漏接，FORUM-102 补上）
 * 14. activeTopicId > 0：话题消息流打开中（返回回话题列表，FORUM-102）
 *
 * 若所有覆盖层均未激活（返回 null），由外部装配层（`entry`）执行 `BackToChatList` 退出会话。
 */

import {
  ChatIntent,
  CloseActiveTopic,
  CloseAttachmentMenu,
  CloseChatSearch,
  CloseEmojiBoard,
  CloseForumTopics,
  CloseMediaViewer,
  ClosePollComposer,
  CloseStickerSetPreview,
  CloseTopicManageDialog,
  CloseTopicMenu,
  DismissDeleteTopic,
  DismissMenuConfirmDialog,
  DismissMessageActionMenu,
  ExitMessageSelection
} from '../contract/ChatIntent';
import { ChatUiState } from '../contract/ChatUiState';

/**
 * 返回这一次物理返回键应当派发的关闭意图；`null` 表示当前没有任何覆盖层，
 * 调用方（`entry`）才派发 BackToChatList 或放行路由 pop。
 */
export function chatOverlayCloseIntent(state: ChatUiState): ChatIntent | null {
  if (state.showMenuConfirmDialog) {
    return new DismissMenuConfirmDialog();
  }
  if (state.stickerSetPreview !== null) {
    return new CloseStickerSetPreview();
  }
  if (state.showSearch) {
    return new CloseChatSearch();
  }
  if (state.activeViewerIndex >= 0) {
    return new CloseMediaViewer();
  }
  if (state.pollComposer !== null) {
    return new ClosePollComposer();
  }
  if (state.showAttachmentMenu) {
    return new CloseAttachmentMenu();
  }
  if (state.actionMenu !== null) {
    return new DismissMessageActionMenu();
  }
  if (state.showEmojiBoard) {
    return new CloseEmojiBoard();
  }
  if (state.selectionMode) {
    return new ExitMessageSelection();
  }
  // FORUM-104：话题管理三弹层渲染在话题列表覆盖层内部（后渲染在上），
  // 收口顺序与视觉一致：删除确认 > 长按菜单 > 创建/编辑弹窗。
  if (state.topicManage !== null) {
    if (state.topicManage.confirmDeleteTopicId > 0) {
      return new DismissDeleteTopic();
    }
    if (state.topicManage.menuTopicId > 0) {
      return new CloseTopicMenu();
    }
    if (state.topicManage.dialogOpen) {
      return new CloseTopicManageDialog();
    }
  }
  // FORUM-102：话题列表覆盖层盖在消息流上（无论底下是全会话还是已打开的
  // 话题），所以先于话题态判断——列表在最上，先关列表；再按一次才关话题，
  // 关话题时 reducer 会把列表重新拉起，形成 会话 → 话题列表 → 话题 的
  // 三层返回链。
  if (state.showForumTopics) {
    return new CloseForumTopics();
  }
  if (state.activeTopicId > 0) {
    return new CloseActiveTopic();
  }
  return null;
}
