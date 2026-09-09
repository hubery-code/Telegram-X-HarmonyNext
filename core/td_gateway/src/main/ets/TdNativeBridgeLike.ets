/**
 * core/td_gateway — TdNativeBridgeLike：Node-API 桥的最小抽象（CORE-002）。
 *
 * 计划 §5.2「Node-API 最小契约」的 ArkTS 侧镜像。core/td_gateway 只面向
 * 本接口编程：生产实现由 platform/native 适配层把 libtdcore_napi.so 的
 * 导出包成此接口（entry 的临时 TdBridge 即其雏形，届时迁移），
 * 单测用手写 FakeBridge（见 src/test/FakeBridge.ets）。
 *
 * 线程与顺序契约（§5.4）：
 * - 所有方法在 ArkTS 线程调用；事件经官方线程安全回调（TSFN）回到 ArkTS 线程；
 * - native 层对每个 client 的 sequence 单调递增，ArkTS 侧事件按 sequence 严格有序；
 * - 64 位值（sequence）以十进制 string 传递，不经过 JS number/bigint；
 * - clientId 为 TDLib 全局 int32 id，用 number 承载（调用方需自行校验范围）。
 *
 * 生命周期：closeClient/shutdown 属于 AccountScope（CORE-003）扩展点，
 * 本接口刻意保持最小（对照 §5.2 示意中的 closeClient 幂等约束，
 * 由实现方在 AccountScope 层保证）。
 */

/** native → ArkTS 事件。sequence 为十进制字符串（64 位单调序列）。 */
export interface TdNativeEvent {
  readonly schemaVersion: number;
  readonly clientId: number;
  readonly sequence: string;
  readonly payloadUtf8: string;
  readonly receivedAtMonotonicMs: number;
}

export type TdNativeEventSink = (event: TdNativeEvent) => void;

/** native 侧有界队列/派发器的健康指标（透传，语义由 BRG 层定义）。 */
export interface TdNativeBridgeMetrics {
  readonly queueSize: number;
  readonly overflowWaitCount: number;
  readonly droppedCount: number;
  readonly eventsForwarded: number;
  readonly subscriptions: number;
  readonly dispatcherRunning: boolean;
}

/**
 * 最小桥抽象。send/execute 的载荷为 TDLib JSON 文本（utf8）；
 * createClient 返回 TDLib 全局 int32 client id。
 */
export interface TdNativeBridgeLike {
  getVersion(): string;
  createClient(): number;
  send(clientId: number, requestUtf8: string): void;
  execute(requestUtf8: string): string | null;
  subscribeUpdates(sink: TdNativeEventSink): number;
  unsubscribe(subscriptionId: number): void;
  getMetrics(): TdNativeBridgeMetrics;
}
