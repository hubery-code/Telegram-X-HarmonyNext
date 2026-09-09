/**
 * entry — Bootstrap：最小装配骨架（BRG-006 entry 装配）。
 *
 * 链路：TdCoreBridge → AccountRegistry → create('default') → scope
 *
 * TODO（真机集成，需 SPIKE-001 确认后启用）：
 * - AppFilesPort 当前用 FakeAppFiles 占位；生产需 platform/files 的
 *   HarmonyOS 文件 Kit adapter（context.filesDir → AppDirectory）
 * - EntryAbility.onCreate 调用 bootstrap() → registry.start() → registry.create('default')
 * - scope.gatewayInstance.start() 后 TDLib 会 emit authorizationStateWaitTdlibParameters
 * - AUTH-001 的 authReducer 驱动 scope.authorizationHolder.replace → UI 渲染
 * - AuthCoordinator 连接 scope 事件流 → authFeatureReducer → AuthRootPage 渲染
 * - 当前 entry/pages/Index.ets 用 fake AuthUiState.initial() 注入独立渲染，
 *   真机启用后替换为 AuthCoordinator（见 feature/auth README 架构图）
 *
 * 本文件编译通过但未被 EntryAbility 调用（不引入未经验证的启动链路）。
 * 真机调试时取消注释 onCreate 中的 bootstrap 调用即可。
 */

import { TdCoreBridge } from '@tgx/platform-tdcore-bridge';
import {
  AccountRegistry,
  AccountRegistryOptions,
  AccountScope,
  AuthState
} from '@tgx/core-account';
import { TdNativeBridgeLike } from '@tgx/td-gateway';
import { AppFilesPort, FakeAppFiles } from '@tgx/platform-ports';

export interface BootstrapResult {
  readonly bridge: TdCoreBridge;
  readonly registry: AccountRegistry;
  readonly scope: AccountScope;
  readonly authStateKind: string;
}

export function bootstrap(): BootstrapResult {
  const bridge: TdCoreBridge = new TdCoreBridge();
  const files: AppFilesPort = new FakeAppFiles();
  const options: AccountRegistryOptions = {
    bridge: bridge as TdNativeBridgeLike,
    files: files
  };
  const registry: AccountRegistry = new AccountRegistry(options);
  registry.start();
  const created = registry.create('default');
  if (created.ok === false) {
    throw new Error(`bootstrap: failed to create default scope: ${created.error.kind}`);
  }
  const scope: AccountScope = created.value;
  const authState: AuthState = scope.authorization;
  return {
    bridge: bridge,
    registry: registry,
    scope: scope,
    authStateKind: authState.kind
  };
}
