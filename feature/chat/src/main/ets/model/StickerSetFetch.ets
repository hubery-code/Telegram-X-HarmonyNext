/**
 * feature/chat — 整包取数失败的分类（STICKER-FETCH-102）。
 *
 * 为什么分类而不是把 TDLib 原文印出来：`AppError` 刻意把原文只关在 `cause` 里
 * （别的请求的原文可能带手机号、沙盒路径、mtproto 凭证），日志只允许落一个稳定 key。
 *
 * 这一层存在的唯一理由是 **同一个数字码 406 有两个来源，而修法完全不同**：
 *  - 服务端真的回 `STICKERSET_INVALID` —— 这一包在当前会话解析不出来；
 *  - TDLib **本地造的** 406：`NetQueryDispatcher.cpp:102` 把服务端的
 *    `420 FROZEN_METHOD_INVALID` 重写成 `Status::Error(406, message)`。
 *    「方法被冻」说的是这个 api_id/会话不被允许调这个方法，跟这一包存不存在无关。
 * 分不开它们，就会把配置问题当成服务端问题 —— 本仓上一轮正是这么定案的。
 *
 * 另一条只有本地来源：`StickersManager.cpp:4970` 对从未见过的 set_id 合成
 * `400 Sticker set not found` —— 那是「TDLib 压根不认识这个 id」，不是网络否决。
 */

import { AppError } from '@tgx/core-common';

export type StickerSetFetchFailure =
  | 'stickerSetInvalid'
  | 'frozenMethod'
  | 'setNotFound'
  | 'other';

/** 原文（只用来匹配关键字）：`cause` 是我们自己写的 `"<code>:<TDLib 原文>"`。 */
function failureHaystack(error: AppError): string {
  const cause: string | undefined = error.cause;
  const raw: string = cause !== undefined && cause.length > 0 ? cause : error.message;
  const colon: number = raw.indexOf(':');
  const text: string = colon === -1 ? raw : raw.substring(colon + 1);
  return text.toUpperCase();
}

/** TDLib 数字错误码（0 = 拿不到）；数字是我们自己拼进 cause 的，不是原文。 */
function tdlibCodeOf(error: AppError): number {
  if (error.kind !== 'tdlib') {
    return 0;
  }
  const cause: string | undefined = error.cause;
  if (cause === undefined) {
    return 0;
  }
  const colon: number = cause.indexOf(':');
  const head: string = colon === -1 ? cause : cause.substring(0, colon);
  const code: number = Number.parseInt(head, 10);
  return Number.isNaN(code) ? 0 : code;
}

export function classifyStickerSetFetchFailure(error: AppError): StickerSetFetchFailure {
  const text: string = failureHaystack(error);
  if (text.indexOf('FROZEN_METHOD_INVALID') >= 0) {
    return 'frozenMethod';
  }
  if (text.indexOf('STICKERSET_INVALID') >= 0) {
    return 'stickerSetInvalid';
  }
  if (text.indexOf('STICKER SET NOT FOUND') >= 0 || text.indexOf('STICKERSET_NOT_FOUND') >= 0) {
    return 'setNotFound';
  }
  return 'other';
}

/** 日志用的安全串：只有数字码与分类，没有原文。 */
export function stickerSetFetchFailureLogKey(error: AppError): string {
  return `code=${tdlibCodeOf(error)} reason=${classifyStickerSetFetchFailure(error)}`;
}
