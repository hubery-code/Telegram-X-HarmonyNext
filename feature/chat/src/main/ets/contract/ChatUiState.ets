/**
 * feature/chat — 会话页可观察状态（CHAT-001 + CHAT-003）。
 *
 * 遵循计划 §5.11 / UI-003：所有字段只读，不可变更新经 copyWith() 派生。
 * messages 按时间升序（最旧在前），渲染层倒置显示最新在底。
 * composerText 驱动底部输入栏（受控输入），发送后立即清空。
 */

import { UiState } from '@tgx/feature-template';
import { MessageItem } from '../model/MessageItem';

export interface ChatUiStateOptions {
  readonly chatTitle?: string;
  readonly messages?: readonly MessageItem[];
  readonly isLoading?: boolean;
  readonly hasMoreOlder?: boolean;
  readonly errorMessage?: string | null;
  readonly composerText?: string;
}

export class ChatUiState implements UiState {
  readonly chatId: number;
  readonly chatTitle: string;
  readonly messages: readonly MessageItem[];
  readonly isLoading: boolean;
  readonly hasMoreOlder: boolean;
  readonly errorMessage: string | null;
  readonly composerText: string;

  constructor(
    chatId: number,
    chatTitle: string,
    messages: readonly MessageItem[],
    isLoading: boolean,
    hasMoreOlder: boolean,
    errorMessage: string | null,
    composerText: string
  ) {
    this.chatId = chatId;
    this.chatTitle = chatTitle;
    this.messages = messages;
    this.isLoading = isLoading;
    this.hasMoreOlder = hasMoreOlder;
    this.errorMessage = errorMessage;
    this.composerText = composerText;
  }

  static initial(): ChatUiState {
    return new ChatUiState(0, '', [], false, true, null, '');
  }

  copyWith(options: ChatUiStateOptions): ChatUiState {
    return new ChatUiState(
      this.chatId,
      options.chatTitle !== undefined ? options.chatTitle : this.chatTitle,
      options.messages !== undefined ? options.messages : this.messages,
      options.isLoading !== undefined ? options.isLoading : this.isLoading,
      options.hasMoreOlder !== undefined ? options.hasMoreOlder : this.hasMoreOlder,
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage,
      options.composerText !== undefined ? options.composerText : this.composerText
    );
  }
}
