/**
 * platform/tdcore-bridge — TdCoreBridge 生产适配器（BRG-006）。
 *
 * 把 libtdcore_napi.so 的 Node-API 导出包装为 core/td_gateway 的
 * TdNativeBridgeLike 契约。替代 entry 内临时 TdBridge.ts（BRG-003/004 雏形）。
 *
 * 契约对照（§5.2 TdNativeBridge）：
 * - getVersion / execute / createClient / send：同步直透
 * - subscribeUpdates：native sink 为 5 个位置参数（含 sequence: string），
 *   契约 sink 为 (TdNativeEvent) => void。适配器把位置参数组装为事件对象，
 *   sequence 保持十进制 string（64 位安全，不经 JS number/bigint）。
 * - unsubscribe：幂等直透（native 侧对未知 id 安全）
 * - getMetrics：直透（字段名一致）
 *
 * 生命周期：closeClient/shutdown 不在本接口（CORE-002 刻意最小化），
 * 由 AccountScope（CORE-003）层保证。
 *
 * 可注入性：构造器接受可选 nativeModule，缺省用模块级 import。
 * 单测注入 FakeNativeModule 即可不依赖 .so 验证契约语义。
 */

import native from 'libtdcore_napi.so';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEvent,
  TdNativeEventSink
} from '@tgx/td-gateway';

export type TdEventSinkRaw = (
  schemaVersion: number,
  clientId: number,
  sequence: string,
  payloadUtf8: string,
  receivedAtMonotonicMs: number
) => void;

export interface TdCoreNativeModule {
  getVersion(): string;
  execute(requestUtf8: string): string | null;
  createClient(): number;
  send(clientId: number, requestUtf8: string): void;
  subscribeUpdates(sink: TdEventSinkRaw): number;
  unsubscribe(subscriptionId: number): void;
  getMetrics(): TdNativeBridgeMetrics;
}

const tdcoreNative: TdCoreNativeModule = native as TdCoreNativeModule;

export class TdCoreBridge implements TdNativeBridgeLike {
  private readonly nativeModule: TdCoreNativeModule;

  constructor(nativeModule?: TdCoreNativeModule) {
    this.nativeModule = nativeModule !== undefined ? nativeModule : tdcoreNative;
  }

  getVersion(): string {
    return this.nativeModule.getVersion();
  }

  execute(requestUtf8: string): string | null {
    return this.nativeModule.execute(requestUtf8);
  }

  createClient(): number {
    return this.nativeModule.createClient();
  }

  send(clientId: number, requestUtf8: string): void {
    this.nativeModule.send(clientId, requestUtf8);
  }

  subscribeUpdates(sink: TdNativeEventSink): number {
    const raw: TdEventSinkRaw = (
      schemaVersion: number,
      clientId: number,
      sequence: string,
      payloadUtf8: string,
      receivedAtMonotonicMs: number
    ): void => {
      const event: TdNativeEvent = {
        schemaVersion: schemaVersion,
        clientId: clientId,
        sequence: sequence,
        payloadUtf8: payloadUtf8,
        receivedAtMonotonicMs: receivedAtMonotonicMs
      };
      sink(event);
    };
    return this.nativeModule.subscribeUpdates(raw);
  }

  unsubscribe(subscriptionId: number): void {
    this.nativeModule.unsubscribe(subscriptionId);
  }

  getMetrics(): TdNativeBridgeMetrics {
    return this.nativeModule.getMetrics();
  }
}
