/**
 * feature/profile — 共享内容分页拉取（CHATPROF-SHARED）。
 *
 * searchChatMessages 的构造（空 query + 按 Tab 选过滤器 + from_message_id 续页）、
 * foundChatMessages 解码、逐 Tab 映射条目与 `next_from_message_id` 记账全部收在这里：
 * 用户资料页与群/频道资料页拉的是同一种数据，两处各写一份的话，「hasMore 怎么判」
 * 「空页算不算到底」这类规则会先分叉，页面表现就开始不一致。
 *
 * 只注入 `request`（= AccountScope.request）与两个路径查询端口（媒体缩略图走带订阅的
 * `localPathOf`，音频/语音走只查缓存的 `audioLocalPathOf`），因此 Kit-free、可单测。
 */

import { AppError, Result } from '@tgx/core-common';
import { Logger } from '@tgx/observability';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import {
  FoundChatMessages,
  Message,
  SearchChatMessages,
  SearchMessagesFilterAudio,
  SearchMessagesFilterDocument,
  SearchMessagesFilterPhotoAndVideo,
  SearchMessagesFilterUrl,
  SearchMessagesFilterVoiceNote,
  TdSearchMessagesFilter,
  decodeFoundChatMessages,
  encodeSearchChatMessages,
  TdJsonRaw
} from '@tgx/core-td-api-generated';
import { SharedAudioItem, SharedContentRows, SharedFileItem, SharedLinkItem, SharedMediaItem }
  from '../contract/SharedContentItems';
import { audioItemOf, fileItemOf, linkItemOf, sharedMediaItemOf, voiceItemOf } from './SharedContentFormat';

/** 共享内容每页拉取条数（对齐 TGX shared media 默认页大小）。 */
export const SHARED_PAGE_LIMIT: number = 20;

/**
 * 共享内容 Tab 编号（SHARED-AUDIO 扩到五个内容 Tab）。
 *
 * 顺序照 Android `ProfileController.getFiltersOrder()`：PhotoAndVideo、Document、Url、
 * Audio、（Animation 未做）、VoiceNote；「共同群组」是私聊资料页专属，固定排在最后。
 * 编号只增不改：已有的「切到 Tab 1 拉文件」用例与页面接线都按这套编号写。
 */
export const SHARED_TAB_MEDIA: number = 0;
export const SHARED_TAB_FILES: number = 1;
export const SHARED_TAB_LINKS: number = 2;
export const SHARED_TAB_AUDIO: number = 3;
export const SHARED_TAB_VOICE: number = 4;
export const SHARED_TAB_GROUPS: number = 5;

/** 一页结果：只填本次请求 Tab 对应的数组，其余保持空。 */
export class SharedContentPage {
  readonly tab: number;
  /** false = 请求失败/解码失败；调用方退回错误态，不能当成「没有内容」。 */
  readonly loaded: boolean;
  readonly rows: SharedContentRows;
  readonly hasMore: boolean;

  constructor(tab: number, loaded: boolean, rows: SharedContentRows, hasMore: boolean) {
    this.tab = tab;
    this.loaded = loaded;
    this.rows = rows;
    this.hasMore = hasMore;
  }

  static failed(tab: number): SharedContentPage {
    return new SharedContentPage(tab, false, new SharedContentRows(), false);
  }
}

/**
 * 把一页回并进入已有集合：加载更多是 append，首屏直接替换该 Tab。
 * 收在 model 里是因为两个资料页的 coordinator 都要做同样的事，写两份就会在
 * 「append 到底算不算覆盖游标」这类细节上分叉。
 */
export function mergeSharedRows(
  current: SharedContentRows,
  tab: number,
  incoming: SharedContentRows,
  isAppend: boolean
): SharedContentRows {
  if (tab === SHARED_TAB_MEDIA) {
    return new SharedContentRows({
      media: isAppend ? [...current.media, ...incoming.media] : incoming.media,
      files: current.files,
      links: current.links,
      audios: current.audios,
      voices: current.voices
    });
  }
  if (tab === SHARED_TAB_FILES) {
    return new SharedContentRows({
      media: current.media,
      files: isAppend ? [...current.files, ...incoming.files] : incoming.files,
      links: current.links,
      audios: current.audios,
      voices: current.voices
    });
  }
  if (tab === SHARED_TAB_AUDIO) {
    return new SharedContentRows({
      media: current.media,
      files: current.files,
      links: current.links,
      audios: isAppend ? [...current.audios, ...incoming.audios] : incoming.audios,
      voices: current.voices
    });
  }
  if (tab === SHARED_TAB_VOICE) {
    return new SharedContentRows({
      media: current.media,
      files: current.files,
      links: current.links,
      audios: current.audios,
      voices: isAppend ? [...current.voices, ...incoming.voices] : incoming.voices
    });
  }
  return new SharedContentRows({
    media: current.media,
    files: current.files,
    links: isAppend ? [...current.links, ...incoming.links] : incoming.links,
    audios: current.audios,
    voices: current.voices
  });
}

export interface SharedContentSearchDeps {
  /** = AccountScope.request；注入而非传 scope，是为了让本文件不碰账号生命周期。 */
  readonly request: (name: string, payload: TdWireObject) => Result<TdPendingRequest, AppError>;
  /** 缩略图本地路径查询；未就绪时由调用方顺带登记下载与订阅（媒体 Tab 只有一张图，值得预热）。 */
  readonly localPathOf: (fileId: number) => string | null;
  /**
   * 音频/语音本地路径「只看不拉」查询（SHARED-AUDIO）：纯 FileRegistry 命中检查。
   * 不能复用 `localPathOf`：那会在解析阶段给整页音频逐个登记下载，一屏 20 条
   * 就是 20 个音频文件同时下，用户只是翻了个 Tab。真正要听哪条由点按触发下载。
   */
  readonly audioLocalPathOf: (fileId: number) => string | null;
  /**
   * 语音行的发送者昵称（SHARED-AUDIO）：由调用方查自己的 UserRegistry。
   * 查不到时返回空串，交给 `voiceTitleOf`（自己发的显「我」，其余由组件回落「语音消息」）。
   * 晚到的昵称不回灌，因为共享语音的会话成员必然已在本页成员表里，miss 只发生在极旧的缓存上。
   */
  readonly senderNameOf?: (userId: number) => string;
  readonly logger: Logger;
  readonly tag: string;
}

export class SharedContentSearcher {
  private readonly request: (name: string, payload: TdWireObject) => Result<TdPendingRequest, AppError>;
  private readonly localPathOf: (fileId: number) => string | null;
  private readonly audioLocalPathOf: (fileId: number) => string | null;
  private readonly senderNameOf: (userId: number) => string;
  private readonly logger: Logger;
  private readonly tag: string;
  private readonly nextOffsets: Map<number, number> = new Map();
  private destroyed: boolean = false;

  constructor(deps: SharedContentSearchDeps) {
    this.request = deps.request;
    this.localPathOf = deps.localPathOf;
    this.audioLocalPathOf = deps.audioLocalPathOf;
    this.senderNameOf = deps.senderNameOf !== undefined ? deps.senderNameOf : (_userId: number): string => '';
    this.logger = deps.logger;
    this.tag = deps.tag;
  }

  /** 页面销毁后回包只丢弃，不再回调（调用方的 dispatch/listener 已失效）。 */
  destroy(): void {
    this.destroyed = true;
    this.nextOffsets.clear();
  }

  /** 换会话时清掉续页游标：旧 chatId 的 next_from_message_id 对新会话无意义。 */
  resetOffsets(): void {
    this.nextOffsets.clear();
  }

  search(
    tab: number,
    chatId: number,
    isLoadMore: boolean,
    onDone: (page: SharedContentPage) => void
  ): void {
    if (this.destroyed) {
      return;
    }
    const filter: TdSearchMessagesFilter | null = sharedFilterOf(tab);
    if (filter === null) {
      onDone(SharedContentPage.failed(tab));
      return;
    }
    const req: SearchChatMessages = new SearchChatMessages();
    req.chat_id = chatId;
    req.query = '';
    req.from_message_id = isLoadMore ? this.offsetOf(tab) : 0;
    req.offset = 0;
    req.limit = SHARED_PAGE_LIMIT;
    req.sender_id = null;
    req.topic_id = null;
    req.filter = filter;

    const res: Result<TdPendingRequest, AppError> =
      this.request('searchChatMessages', encodeSearchChatMessages(req) as TdWireObject);
    this.logger.info(this.tag, 'search_shared_content',
      `tab=${tab},chatId=${chatId},fromMessageId=${req.from_message_id},isLoadMore=${isLoadMore},accepted=${res.ok}`);
    if (res.ok) {
      const self: SharedContentSearcher = this;
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        if (self.destroyed) {
          return;
        }
        if (out.err) {
          self.logger.logError(self.tag, out.error);
          onDone(SharedContentPage.failed(tab));
          return;
        }
        if (out.ok) {
          const found: FoundChatMessages | null = decodeFoundChatMessages(out.value as TdJsonRaw);
          if (found === null) {
            onDone(SharedContentPage.failed(tab));
            return;
          }
          onDone(self.pageOf(tab, found));
        }
      }).catch((): void => {
      });
      return;
    }
    if (res.err) {
      this.logger.logError(this.tag, res.error);
    }
    onDone(SharedContentPage.failed(tab));
  }

  private pageOf(tab: number, found: FoundChatMessages): SharedContentPage {
    const nextFromId: number = found.next_from_message_id;
    const hasMore: boolean = nextFromId > 0 && found.messages.length > 0;
    this.nextOffsets.set(tab, nextFromId);

    if (tab === SHARED_TAB_MEDIA) {
      const media: SharedMediaItem[] = [];
      let placeholders: number = 0;
      for (let i = 0; i < found.messages.length; i++) {
        const item: SharedMediaItem | null =
          sharedMediaItemOf(found.messages[i].content, this.localPathOf, found.messages[i].date);
        if (item !== null) {
          // 占位=「缩略图还没落盘」，含 fileId 有值但本地路径没回来的下载中态；
          // 只统计 fileId === 0 会漏掉这一整类，日志上看不出页面为什么是灰块。
          if (item.localPath === null) {
            placeholders++;
          }
          media.push(item);
        }
      }
      this.logger.info(this.tag, 'shared_media_ok',
        `page=${found.messages.length},kept=${media.length},placeholder=${placeholders},hasMore=${hasMore}`);
      return new SharedContentPage(tab, true, new SharedContentRows({ media: media }), hasMore);
    }

    if (tab === SHARED_TAB_FILES) {
      const files: SharedFileItem[] = [];
      for (let i = 0; i < found.messages.length; i++) {
        const item: SharedFileItem | null = fileItemOf(found.messages[i]);
        if (item !== null) {
          files.push(item);
        }
      }
      this.logger.info(this.tag, 'shared_files_ok', `pageCount=${files.length},hasMore=${hasMore}`);
      return new SharedContentPage(tab, true, new SharedContentRows({ files: files }), hasMore);
    }

    if (tab === SHARED_TAB_AUDIO || tab === SHARED_TAB_VOICE) {
      const items: SharedAudioItem[] = [];
      for (let i = 0; i < found.messages.length; i++) {
        const msg: Message = found.messages[i];
        const item: SharedAudioItem | null = tab === SHARED_TAB_AUDIO
          ? audioItemOf(msg, this.audioLocalPathOf)
          : voiceItemOf(msg, this.audioLocalPathOf, this.senderNameOf);
        if (item !== null) {
          items.push(item);
        }
      }
      this.logger.info(this.tag, tab === SHARED_TAB_AUDIO ? 'shared_audio_ok' : 'shared_voice_ok',
        `page=${found.messages.length},kept=${items.length},hasMore=${hasMore}`);
      return new SharedContentPage(tab, true,
        new SharedContentRows(tab === SHARED_TAB_AUDIO ? { audios: items } : { voices: items }), hasMore);
    }

    const links: SharedLinkItem[] = [];
    for (let i = 0; i < found.messages.length; i++) {
      const item: SharedLinkItem | null = linkItemOf(found.messages[i].content, found.messages[i].date);
      if (item !== null) {
        links.push(item);
      }
    }
    this.logger.info(this.tag, 'shared_links_ok', `pageCount=${links.length},hasMore=${hasMore}`);
    return new SharedContentPage(tab, true, new SharedContentRows({ links: links }), hasMore);
  }

  private offsetOf(tab: number): number {
    const known: number | undefined = this.nextOffsets.get(tab);
    return known !== undefined ? known : 0;
  }
}

function sharedFilterOf(tab: number): TdSearchMessagesFilter | null {
  if (tab === SHARED_TAB_MEDIA) {
    return new SearchMessagesFilterPhotoAndVideo();
  }
  if (tab === SHARED_TAB_FILES) {
    return new SearchMessagesFilterDocument();
  }
  if (tab === SHARED_TAB_LINKS) {
    return new SearchMessagesFilterUrl();
  }
  if (tab === SHARED_TAB_AUDIO) {
    return new SearchMessagesFilterAudio();
  }
  if (tab === SHARED_TAB_VOICE) {
    return new SearchMessagesFilterVoiceNote();
  }
  return null;
}
