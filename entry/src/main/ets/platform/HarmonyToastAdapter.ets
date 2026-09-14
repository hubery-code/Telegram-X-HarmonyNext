/**
 * entry — HarmonyOS 系统轻提示适配器（ARCH-001 / P1-ARCH-001）。
 *
 * 包装 @kit.ArkUI.promptAction.showToast，实现 platform/ports 的 ToastPort 契约。
 */

import { promptAction } from '@kit.ArkUI';
import { ToastPort } from '@tgx/platform-ports';

export class HarmonyToastAdapter implements ToastPort {
  showToast(message: string, durationMs: number = 2000): void {
    try {
      promptAction.showToast({
        message: message,
        duration: durationMs
      });
    } catch (_err) {
      // 容错处理：在无窗口/背景状态下避免崩溃
    }
  }
}
