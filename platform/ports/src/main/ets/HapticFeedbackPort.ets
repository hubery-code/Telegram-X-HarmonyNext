/**
 * platform/ports — 触感反馈抽象契约（CONTACT-103 / ARCH-001）。
 *
 * 消除 feature 层对 @kit.SensorServiceKit vibrator 的直接依赖，使拖拽换段
 * 触感在无马达 / 未授权 / headless 环境下降级为 no-op。真实实现由 entry
 * 装配层注入（HarmonyHapticFeedbackAdapter，@ohos.vibrator 预置效果）。
 */

export interface HapticFeedbackPort {
  /**
   * 触发一次短促轻触感（对齐 Android HapticFeedbackConstants.CLOCK_TICK，
   * 用于联系人索引条拖拽划过新分段的确认反馈）。
   *
   * 实现内部必须自兜底：无振动器 / 无权限 / 能力不支持时静默返回（至多记日志），
   * 不得向调用方抛出——触感是增强体验，失败不能影响拖动换段主流程。
   */
  vibrateShort(): void;
}
