/**
 * platform/ports — 内存型 Fake 轻提示实现（ARCH-001）。
 *
 * 记录所有提示内容供单元测试断言，无需任何系统 ArkUI Kit。
 */

import { ToastPort } from '../ToastPort';

export interface RecordedToast {
  readonly message: string;
  readonly durationMs: number;
}

export class FakeToast implements ToastPort {
  readonly toasts: RecordedToast[] = [];

  showToast(message: string, durationMs: number = 2000): void {
    this.toasts.push({ message, durationMs });
  }

  get lastToast(): string | null {
    if (this.toasts.length === 0) {
      return null;
    }
    return this.toasts[this.toasts.length - 1].message;
  }

  clear(): void {
    this.toasts.length = 0;
  }
}
