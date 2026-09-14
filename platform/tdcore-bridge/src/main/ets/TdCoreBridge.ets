/**
 * platform/tdcore-bridge — TdCoreBridge 生产适配器（BRG-006 + BRG-005 关闭生命周期）。
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
 * 关闭生命周期（BRG-005，状态机 idle → active → closing → closed）：
 * - close()：幂等。逐 client 发送 {"@type":"close"}（TDLib JSON API 的销毁语义），
 *   再退订本桥创建的全部订阅——最后一个订阅移除时 native 侧停止 receive 线程
 *   并释放 TSFN（StopDispatcherIfIdle）。单次同步完成，closing 仅对重入回调可见；
 * - 重复 close()：第二次起为 no-op；
 * - 迟到回调：close 期间/之后到达本桥 raw sink 的事件一律丢弃并计
 *   discardedEventCount（不触达业务 sink，不崩溃不泄漏）；
 * - closed 后 send/subscribeUpdates 抛 Error（RequestRegistry 契约会把 send 异常
 *   映射为稳定 platform 错误），execute 返回 TDLib 形 error JSON，getVersion/
 *   getMetrics 为无状态观测口仍直透；
 * - 快速 close → reopen：closed 后 createClient() 复位状态机（idle → active）并
 *   创建全新 client，开始新的一代；诊断计数器跨代累计不清零。
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
  resetSession?(): void;
}

/** 桥关闭生命周期状态。idle = 未建 client；active = 已建 client/可服务；closed = 终态（可经 createClient  reopen）。 */
export type TdCoreBridgeState = 'idle' | 'active' | 'closing' | 'closed';

const tdcoreNative: TdCoreNativeModule = native as TdCoreNativeModule;

const TDCORE_BRIDGE_CLOSED_MESSAGE: string = 'tdcore bridge is closed';

/** TDLib JSON API 的 client 销毁语义：向该 client 发送 close 请求。 */
const TDCORE_CLOSE_CLIENT_REQUEST: string = '{"@type":"close"}';

/** closed 后 execute 的返回：TDLib 形 error 对象（与 native 对非法请求的既有做法一致）。 */
const TDCORE_CLOSED_EXECUTE_RESPONSE: string =
  '{"@type":"error","code":400,"message":"tdcore bridge is closed"}';

export class TdCoreBridge implements TdNativeBridgeLike {
  private readonly nativeModule: TdCoreNativeModule;

  private state: TdCoreBridgeState = 'idle';
  /** 本代经本桥创建、尚未关闭的 clientId。 */
  private readonly clientIds: Set<number> = new Set();
  /** 本桥创建、尚未退订的订阅 id。 */
  private readonly subscriptionIds: Set<number> = new Set();
  /** closing/closed 后被 raw sink 守卫丢弃的迟到事件数（跨代累计）。 */
  private discardedEventCountValue: number = 0;
  /** close() 过程中 native 调用抛异常的次数（尽力而为关闭，不中断流程）。 */
  private closeErrorCountValue: number = 0;

  constructor(nativeModule?: TdCoreNativeModule) {
    this.nativeModule = nativeModule !== undefined ? nativeModule : tdcoreNative;
  }

  get lifecycleState(): TdCoreBridgeState {
    return this.state;
  }

  get discardedEventCount(): number {
    return this.discardedEventCountValue;
  }

  get closeErrorCount(): number {
    return this.closeErrorCountValue;
  }

  getVersion(): string {
    return this.nativeModule.getVersion();
  }

  execute(requestUtf8: string): string | null {
    if (this.state === 'closing' || this.state === 'closed') {
      return TDCORE_CLOSED_EXECUTE_RESPONSE;
    }
    return this.nativeModule.execute(requestUtf8);
  }

  createClient(): number {
    if (this.state === 'closed') {
      // 快速 close → reopen：复位状态机，开始新的一代（计数器累计不清零）。
      this.state = 'idle';
    }
    if (this.state === 'closing') {
      throw new Error(TDCORE_BRIDGE_CLOSED_MESSAGE);
    }
    const clientId: number = this.nativeModule.createClient();
    this.clientIds.add(clientId);
    this.state = 'active';
    return clientId;
  }

  send(clientId: number, requestUtf8: string): void {
    if (this.state === 'closing' || this.state === 'closed') {
      throw new Error(TDCORE_BRIDGE_CLOSED_MESSAGE);
    }
    this.nativeModule.send(clientId, requestUtf8);
  }

  subscribeUpdates(sink: TdNativeEventSink): number {
    if (this.state === 'closing' || this.state === 'closed') {
      throw new Error(TDCORE_BRIDGE_CLOSED_MESSAGE);
    }
    const self: TdCoreBridge = this;
    const raw: TdEventSinkRaw = (
      schemaVersion: number,
      clientId: number,
      sequence: string,
      payloadUtf8: string,
      receivedAtMonotonicMs: number
    ): void => {
      // 迟到回调守卫：close 期间/之后绝不触达业务 sink，丢弃并计数。
      if (self.state === 'closing' || self.state === 'closed') {
        self.discardedEventCountValue += 1;
        return;
      }
      const event: TdNativeEvent = {
        schemaVersion: schemaVersion,
        clientId: clientId,
        sequence: sequence,
        payloadUtf8: payloadUtf8,
        receivedAtMonotonicMs: receivedAtMonotonicMs
      };
      sink(event);
    };
    const subscriptionId: number = this.nativeModule.subscribeUpdates(raw);
    this.subscriptionIds.add(subscriptionId);
    return subscriptionId;
  }

  unsubscribe(subscriptionId: number): void {
    this.subscriptionIds.delete(subscriptionId);
    // 幂等直透：native 侧对未知/重复 id 安全；closed 后残留的退订同样是安全 no-op。
    this.nativeModule.unsubscribe(subscriptionId);
  }

  /**
   * 关闭（BRG-005）：销毁本代全部 TDLib client（逐 client 发送 close 请求），
   * 退订本桥全部订阅（最后一个移除时 native 停止 receive 线程并释放 TSFN），
   * 终态 closed。幂等：重复调用为 no-op。单步内 native 失败尽力而为、计数不中断。
   */
  close(): void {
    if (this.state === 'closing' || this.state === 'closed') {
      return;
    }
    this.state = 'closing';
    for (const clientId of Array.from(this.clientIds)) {
      try {
        this.nativeModule.send(clientId, TDCORE_CLOSE_CLIENT_REQUEST);
      } catch (e) {
        this.closeErrorCountValue += 1;
      }
    }
    this.clientIds.clear();
    for (const subscriptionId of Array.from(this.subscriptionIds)) {
      try {
        this.nativeModule.unsubscribe(subscriptionId);
      } catch (e) {
        this.closeErrorCountValue += 1;
      }
    }
    this.subscriptionIds.clear();
    if (typeof this.nativeModule.resetSession === 'function') {
      try {
        this.nativeModule.resetSession();
      } catch (e) {
        this.closeErrorCountValue += 1;
      }
    }
    this.state = 'closed';
  }

  /**
   * 推进会话代际并清空底层积压队列（BRG-007 / P1-BRG-002）。
   */
  resetSession(): void {
    if (typeof this.nativeModule.resetSession === 'function') {
      try {
        this.nativeModule.resetSession();
      } catch (e) {
        this.closeErrorCountValue += 1;
      }
    }
  }

  getMetrics(): TdNativeBridgeMetrics {
    return this.nativeModule.getMetrics();
  }
}
