/**
 * entry 装配层 — 应用锁的装配与取用（APPLOCK-101）。
 *
 * 为什么是模块单例而不是 `AppStorage`：`AppLockGate` 是**行为对象**，不是可观察状态 ——
 * 遮罩层要订阅它的快照变化，而 `AppStorage` 只会告诉我们「换了个引用」。取 `AppStorage`
 * 反而要再造一层订阅，不如沿用本仓已有的模块单例口径（`deeplink/DeepLinkQueue.ets`）。
 *
 * 时序（关键）：`installAppLock()` 必须在 `initSettingsStore()` **之后**调用 ——
 * 档位是从 `preferences` 读的，存储还没打开就装锁，第一次读到的会是默认档并被缓存住。
 */

import { AppLockStore } from '@tgx/core-domain';
import { BootstrapResult } from '../Bootstrap';
import { HarmonyPasscodeStore } from '@tgx/platform-keystore';
import { PreferencesAppLockStore } from '../store/AppLockStore';
import { AppLockGate } from './AppLockGate';

let store: PreferencesAppLockStore | null = null;
let gate: AppLockGate | null = null;

/**
 * 冷启动装配：把安全存储 + 随机数端口包成 PIN 存储，再装出锁态机。
 * `bootstrap` 没带出端口（旧入口/测试装配）时返回 false，调用方按「本进程没有应用锁」处理。
 */
export function installAppLock(result: BootstrapResult | undefined | null): boolean {
  if (gate !== null) {
    return true;
  }
  if (result === undefined || result === null
    || result.keyStore === undefined || result.secureRandom === undefined) {
    return false;
  }
  store = new PreferencesAppLockStore(new HarmonyPasscodeStore(result.keyStore, result.secureRandom));
  gate = new AppLockGate(store);
  return true;
}

export function appLockGate(): AppLockGate | null {
  return gate;
}

/** 设置协调器注入用：与遮罩层共用同一份实例，缓存的「是否已设 PIN」才只有一个真相。 */
export function appLockStore(): AppLockStore | null {
  return store;
}

/** 测试/冷启失败清理用。 */
export function resetAppLock(): void {
  gate = null;
  store = null;
}
