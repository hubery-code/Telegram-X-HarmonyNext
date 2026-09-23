/**
 * feature/profile — 共享内容分页拉取（CHATPROF-SHARED）。
 *
 * searchChatMessages 的构造（空 query + 按 Tab 选过滤器 + from_message_id 续页）、
 * foundChatMessages 解码、逐 Tab 映射条目与 `next_from_message_id` 记账全部收在这里：
 * 用户资料页与群/频道资料页拉的是同一种数据，两处各写一份的话，「hasMore 怎么判」
 * 「空页算不算到底」这类规则会先分叉，页面表现就开始不一致。
 *
 * 只注入一个 `request` 端口（= AccountScope.request）与一个 `localPathOf`
 * （各自查自己的 FileRegistry 并登记缩略图订阅），因此 Kit-free、可单测。
 */

import { AppError, Result } from '@tgx/core-common';
import { Logger } from '@tgx/observability';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import {
  FoundChatMessages,
  SearchChatMessages,
  SearchMessagesFilterDocument,
  SearchMessagesFilterPhotoAndVideo,
  SearchMessagesFilterUrl,
  TdSearchMessagesFilter,
  decodeFoundChatMessages,
  encodeSearchChatMessages,
  TdJsonRaw
} from '@tgx/core-td-api-generated';
import { SharedFileItem, SharedLinkItem, SharedMediaItem } from '../contract/SharedContentItems';
import { fileItemOf, linkItemOf, sharedMediaItemOf } from './SharedContentFormat';

/** 共享内容每页拉取条数（对齐 TGX shared media 默认页大小）。 */
export const SHARED_PAGE_LIMIT: number = 20;

/** 共享内容 Tab：0 媒体 / 1 文件 / 2 链接。群组 Tab 走 getGroupsInCommon，不在本文件。 */
export const SHARED_TAB_MEDIA: number = 0;
export const SHARED_TAB_FILES: number = 1;
export const SHARED_TAB_LINKS: number = 2;

/** 一页结果：只填本次请求 Tab 对应的数组，其余保持空。 */
export class SharedContentPage {
  readonly tab: number;
  /** false = 请求失败/解码失败；调用方退回错误态，不能当成「没有内容」。 */
  readonly loaded: boolean;
  readonly media: SharedMediaItem[];
  readonly files: SharedFileItem[];
  readonly links: SharedLinkItem[];
  readonly hasMore: boolean;

  constructor(
    tab: number,
    loaded: boolean,
    media: SharedMediaItem[],
    files: SharedFileItem[],
    links: SharedLinkItem[],
    hasMore: boolean
  ) {
    this.tab = tab;
    this.loaded = loaded;
    this.media = media;
    this.files = files;
    this.links = links;
    this.hasMore = hasMore;
  }

  static failed(tab: number): SharedContentPage {
    return new SharedContentPage(tab, false, [], [], [], false);
  }
}

export interface SharedContentSearchDeps {
  /** = AccountScope.request；注入而非传 scope，是为了让本文件不碰账号生命周期。 */
  readonly request: (name: string, payload: TdWireObject) => Result<TdPendingRequest, AppError>;
  /** 缩略图/文件本地路径查询；未就绪时由调用方顺带登记下载与订阅。 */
  readonly localPathOf: (fileId: number) => string | null;
  readonly logger: Logger;
  readonly tag: string;
}

export class SharedContentSearcher {
  private readonly request: (name: string, payload: TdWireObject) => Result<TdPendingRequest, AppError>;
  private readonly localPathOf: (fileId: number) => string | null;
  private readonly logger: Logger;
  private readonly tag: string;
  private readonly nextOffsets: Map<number, number> = new Map();
  private destroyed: boolean = false;

  constructor(deps: SharedContentSearchDeps) {
    this.request = deps.request;
    this.localPathOf = deps.localPathOf;
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
          sharedMediaItemOf(found.messages[i].content, this.localPathOf);
        if (item !== null) {
          if (item.fileId === 0) {
            placeholders++;
          }
          media.push(item);
        }
      }
      this.logger.info(this.tag, 'shared_media_ok',
        `page=${found.messages.length},kept=${media.length},placeholder=${placeholders},hasMore=${hasMore}`);
      return new SharedContentPage(tab, true, media, [], [], hasMore);
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
      return new SharedContentPage(tab, true, [], files, [], hasMore);
    }

    const links: SharedLinkItem[] = [];
    for (let i = 0; i < found.messages.length; i++) {
      const item: SharedLinkItem | null = linkItemOf(found.messages[i].content);
      if (item !== null) {
        links.push(item);
      }
    }
    this.logger.info(this.tag, 'shared_links_ok', `pageCount=${links.length},hasMore=${hasMore}`);
    return new SharedContentPage(tab, true, [], [], links, hasMore);
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
  return null;
}
