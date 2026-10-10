/**
 * feature/chat — 频道帖子评论列表协调器（CHANNEL-101 / FEAT-P2-002 / FEAT-P2-003）。
 *
 * 遵循 ARCH-001 与 ADR-007，纯 ArkTS 实现，100% Kit-free。
 * 管理频道帖子评论页的状态与 TDLib 讨论组消息交互：
 * 1. start()：获取频道帖子详情（GetMessage / GetChat）及评论线程（GetMessageThread）；
 * 2. 拿到关联讨论超级群（discussion supergroup）与 message_thread_id 后，调用 GetMessageThreadHistory 拉取历史评论；
 * 3. sendComment()：向讨论群以 message_thread_id 为 replyTo 派发 SendMessage，并支持本地即时乐观回显。
 */

import {
  datePartsFrom,
  formatTimeOfDay,
  HourClock,
  Lang,
  Result,
  AppError,
  SupportedLanguage
} from '@tgx/core-common';
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

/**
 * 评论行的**原始输入**（I18N-HOTSWITCH-102）：`CommentItem` 里的 `senderName`/`dateText`
 * 是已解析串，语言与时制一变就旧；能重投影的只有这些与语言无关的字段。
 * 留 `avatarColor` 是因为它由 `sender_id` 派生，而投影阶段已经没有 `sender_id`。
 */
interface CommentSource {
  readonly id: number;
  readonly text: string;
  readonly dateUnix: number;
  readonly isOutgoing: boolean;
  readonly isSending: boolean;
  readonly avatarColor: string;
}

const AVATAR_PALETTE: string[] = [
  '#FF4A82', '#E17076', '#FAA774', '#FFCE54',
  '#3ECF8E', '#29B6F6', '#7E57C2', '#AB47BC'
];

function pickAvatarColor(id: number): string {
  const abs: number = Math.abs(id);
  return AVATAR_PALETTE[abs % AVATAR_PALETTE.length];
}

/**
 * 评论行的时间。I18N-DATE-102：这一位此前手写 `HH:mm`（`getHours()`/`getMinutes()` 拼串），
 * 既不跟界面语言也不跟系统时制；档位与语言在投影时现取，形态只在 `DateFormat`。
 */
function formatUnixTime(unixSec: number): string {
  if (unixSec <= 0) {
    return '';
  }
  const lang: SupportedLanguage = Lang.getInstance().getLanguage();
  const clock: HourClock = Lang.getInstance().getHourClock();
  return formatTimeOfDay(datePartsFrom(unixSec * 1000), lang, clock);
}

/**
 * 评论行的投影（I18N-HOTSWITCH-102）：发送者称谓与时刻都在这一句**现取**，
 * 所以换语言/换时制后重跑一次 `buildState()` 就是新词新形态，不需要重新取数。
 */
function projectComment(source: CommentSource): CommentItem {
  const senderName: string = source.isOutgoing
    ? Lang.getInstance().getString('Me')
    : Lang.getInstance().getString('User');
  return {
    id: source.id,
    senderName: senderName,
    senderAvatarLetter: senderName.charAt(0).toUpperCase(),
    senderAvatarColor: source.avatarColor,
    text: source.text,
    dateText: formatUnixTime(source.dateUnix),
    isOutgoing: source.isOutgoing,
    isSending: source.isSending
  };
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

  /**
   * I18N-HOTSWITCH-102：状态里所有会随语言/时制变的位，一律从这些**与语言无关的原始输入**
   * 现取现投（`buildState()` 是全文件唯一的组装点）。换语言时只做一次纯本地重投影，
   * 不发任何新请求 —— 与 `ChatCoordinator.subscribeLanguage()` 同一条红线。
   */
  private titleSource: string = '';
  /** null = 主帖还没回；此时 `postText` 必须是空串，不能出「Channel message」兜底。 */
  private postTextSource: string | null = null;
  private postDateUnix: number = 0;
  private countSource: number = 0;
  private loadingSource: boolean = true;
  private sendingSource: boolean = false;
  private inputSource: string = '';
  /** 词典可解的错误（本地可重投）。 */
  private errorKey: string | null = null;
  /** TDLib/AppError 原文（与语言无关，原样留着）。 */
  private errorRaw: string | null = null;
  private commentSources: CommentSource[] = [];

  private lastProjectedLanguage: SupportedLanguage = Lang.getInstance().getLanguage();
  private lastProjectedClock: HourClock = Lang.getInstance().getHourClock();
  private unsubscribeLang: (() => void) | null = null;

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

    this.state = this.buildState();
  }

  /**
   * 唯一的投影点：把原始输入 + 当前的语言与时制档拼成上屏状态。
   * 一切词典取值都在这里现取，所以换语言后重跑一次就是新语言。
   */
  private buildState(): CommentsUiState {
    const lang: Lang = Lang.getInstance();
    let errorText: string | null = null;
    if (this.errorKey !== null) {
      errorText = lang.getString(this.errorKey);
    } else if (this.errorRaw !== null) {
      errorText = this.errorRaw;
    }
    return {
      channelChatId: this.channelChatId,
      channelPostId: this.channelPostId,
      channelTitle: this.titleSource.length > 0
        ? this.titleSource
        : lang.getString('Channel post'),
      postText: this.postTextSource === null
        ? ''
        : (this.postTextSource.length > 0 ? this.postTextSource : lang.getString('Channel message')),
      postDate: formatUnixTime(this.postDateUnix),
      commentsCount: this.countSource,
      isLoading: this.loadingSource,
      isSending: this.sendingSource,
      comments: this.commentSources.map((s: CommentSource): CommentItem => projectComment(s)),
      inputText: this.inputSource,
      errorMessage: errorText
    };
  }

  /** 改原始输入并重新投影上屏（本文件唯一的状态出口）。 */
  private repaint(): void {
    if (this.destroyed) {
      return;
    }
    this.state = this.buildState();
    this.notify();
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
    this.subscribeLanguage();
    this.loadChannelPostAndTitle();
    this.loadMessageThreadInfo();
  }

  /**
   * I18N-HOTSWITCH-102：换语言 / 换系统时制后用留存的原始输入重投影一次。
   *
   * **纯本地**：只读 `Lang` 与 `this.*Source`，不发任何 TDLib 请求 —— 评论页开着时切语言
   * 走不到（切语言必须进设置，本页此时已销毁），所以这条路靠单测把不变量钉住
   * （同输入两次投影逐字相同 + 语言位变化后称谓/时刻/兜底串换词而取数不重发）。
   */
  private subscribeLanguage(): void {
    this.lastProjectedLanguage = Lang.getInstance().getLanguage();
    this.lastProjectedClock = Lang.getInstance().getHourClock();
    const self: CommentsCoordinator = this;
    this.unsubscribeLang = Lang.getInstance().subscribe((lang: SupportedLanguage): void => {
      const clock: HourClock = Lang.getInstance().getHourClock();
      if (self.destroyed || (lang === self.lastProjectedLanguage && clock === self.lastProjectedClock)) {
        return;
      }
      self.lastProjectedLanguage = lang;
      self.lastProjectedClock = clock;
      self.repaint();
    });
  }

  destroy(): void {
    this.destroyed = true;
    if (this.unsubscribeLang !== null) {
      this.unsubscribeLang();
      this.unsubscribeLang = null;
    }
    this.listeners.length = 0;
  }

  setInputText(text: string): void {
    this.inputSource = text;
    this.repaint();
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
            this.titleSource = chat.title;
            this.repaint();
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
            let count: number = this.countSource;
            if (msg.interaction_info !== null && msg.interaction_info.reply_info !== null) {
              count = msg.interaction_info.reply_info.reply_count;
            }
            this.postTextSource = messageContentText(msg.content);
            this.postDateUnix = msg.date;
            this.countSource = count;
            this.repaint();
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
      this.loadingSource = false;
      this.errorKey = null;
      this.errorRaw = result.error.message;
      this.repaint();
      return;
    }

    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (res.err) {
          this.loadingSource = false;
          this.errorKey = null;
          this.errorRaw = res.error.message;
          this.repaint();
          return;
        }

        if (res.ok) {
          const info: MessageThreadInfo | null = decodeMessageThreadInfo(res.value as TdJsonRaw);
          if (info === null) {
            this.loadingSource = false;
            this.errorRaw = null;
            this.errorKey = 'No comment thread';
            this.repaint();
            return;
          }

          this.discussionChatId = info.chat_id;
          this.messageThreadId = info.message_thread_id;
          const count: number = info.reply_info !== null ? info.reply_info.reply_count : info.messages.length;

          // 如果返回对象已附带 messages
          if (info.messages.length > 0) {
            this.commentSources = this.mapMessagesToSources(info.messages);
            this.countSource = Math.max(count, this.commentSources.length);
            this.loadingSource = false;
            this.errorKey = null;
            this.errorRaw = null;
            this.repaint();
          }

          // 拉取更完整的评论历史
          this.loadThreadHistory(info.chat_id, info.message_thread_id);
        }
      }).catch((): void => {
        if (!this.destroyed) {
          this.loadingSource = false;
          this.errorRaw = null;
          this.errorKey = 'Network error';
          this.repaint();
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
            const items: CommentSource[] = this.mapMessagesToSources(msgs.messages);
            this.commentSources = items;
            this.countSource = Math.max(this.countSource, items.length);
            this.loadingSource = false;
            this.errorKey = null;
            this.errorRaw = null;
            this.repaint();
          }
        }
      }).catch((): void => {});
    }
  }

  private mapMessagesToSources(messages: Message[]): CommentSource[] {
    const list: CommentSource[] = [];
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
      list.push({
        id: m.id,
        text: text,
        dateUnix: m.date,
        isOutgoing: m.is_outgoing,
        isSending: m.sending_state !== null,
        avatarColor: pickAvatarColor(m.sender_id !== null ? 1 : 0)
      });
    }

    // 升序排列（旧在上，新在下）
    list.sort((a: CommentSource, b: CommentSource): number => a.id - b.id);
    return list;
  }

  sendComment(): void {
    const text: string = this.inputSource.trim();
    if (text.length === 0 || this.sendingSource) {
      return;
    }

    const targetChatId: number = this.discussionChatId !== 0 ? this.discussionChatId : this.channelChatId;
    const targetReplyId: number = this.messageThreadId !== 0 ? this.messageThreadId : this.channelPostId;

    // 乐观插入本地评论（存原始输入，称谓/时刻由 `projectComment` 现取）
    const tempId: number = Date.now();
    const optimistic: CommentSource = {
      id: tempId,
      text: text,
      dateUnix: Math.floor(tempId / 1000),
      isOutgoing: true,
      isSending: true,
      avatarColor: pickAvatarColor(0)
    };

    const newSources: CommentSource[] = this.commentSources.slice();
    newSources.push(optimistic);
    this.commentSources = newSources;
    this.countSource = this.countSource + 1;
    this.sendingSource = true;
    this.inputSource = '';
    this.errorKey = null;
    this.errorRaw = null;
    this.repaint();

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
    this.commentSources = this.commentSources.map((s: CommentSource): CommentSource => {
      if (s.id !== tempId) {
        return s;
      }
      return {
        id: s.id,
        text: s.text,
        dateUnix: s.dateUnix,
        isOutgoing: s.isOutgoing,
        isSending: isSending,
        avatarColor: s.avatarColor
      };
    });
    this.sendingSource = false;
    this.repaint();
  }
}
