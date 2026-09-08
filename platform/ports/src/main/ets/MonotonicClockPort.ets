/**
 * platform/ports — MonotonicClockPort 单调时钟契约（PLAT-001）。
 *
 * 背景：纯 ArkTS 无可移植的单调时钟 API（core/common 的 SystemClock.monotonicMillis
 * 以 Date.now() 近似，见 core/common README 交接说明）。需要严格单调语义的路径
 * （超时、事件排序、序列号）必须经本端口注入生产实现。
 *
 * 语义约定：
 * - nowMillis() 单调不减：任意两次调用的后值 >= 前值，与系统时间回拨无关；
 * - 不因系统休眠语义而回退（实现文档须声明对 suspend/resume 的处理）；
 * - 时钟原点未定义（不要求从 0 开始），调用方只做差值比较；
 * - 纯查询无失败路径，故不包 Result。
 */

export interface MonotonicClockPort {
  /** 单调不减的毫秒时间戳。 */
  nowMillis(): number;
}
