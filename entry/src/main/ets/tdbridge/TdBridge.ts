// BRG-003/004 最小封装：libtdcore_napi.so -> 类型化 TdBridge。
// 注意：正式 facade 属于 core/td_gateway（后续工作包），本文件是 entry
// 内的临时验证封装，届时迁移/删除。

import native from 'libtdcore_napi.so';

export interface TdNativeEvent {
  schemaVersion: number;
  clientId: number;
  // 十进制字符串转 bigint：TDLib 业务 ID 与单调 sequence 不走 JS number。
  sequence: bigint;
  payloadUtf8: string;
  receivedAtMonotonicMs: number;
}

export interface TdBridgeMetrics {
  queueSize: number;
  overflowWaitCount: number;
  droppedCount: number;
  eventsForwarded: number;
  subscriptions: number;
  dispatcherRunning: boolean;
}

type TdEventSinkRaw = (schemaVersion: number, clientId: number, sequence: string,
  payloadUtf8: string, receivedAtMonotonicMs: number) => void;

interface TdCoreNativeModule {
  getVersion(): string;
  execute(requestUtf8: string): string | null;
  createClient(): number;
  send(clientId: number, requestUtf8: string): void;
  subscribeUpdates(sink: TdEventSinkRaw): number;
  unsubscribe(subscriptionId: number): void;
  getMetrics(): TdBridgeMetrics;
}

const tdcore: TdCoreNativeModule = native as TdCoreNativeModule;

export class TdBridge {
  static getVersion(): string {
    return tdcore.getVersion();
  }

  static execute(requestUtf8: string): string | null {
    return tdcore.execute(requestUtf8);
  }

  static createClient(): number {
    return tdcore.createClient();
  }

  static send(clientId: number, requestUtf8: string): void {
    tdcore.send(clientId, requestUtf8);
  }

  static subscribe(onEvent: (event: TdNativeEvent) => void): number {
    const sink: TdEventSinkRaw = (schemaVersion: number, clientId: number,
      sequence: string, payloadUtf8: string, receivedAtMonotonicMs: number): void => {
      onEvent({
        schemaVersion: schemaVersion,
        clientId: clientId,
        sequence: BigInt(sequence),
        payloadUtf8: payloadUtf8,
        receivedAtMonotonicMs: receivedAtMonotonicMs
      });
    };
    return tdcore.subscribeUpdates(sink);
  }

  static unsubscribe(subscriptionId: number): void {
    tdcore.unsubscribe(subscriptionId);
  }

  static getMetrics(): TdBridgeMetrics {
    return tdcore.getMetrics();
  }
}
