/**
 * entry — Bootstrap：真机授权链路与生命周期装配（SPIKE-001 + LIFE-001）。
 *
 * 链路：
 *   HarmonyAppFilesAdapter + ConnectivityAdapter + TdCoreBridge → AccountRegistry
 *   → LifecycleCoordinator.start() 恢复/创建账号 → primaryScope
 *   → ScopeAuthAdapter → AuthCoordinator
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
import { NetworkStatePort, SecureKeyStorePort, SecureRandomPort, AppFilesPort } from '@tgx/platform-ports';
import { ConnectivityAdapter } from '@tgx/platform-network';
import { HarmonySecureKeyStore, HarmonySecureRandom } from '@tgx/platform-keystore';
import { ScopeAuthAdapter } from './ScopeAuthAdapter';
import {
  LifecycleCoordinator,
  LifecycleBootstrapReport
} from './lifecycle/LifecycleCoordinator';
import { createHarmonyLogger } from './platform/HarmonyLogSink';

export interface BootstrapResult {
  readonly coordinator: AuthCoordinator;
  readonly registry: AccountRegistry;
  readonly scope: AccountScope;
  readonly bridge: TdNativeBridgeLike;
  readonly lifecycle: LifecycleCoordinator;
}

export function bootstrap(
  filesDir: string,
  cacheDir: string,
  tdlibParams: TdlibParametersConfig,
  networkPort?: NetworkStatePort,
  keyStorePort?: SecureKeyStorePort,
  secureRandomPort?: SecureRandomPort,
  bridgePort?: TdNativeBridgeLike,
  filesPort?: AppFilesPort
): BootstrapResult {
  const bridge: TdNativeBridgeLike = bridgePort !== undefined ? bridgePort : new TdCoreBridge();
  const files: AppFilesPort = filesPort !== undefined ? filesPort : new HarmonyAppFilesAdapter(filesDir, cacheDir);
  const keyStore: SecureKeyStorePort = keyStorePort !== undefined ? keyStorePort : new HarmonySecureKeyStore();
  const secureRandom: SecureRandomPort = secureRandomPort !== undefined ? secureRandomPort : new HarmonySecureRandom();
  const options: AccountRegistryOptions = {
    bridge: bridge,
    files: files,
    keyStore: keyStore,
    secureRandom: secureRandom,
    gatewayOptions: {
      defaultTimeoutMillis: 60000
    }
  };
  const registry: AccountRegistry = new AccountRegistry(options);
  registry.start();

  const network: NetworkStatePort = networkPort !== undefined ? networkPort : new ConnectivityAdapter();
  const lifecycle: LifecycleCoordinator = new LifecycleCoordinator({
    registry: registry,
    network: network
  });
  const report: LifecycleBootstrapReport = lifecycle.start();
  const scope: AccountScope = report.primaryScope;

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
    },
    logger: createHarmonyLogger()
  };
  const coordinator: AuthCoordinator = new AuthCoordinator(deps);

  return {
    coordinator: coordinator,
    registry: registry,
    scope: scope,
    bridge: bridge,
    lifecycle: lifecycle
  };
}
