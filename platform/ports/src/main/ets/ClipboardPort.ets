/**
 * platform/ports — 纯 ArkTS 剪贴板抽象契约（ARCH-001 / P1-ARCH-001）。
 *
 * 消除协调器层对 @kit.BasicServicesKit.pasteboard 的直接依赖，
 * 使剪贴板操作在跨端、脱机单测或 mock 场景下完全可替换。
 */

export interface ClipboardPort {
  /** 将纯文本写入系统剪贴板。 */
  setPlainText(text: string): Promise<void>;

  /** 从系统剪贴板读取纯文本。剪贴板为空或非文本时返回 null。 */
  getPlainText(): Promise<string | null>;
}
