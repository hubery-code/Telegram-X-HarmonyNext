/**
 * feature/_template — 示例 feature：CounterEffect（UI-003）。
 *
 * Effect 是一次性副作用的「描述」，不是执行：
 * - PersistCount：由 EffectHandler 真正发起持久化；requestId / savedAtMillis
 *   由 reducer 从 env.ids / env.clock 注入，测试可精确断言；
 * - ShowToast：messageKey 是本地化 key，禁止携带拼接好的用户文案。
 */

import { Effect } from '../contract/UiState';

export class PersistCount implements Effect {
  readonly kind: 'persistCount' = 'persistCount';
  readonly requestId: string;
  readonly count: number;
  readonly savedAtMillis: number;

  constructor(requestId: string, count: number, savedAtMillis: number) {
    this.requestId = requestId;
    this.count = count;
    this.savedAtMillis = savedAtMillis;
  }
}

export class ShowToast implements Effect {
  readonly kind: 'showToast' = 'showToast';
  readonly messageKey: string;

  constructor(messageKey: string) {
    this.messageKey = messageKey;
  }
}

export type CounterEffect = PersistCount | ShowToast;
