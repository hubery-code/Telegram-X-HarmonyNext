/**
 * platform/ports — 内存型 Fake 触感实现（CONTACT-103）。
 *
 * 记录 vibrateShort 调用次数供单元测试断言边沿触发，无需真机马达；
 * 同时作为协调器未注入真实端口时的缺省兜底（与 FakeToast 等同一套约定）。
 */

import { HapticFeedbackPort } from '../HapticFeedbackPort';

export class FakeHapticFeedback implements HapticFeedbackPort {
  /** 累计触发次数。 */
  count: number = 0;

  vibrateShort(): void {
    this.count++;
  }

  clear(): void {
    this.count = 0;
  }
}
