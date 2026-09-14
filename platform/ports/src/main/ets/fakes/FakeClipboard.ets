/**
 * platform/ports — 内存型 Fake 剪贴板实现（ARCH-001）。
 *
 * 用于单元测试与脱机场景，无需任何系统 Kit。
 */

import { ClipboardPort } from '../ClipboardPort';

export class FakeClipboard implements ClipboardPort {
  private currentText: string | null = null;
  /** 写入计数器（用于测试验证）。 */
  setCount: number = 0;
  /** 读取计数器（用于测试验证）。 */
  getCount: number = 0;

  async setPlainText(text: string): Promise<void> {
    this.currentText = text;
    this.setCount += 1;
  }

  async getPlainText(): Promise<string | null> {
    this.getCount += 1;
    return this.currentText;
  }

  clear(): void {
    this.currentText = null;
    this.setCount = 0;
    this.getCount = 0;
  }
}
