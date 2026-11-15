/**
 * core/domain — Instant View 请求投影（IV-101，UI 待接）。
 *
 * 与 MessageProjection 同构但**不绑 chatId**：Instant View 按 URL 取页，
 * 构造只需账号级 AccountScope（gateway + clientId + 取消域都在 scope 上）。
 *
 * - fetchInstantView(url)：组 getWebPageInstantView 请求并登记取消域；
 *   url 空 / 非 http(s) 协议在本地判 parameter 错误，不发请求；
 *   返回的 TdPendingRequest 由调用方经 promise 拿到 TDLib JSON 回包后，
 *   交给 projectInstantView 解码成阅读器页模型。
 * - projectInstantView(json)：decodeWebPageInstantView + 块树投影（纯函数）。
 *
 * 不动 MessageProjection —— 网页预览（getPage）与 Instant View 是两条链路。
 *
 * 注意：本模块不 import ArkUI / Kit（与 core 层约束一致）。
 */

import {
  GetWebPageInstantView,
  encodeGetWebPageInstantView,
  WebPageInstantView,
  decodeWebPageInstantView,
  TdJsonRaw
} from '@tgx/core-td-api-generated';
import { AccountScope } from '@tgx/core-account';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { Result, AppError, AppErrors, err } from '@tgx/core-common';
import { InstantViewPage, projectInstantViewPage } from './InstantViewModel';

export class WebPageProjection {
  private readonly scope: AccountScope;

  constructor(scope: AccountScope) {
    this.scope = scope;
  }

  /**
   * 取指定 URL 的 Instant View（TDLib：getWebPageInstantView）。
   *
   * 参数校验先行：空 url 判 parameter/missing；非 http(s) 判 parameter/invalid，
   * 两种情况都不发起请求（t.me 深链、tg:// 等内部链接不进 Instant View 链路，
   * 由调用方先经 internalLinkType 分流）。
   *
   * @param url 网页地址（http/https）
   * @param onlyLocal true = 只取本地已缓存的 Instant View，不发网络请求
   * @returns ok(TdPendingRequest) 由调用方等待回包后交给 projectInstantView；
   *          err(AppError kind='parameter') 时请求未发出
   */
  fetchInstantView(url: string, onlyLocal: boolean = false): Result<TdPendingRequest, AppError> {
    const trimmed: string = url.trim();
    if (trimmed.length === 0) {
      return err(AppErrors.parameter('missing', 'url', 'web page url is empty'));
    }
    const lower: string = trimmed.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return err(AppErrors.parameter('invalid', 'url', 'instant view url must be http(s)'));
    }
    const req: GetWebPageInstantView = new GetWebPageInstantView();
    req.url = trimmed;
    req.only_local = onlyLocal;
    return this.scope.request('getWebPageInstantView', encodeGetWebPageInstantView(req) as TdWireObject);
  }

  /**
   * TDLib JSON 回包 → 阅读器页模型（纯投影，无 IO）。
   * 解码失败（形状不对/为 null）返回 null，调用方按「无 Instant View」降级。
   */
  projectInstantView(json: TdJsonRaw): InstantViewPage | null {
    const instantView: WebPageInstantView | null = decodeWebPageInstantView(json);
    if (instantView === null) {
      return null;
    }
    return projectInstantViewPage(instantView);
  }
}
