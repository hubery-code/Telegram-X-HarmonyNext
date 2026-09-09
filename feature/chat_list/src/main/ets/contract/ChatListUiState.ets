/**
 * feature/chat_list — 会话列表可观察状态（CHATLIST-002）。
 *
 * 遵循计划 §5.11 / UI-003：所有字段只读，不可变更新经 copyWith() 派生。
 */

import { UiState } from '@tgx/feature-template';
import { ChatListItem } from '../model/ChatListItem';

export interface ChatListUiStateOptions {
  readonly items?: readonly ChatListItem[];
  readonly isLoading?: boolean;
  readonly errorMessage?: string | null;
}

export class ChatListUiState implements UiState {
  readonly items: readonly ChatListItem[];
  readonly isLoading: boolean;
  readonly errorMessage: string | null;

  constructor(items: readonly ChatListItem[], isLoading: boolean, errorMessage: string | null) {
    this.items = items;
    this.isLoading = isLoading;
    this.errorMessage = errorMessage;
  }

  static initial(): ChatListUiState {
    return new ChatListUiState([], false, null);
  }

  copyWith(options: ChatListUiStateOptions): ChatListUiState {
    return new ChatListUiState(
      options.items !== undefined ? options.items : this.items,
      options.isLoading !== undefined ? options.isLoading : this.isLoading,
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage
    );
  }
}
