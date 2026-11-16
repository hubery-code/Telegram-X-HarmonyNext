/**
 * core/domain — 建群 / 建频道请求投影（GROUP-CREATE-101）。
 *
 * 两条 TDLib 请求的组装与本地校验收口在这里（对齐 MessageProjection 的
 * createForumTopic 同款约定：本端先拦形状错误，请求级失败经 promise 透传）：
 * - createNewBasicGroupChat { user_ids(可空), title(1-128) } → 回 Chat（basicGroup）；
 * - createNewSupergroupChat { title(1-128), is_forum=false, is_channel, description }
 *   → 回 Chat（supergroup / channel，is_channel=true 建频道）。
 *
 * 校验纯函数 validateGroupTitle 单独导出：feature 层的 reducer 在「提交前」
 * 也用它本地拦截（标题空/超长不出请求），两边共享同一条口径。
 *
 * 回包 `Chat` 的解码归调用方（协调器）——decodeChat 已在协调器侧广泛使用，
 * 本投影只负责「把请求发出去」，不吞回包。
 */

import {
  CreateNewBasicGroupChat,
  CreateNewSupergroupChat,
  encodeCreateNewBasicGroupChat,
  encodeCreateNewSupergroupChat
} from '@tgx/core-td-api-generated';
import { AccountScope } from '@tgx/core-account';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { Result, AppError, AppErrors, err } from '@tgx/core-common';

/**
 * TDLib 协议上限：标题 1-128 字符（createNewBasicGroupChat /
 * createNewSupergroupChat 的 title 字段文档口径）。
 */
export const GROUP_TITLE_MAX_LENGTH: number = 128;

/**
 * trim 后校验标题（1-128 字）。合法返回 null；非法返回 AppError，
 * 文案走技术串（调用方 UI 用自己的 Lang key 呈现，这里只承载错误类别）。
 */
export function validateGroupTitle(title: string): AppError | null {
  const trimmed: string = title.trim();
  if (trimmed.length === 0) {
    return AppErrors.parameter('missing', 'title', 'group title is empty');
  }
  if (trimmed.length > GROUP_TITLE_MAX_LENGTH) {
    return AppErrors.parameter(
      'invalid',
      'title',
      `group title exceeds ${GROUP_TITLE_MAX_LENGTH} characters`
    );
  }
  return null;
}

/** 建群/建频道请求发送器（单账号作用域）。 */
export class GroupChatCreator {
  private readonly scope: AccountScope;

  constructor(scope: AccountScope) {
    this.scope = scope;
  }

  /**
   * 建普通群组（createNewBasicGroupChat）。
   * userIds 可为空数组（TDLib 允许先建空群再拉人），入参复制一份防外部可变引用。
   */
  createBasicGroup(title: string, userIds: number[]): Result<TdPendingRequest, AppError> {
    const invalid: AppError | null = validateGroupTitle(title);
    if (invalid !== null) {
      return err(invalid);
    }
    const req: CreateNewBasicGroupChat = new CreateNewBasicGroupChat();
    req.title = title.trim();
    req.user_ids = userIds.slice();
    return this.scope.request(
      'createNewBasicGroupChat',
      encodeCreateNewBasicGroupChat(req) as TdWireObject
    );
  }

  /**
   * 建超级群组 / 频道（createNewSupergroupChat）。
   * isChannel=true 建频道、false 建超级群组；is_forum 本端 v1 恒 false
   * （论坛群创建不在本包范围）；description 可选，trim 后随请求发送。
   */
  createSupergroup(title: string, isChannel: boolean, description: string = ''): Result<TdPendingRequest, AppError> {
    const invalid: AppError | null = validateGroupTitle(title);
    if (invalid !== null) {
      return err(invalid);
    }
    const req: CreateNewSupergroupChat = new CreateNewSupergroupChat();
    req.title = title.trim();
    req.is_forum = false;
    req.is_channel = isChannel;
    req.description = description.trim();
    return this.scope.request(
      'createNewSupergroupChat',
      encodeCreateNewSupergroupChat(req) as TdWireObject
    );
  }
}
