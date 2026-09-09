/**
 * entry — Bootstrap：真机授权链路装配（SPIKE-001）。
 *
 * 链路：
 *   HarmonyAppFilesAdapter → TdCoreBridge → AccountRegistry → create('default')
 *   → ScopeAuthAdapter → AuthCoordinator
 *
 * EntryAbility.onCreate 调用 bootstrap()，返回 AuthCoordinator 供 Index.ets 使用。
 * scope.gatewayInstance.start() 已在 AccountScope.open(startActive=true) 中完成。
 * TDLib 启动后 emit authorizationStateWaitTdlibParameters →
 * AuthCoordinator.handleIncomingEvent → core authReducer emits setTdlibParameters effect →
 * AuthCoordinator.executeCoreAuthEffect → scope.request('setTdlibParameters', params)。
 */

import { TdCoreBridge } from '@tgx/platform-tdcore-bridge';
import {
  AccountRegistry,
  AccountRegistryOptions,
  AccountScope
} from '@tgx/core-account';
import { TdNativeBridgeLike } from '@tgx/td-gateway';
import { HarmonyAppFilesAdapter } from '@tgx/platform-files';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv } from '@tgx/feature-template';
import {
  AuthCoordinator,
  AuthCoordinatorDeps,
  TdlibParametersConfig
} from '@tgx/feature-auth';
import { ScopeAuthAdapter } from './ScopeAuthAdapter';

export interface BootstrapResult {
  readonly coordinator: AuthCoordinator;
  readonly registry: AccountRegistry;
  readonly scope: AccountScope;
  readonly bridge: TdCoreBridge;
}

export function bootstrap(
  filesDir: string,
  cacheDir: string,
  tdlibParams: TdlibParametersConfig
): BootstrapResult {
  const bridge: TdCoreBridge = new TdCoreBridge();
  const files: HarmonyAppFilesAdapter = new HarmonyAppFilesAdapter(filesDir, cacheDir);
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

  const authScope: ScopeAuthAdapter = new ScopeAuthAdapter(scope);
  const env: ReducerEnv = {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('entry-')
  };
  const deps: AuthCoordinatorDeps = {
    scope: authScope,
    env: env,
    tdlibParameters: tdlibParams,
    onNavigate: (route: string) => {
      // Navigation handled in Index.ets via state subscription
    }
  };
  const coordinator: AuthCoordinator = new AuthCoordinator(deps);

  return {
    coordinator: coordinator,
    registry: registry,
    scope: scope,
    bridge: bridge
  };
}
