/**
 * feature/chat — 频道帖子评论列表协调器（CHANNEL-101 / FEAT-P2-002 / FEAT-P2-003）。
 *
 * 遵循 ARCH-001 与 ADR-007，纯 ArkTS 实现，100% Kit-free。
 * 管理频道帖子评论页的状态与 TDLib 讨论组消息交互：
 * 1. start()：获取频道帖子详情（GetMessage / GetChat）及评论线程（GetMessageThread）；
 * 2. 拿到关联讨论超级群（discussion supergroup）与 message_thread_id 后，调用 GetMessageThreadHistory 拉取历史评论；
 * 3. sendComment()：向讨论群以 message_thread_id 为 replyTo 派发 SendMessage，并支持本地即时乐观回显。
 */

import { Result, AppError } from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import {
  Chat,
  decodeChat,
  decodeMessage,
  decodeMessageThreadInfo,
  decodeMessages,
  encodeGetChat,
  encodeGetMessage,
  encodeGetMessageThread,
  encodeGetMessageThreadHistory,
  encodeSendMessage,
  FormattedText,
  GetChat,
  GetMessage,
  GetMessageThread,
  GetMessageThreadHistory,
  InputMessageReplyToMessage,
  InputMessageText,
  Message,
  MessageThreadInfo,
  Messages,
  SendMessage,
  TdJsonRaw
} from '@tgx/core-td-api-generated';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { messageContentText } from './ChatCoordinator';

export interface CommentItem {
  readonly id: number;
  readonly senderName: string;
  readonly senderAvatarLetter: string;
  readonly senderAvatarColor: string;
  readonly text: string;
  readonly dateText: string;
  readonly isOutgoing: boolean;
  readonly isSending: boolean;
}

export interface CommentsUiState {
  readonly channelChatId: number;
  readonly channelPostId: number;
  readonly channelTitle: string;
  readonly postText: string;
  readonly postDate: string;
  readonly commentsCount: number;
  readonly isLoading: boolean;
  readonly isSending: boolean;
  readonly comments: CommentItem[];
  readonly inputText: string;
  readonly errorMessage: string | null;
}

export type CommentsUiStateListener = (state: CommentsUiState) => void;

const AVATAR_PALETTE: string[] = [
  '#FF4A82', '#E17076', '#FAA774', '#FFCE54',
  '#3ECF8E', '#29B6F6', '#7E57C2', '#AB47BC'
];

function pickAvatarColor(id: number): string {
  const abs: number = Math.abs(id);
  return AVATAR_PALETTE[abs % AVATAR_PALETTE.length];
}

function formatUnixTime(unixSec: number): string {
  if (unixSec <= 0) {
    return '';
  }
  const date: Date = new Date(unixSec * 1000);
  const h: number = date.getHours();
  const m: number = date.getMinutes();
  const hStr: string = h < 10 ? `0${h}` : `${h}`;
  const mStr: string = m < 10 ? `0${m}` : `${m}`;
  return `${hStr}:${mStr}`;
}

export class CommentsCoordinator {
  private readonly scope: AccountScope;
  private readonly channelChatId: number;
  private readonly channelPostId: number;
  private readonly onBack: () => void;

  private discussionChatId: number = 0;
  private messageThreadId: number = 0;
  private destroyed: boolean = false;
  private readonly listeners: CommentsUiStateListener[] = [];

  private state: CommentsUiState;

  constructor(
    scope: AccountScope,
    channelChatId: number,
    channelPostId: number,
    onBack?: () => void
  ) {
    this.scope = scope;
    this.channelChatId = channelChatId;
    this.channelPostId = channelPostId;
    this.onBack = onBack !== undefined ? onBack : (): void => {};

    this.state = {
      channelChatId: channelChatId,
      channelPostId: channelPostId,
      channelTitle: '频道帖子',
      postText: '',
      postDate: '',
      commentsCount: 0,
      isLoading: true,
      isSending: false,
      comments: [],
      inputText: '',
      errorMessage: null
    };
  }

  getState(): CommentsUiState {
    return this.state;
  }

  subscribe(listener: CommentsUiStateListener): () => void {
    this.listeners.push(listener);
    listener(this.state);
    return (): void => {
      const idx: number = this.listeners.indexOf(listener);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
      }
    };
  }

  private notify(): void {
    if (this.destroyed) {
      return;
    }
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i](this.state);
    }
  }

  start(): void {
    this.loadChannelPostAndTitle();
    this.loadMessageThreadInfo();
  }

  destroy(): void {
    this.destroyed = true;
    this.listeners.length = 0;
  }

  setInputText(text: string): void {
    this.state = {
      channelChatId: this.state.channelChatId,
      channelPostId: this.state.channelPostId,
      channelTitle: this.state.channelTitle,
      postText: this.state.postText,
      postDate: this.state.postDate,
      commentsCount: this.state.commentsCount,
      isLoading: this.state.isLoading,
      isSending: this.state.isSending,
      comments: this.state.comments,
      inputText: text,
      errorMessage: this.state.errorMessage
    };
    this.notify();
  }

  private loadChannelPostAndTitle(): void {
    // 1. 获取频道信息
    const getChatReq: GetChat = new GetChat();
    getChatReq.chat_id = this.channelChatId;
    const chatResult: Result<TdPendingRequest, AppError> =
      this.scope.request('getChat', encodeGetChat(getChatReq) as TdWireObject);
    if (chatResult.ok) {
      chatResult.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (res.ok) {
          const chat: Chat | null = decodeChat(res.value as TdJsonRaw);
          if (chat !== null && chat.title.length > 0) {
            this.state = {
              channelChatId: this.state.channelChatId,
              channelPostId: this.state.channelPostId,
              channelTitle: chat.title,
              postText: this.state.postText,
              postDate: this.state.postDate,
              commentsCount: this.state.commentsCount,
              isLoading: this.state.isLoading,
              isSending: this.state.isSending,
              comments: this.state.comments,
              inputText: this.state.inputText,
              errorMessage: this.state.errorMessage
            };
            this.notify();
          }
        }
      }).catch((): void => {});
    }

    // 2. 获取主帖内容
    const getMsgReq: GetMessage = new GetMessage();
    getMsgReq.chat_id = this.channelChatId;
    getMsgReq.message_id = this.channelPostId;
    const msgResult: Result<TdPendingRequest, AppError> =
      this.scope.request('getMessage', encodeGetMessage(getMsgReq) as TdWireObject);
    if (msgResult.ok) {
      msgResult.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (res.ok) {
          const msg: Message | null = decodeMessage(res.value as TdJsonRaw);
          if (msg !== null) {
            const text: string = messageContentText(msg.content);
            const dateText: string = formatUnixTime(msg.date);
            let count: number = this.state.commentsCount;
            if (msg.interaction_info !== null && msg.interaction_info.reply_info !== null) {
              count = msg.interaction_info.reply_info.reply_count;
            }
            this.state = {
              channelChatId: this.state.channelChatId,
              channelPostId: this.state.channelPostId,
              channelTitle: this.state.channelTitle,
              postText: text.length > 0 ? text : '频道消息',
              postDate: dateText,
              commentsCount: count,
              isLoading: this.state.isLoading,
              isSending: this.state.isSending,
              comments: this.state.comments,
              inputText: this.state.inputText,
              errorMessage: this.state.errorMessage
            };
            this.notify();
          }
        }
      }).catch((): void => {});
    }
  }

  private loadMessageThreadInfo(): void {
    const req: GetMessageThread = new GetMessageThread();
    req.chat_id = this.channelChatId;
    req.message_id = this.channelPostId;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getMessageThread', encodeGetMessageThread(req) as TdWireObject);
    if (result.err) {
      this.state = {
        channelChatId: this.state.channelChatId,
        channelPostId: this.state.channelPostId,
        channelTitle: this.state.channelTitle,
        postText: this.state.postText,
        postDate: this.state.postDate,
        commentsCount: this.state.commentsCount,
        isLoading: false,
        isSending: this.state.isSending,
        comments: this.state.comments,
        inputText: this.state.inputText,
        errorMessage: result.error.message
      };
      this.notify();
      return;
    }

    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (res.err) {
          this.state = {
            channelChatId: this.state.channelChatId,
            channelPostId: this.state.channelPostId,
            channelTitle: this.state.channelTitle,
            postText: this.state.postText,
            postDate: this.state.postDate,
            commentsCount: this.state.commentsCount,
            isLoading: false,
            isSending: this.state.isSending,
            comments: this.state.comments,
            inputText: this.state.inputText,
            errorMessage: res.error.message
          };
          this.notify();
          return;
        }

        if (res.ok) {
          const info: MessageThreadInfo | null = decodeMessageThreadInfo(res.value as TdJsonRaw);
          if (info === null) {
            this.state = {
              channelChatId: this.state.channelChatId,
              channelPostId: this.state.channelPostId,
              channelTitle: this.state.channelTitle,
              postText: this.state.postText,
              postDate: this.state.postDate,
              commentsCount: this.state.commentsCount,
              isLoading: false,
              isSending: this.state.isSending,
              comments: this.state.comments,
              inputText: this.state.inputText,
              errorMessage: '无法获取评论线程'
            };
            this.notify();
            return;
          }

          this.discussionChatId = info.chat_id;
          this.messageThreadId = info.message_thread_id;
          const count: number = info.reply_info !== null ? info.reply_info.reply_count : info.messages.length;

          // 如果返回对象已附带 messages
          if (info.messages.length > 0) {
            const initialItems: CommentItem[] = this.mapMessagesToComments(info.messages);
            this.state = {
              channelChatId: this.state.channelChatId,
              channelPostId: this.state.channelPostId,
              channelTitle: this.state.channelTitle,
              postText: this.state.postText,
              postDate: this.state.postDate,
              commentsCount: Math.max(count, initialItems.length),
              isLoading: false,
              isSending: this.state.isSending,
              comments: initialItems,
              inputText: this.state.inputText,
              errorMessage: null
            };
            this.notify();
          }

          // 拉取更完整的评论历史
          this.loadThreadHistory(info.chat_id, info.message_thread_id);
        }
      }).catch((): void => {
      if (!this.destroyed) {
        this.state = {
          channelChatId: this.state.channelChatId,
          channelPostId: this.state.channelPostId,
          channelTitle: this.state.channelTitle,
          postText: this.state.postText,
          postDate: this.state.postDate,
          commentsCount: this.state.commentsCount,
          isLoading: false,
          isSending: this.state.isSending,
          comments: this.state.comments,
          inputText: this.state.inputText,
          errorMessage: '网络异常'
        };
        this.notify();
      }
    });
    }
  }

  private loadThreadHistory(chatId: number, threadId: number): void {
    const req: GetMessageThreadHistory = new GetMessageThreadHistory();
    req.chat_id = chatId;
    req.message_id = threadId;
    req.from_message_id = 0;
    req.offset = 0;
    req.limit = 50;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getMessageThreadHistory', encodeGetMessageThreadHistory(req) as TdWireObject);
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (res.ok) {
          const msgs: Messages | null = decodeMessages(res.value as TdJsonRaw);
          if (msgs !== null && msgs.messages.length > 0) {
            const items: CommentItem[] = this.mapMessagesToComments(msgs.messages);
            this.state = {
              channelChatId: this.state.channelChatId,
              channelPostId: this.state.channelPostId,
              channelTitle: this.state.channelTitle,
              postText: this.state.postText,
              postDate: this.state.postDate,
              commentsCount: Math.max(this.state.commentsCount, items.length),
              isLoading: false,
              isSending: this.state.isSending,
              comments: items,
              inputText: this.state.inputText,
              errorMessage: null
            };
            this.notify();
          }
        }
      }).catch((): void => {});
    }
  }

  private mapMessagesToComments(messages: Message[]): CommentItem[] {
    const list: CommentItem[] = [];
    for (let i = 0; i < messages.length; i++) {
      const m: Message = messages[i];
      // 过滤掉主帖自身（根 anchor）
      if (m.id === this.messageThreadId) {
        continue;
      }
      const text: string = messageContentText(m.content);
      if (text.length === 0) {
        continue;
      }
      let senderName: string = m.is_outgoing ? '我' : '用户';
      let avatarLetter: string = senderName.charAt(0).toUpperCase();
      let avatarColor: string = pickAvatarColor(m.sender_id !== null ? 1 : 0);

      list.push({
        id: m.id,
        senderName: senderName,
        senderAvatarLetter: avatarLetter,
        senderAvatarColor: avatarColor,
        text: text,
        dateText: formatUnixTime(m.date),
        isOutgoing: m.is_outgoing,
        isSending: m.sending_state !== null
      });
    }

    // 升序排列（旧在上，新在下）
    list.sort((a: CommentItem, b: CommentItem): number => a.id - b.id);
    return list;
  }

  sendComment(): void {
    const text: string = this.state.inputText.trim();
    if (text.length === 0 || this.state.isSending) {
      return;
    }

    const targetChatId: number = this.discussionChatId !== 0 ? this.discussionChatId : this.channelChatId;
    const targetReplyId: number = this.messageThreadId !== 0 ? this.messageThreadId : this.channelPostId;

    // 乐观插入本地评论
    const tempId: number = Date.now();
    const optimisticItem: CommentItem = {
      id: tempId,
      senderName: '我',
      senderAvatarLetter: '我',
      senderAvatarColor: pickAvatarColor(0),
      text: text,
      dateText: formatUnixTime(Math.floor(Date.now() / 1000)),
      isOutgoing: true,
      isSending: true
    };

    const newComments: CommentItem[] = this.state.comments.slice();
    newComments.push(optimisticItem);

    this.state = {
      channelChatId: this.state.channelChatId,
      channelPostId: this.state.channelPostId,
      channelTitle: this.state.channelTitle,
      postText: this.state.postText,
      postDate: this.state.postDate,
      commentsCount: this.state.commentsCount + 1,
      isLoading: this.state.isLoading,
      isSending: true,
      comments: newComments,
      inputText: '',
      errorMessage: null
    };
    this.notify();

    // 组装 SendMessage
    const req: SendMessage = new SendMessage();
    req.chat_id = targetChatId;
    const replyTo: InputMessageReplyToMessage = new InputMessageReplyToMessage();
    replyTo.message_id = targetReplyId;
    req.reply_to = replyTo;

    const formatted: FormattedText = new FormattedText();
    formatted.text = text;
    const content: InputMessageText = new InputMessageText();
    content.text = formatted;
    req.input_message_content = content;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('sendMessage', encodeSendMessage(req) as TdWireObject);

    if (result.err) {
      this.updateOptimisticSendState(tempId, false);
      return;
    }

    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        this.updateOptimisticSendState(tempId, false);
      }).catch((): void => {
        if (!this.destroyed) {
          this.updateOptimisticSendState(tempId, false);
        }
      });
    }
  }

  private updateOptimisticSendState(tempId: number, isSending: boolean): void {
    const updated: CommentItem[] = this.state.comments.map((c: CommentItem): CommentItem => {
      if (c.id === tempId) {
        return {
          id: c.id,
          senderName: c.senderName,
          senderAvatarLetter: c.senderAvatarLetter,
          senderAvatarColor: c.senderAvatarColor,
          text: c.text,
          dateText: c.dateText,
          isOutgoing: c.isOutgoing,
          isSending: isSending
        };
      }
      return c;
    });

    this.state = {
      channelChatId: this.state.channelChatId,
      channelPostId: this.state.channelPostId,
      channelTitle: this.state.channelTitle,
      postText: this.state.postText,
      postDate: this.state.postDate,
      commentsCount: this.state.commentsCount,
      isLoading: this.state.isLoading,
      isSending: false,
      comments: updated,
      inputText: this.state.inputText,
      errorMessage: this.state.errorMessage
    };
    this.notify();
  }
}
