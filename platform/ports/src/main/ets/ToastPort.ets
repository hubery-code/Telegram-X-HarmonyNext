/**
 * platform/ports — 纯 ArkTS 轻提示抽象契约（ARCH-001 / P1-ARCH-001）。
 *
 * 消除协调器层对 @kit.ArkUI.promptAction 的直接依赖，
 * 使轻提示在脱机单测或 headless 场景下不会因缺少 UI 宿主而抛出异常。
 */

export interface ToastPort {
  /** 弹出一条轻提示信息。 */
  showToast(message: string, durationMs?: number): void;
}
