/**
 * entry — HarmonyOS 系统剪贴板适配器（ARCH-001 / P1-ARCH-001）。
 *
 * 包装 @kit.BasicServicesKit.pasteboard，实现 platform/ports 的 ClipboardPort 契约。
 */

import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { ClipboardPort } from '@tgx/platform-ports';

export class HarmonyClipboardAdapter implements ClipboardPort {
  async setPlainText(text: string): Promise<void> {
    try {
      const pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
    } catch (err) {
      // 记录错误但不抛出崩溃异常
      const bErr: BusinessError = err as BusinessError;
      throw new Error(`HarmonyClipboardAdapter.setPlainText failed: ${bErr.message ?? String(err)}`);
    }
  }

  async getPlainText(): Promise<string | null> {
    try {
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const hasData: boolean = await systemPasteboard.hasData();
      if (!hasData) {
        return null;
      }
      const pasteData: pasteboard.PasteData = await systemPasteboard.getData();
      return pasteData.getPrimaryText() ?? null;
    } catch (_err) {
      return null;
    }
  }
}
