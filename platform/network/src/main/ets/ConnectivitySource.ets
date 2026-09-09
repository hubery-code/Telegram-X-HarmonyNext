/**
 * platform/network — ConnectivitySource：底层连通性事件源抽象（PLAT-004，纯 ArkTS 无 Kit 依赖）。
 *
 * ConnectivityAdapter 只依赖本接口；生产实现 ConnectivityKitSource 基于
 * @ohos.net.connection，单测用 Fake 事件源驱动。这样 Kit 不可用的
 * 本地单测环境也能覆盖去重/映射/状态机全部纯逻辑。
 */

import { Result, AppError } from '@tgx/core-common';
import { NetworkSnapshot, Subscription } from '@tgx/platform-ports';

export interface ConnectivitySource {
  /** 当前快照（契约：无失败路径，取不到时返回断网语义快照）。 */
  current(): NetworkSnapshot;

  /**
   * 注册底层事件监听：网络变化（含断网）时向 listener 派发新快照。
   * 底层重复上报是允许的——去重由 ConnectivityAdapter 负责。
   * 注册失败（如权限未授予）返回 err。
   */
  register(listener: (snapshot: NetworkSnapshot) => void): Result<Subscription, AppError>;
}
