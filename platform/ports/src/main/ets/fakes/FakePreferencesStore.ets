/**
 * platform/ports — FakePreferencesStore（PLAT-001）。
 *
 * PreferencesPort 的内存实现，行为对齐 HarmonyOS Preferences 语义：
 * - put/remove/clear 立即作用于内存视图（get 立即可见）；
 * - 变更事件在 flush() 成功后派发：同一 key 多次变更合并为最后一次；
 *   clear() 派发一次 key='*'、value=null 的通配事件；
 * - flush 失败（本 Fake 不会自然失败，可用 failNextFlush() 注入）不产生事件；
 * - observeChanges 注册后不收历史事件，仅从注册后的下一次 flush 起接收；
 * - unsubscribe 幂等，注销后不再收到任何事件。
 */

import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { Subscription } from '../Common';
import {
  PreferenceValue,
  PreferenceChange,
  PREFERENCES_CLEAR_ALL_KEY,
  PreferencesPort
} from '../PreferencesPort';

class FakePreferencesSubscription implements Subscription {
  private active: boolean = true;
  private readonly onUnsubscribe: () => void;

  constructor(onUnsubscribe: () => void) {
    this.onUnsubscribe = onUnsubscribe;
  }

  get isActive(): boolean {
    return this.active;
  }

  unsubscribe(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.onUnsubscribe();
  }
}

export class FakePreferencesStore implements PreferencesPort {
  private data: Map<string, PreferenceValue> = new Map();
  /** 自上次 flush 以来的脏变更：key -> 最新值（null 表示移除）。 */
  private pending: Map<string, PreferenceValue | null> = new Map();
  private clearedPending: boolean = false;
  private listeners: ((change: PreferenceChange) => void)[] = [];
  private failFlush: boolean = false;

  /** 测试注入：下一次 flush 返回 err。 */
  failNextFlush(): void {
    this.failFlush = true;
  }

  getString(key: string): Result<string | null, AppError> {
    const value: PreferenceValue | undefined = this.data.get(key);
    if (value === undefined) {
      return ok(null);
    }
    if (typeof value === 'string') {
      return ok(value);
    }
    return err(AppErrors.parameter('invalid', key,
      `preference '${key}' holds ${typeof value}, requested string`));
  }

  getNumber(key: string): Result<number | null, AppError> {
    const value: PreferenceValue | undefined = this.data.get(key);
    if (value === undefined) {
      return ok(null);
    }
    if (typeof value === 'number') {
      return ok(value);
    }
    return err(AppErrors.parameter('invalid', key,
      `preference '${key}' holds ${typeof value}, requested number`));
  }

  getBoolean(key: string): Result<boolean | null, AppError> {
    const value: PreferenceValue | undefined = this.data.get(key);
    if (value === undefined) {
      return ok(null);
    }
    if (typeof value === 'boolean') {
      return ok(value);
    }
    return err(AppErrors.parameter('invalid', key,
      `preference '${key}' holds ${typeof value}, requested boolean`));
  }

  put(key: string, value: PreferenceValue): Result<void, AppError> {
    if (key.length === 0) {
      return err(AppErrors.parameter('invalid', 'key', 'empty preference key'));
    }
    this.data.set(key, value);
    this.pending.set(key, value);
    this.clearedPending = false;
    return ok(undefined);
  }

  remove(key: string): Result<void, AppError> {
    this.data.delete(key);
    if (this.pending.has(key)) {
      this.pending.delete(key);
    }
    this.pending.set(key, null);
    return ok(undefined);
  }

  clear(): Result<void, AppError> {
    this.data.clear();
    this.pending.clear();
    this.clearedPending = true;
    return ok(undefined);
  }

  async flush(): Promise<Result<void, AppError>> {
    if (this.failFlush) {
      this.failFlush = false;
      return err(AppErrors.storage('io', 'fake flush failure injected', true));
    }
    const events: PreferenceChange[] = [];
    if (this.clearedPending) {
      events.push({ key: PREFERENCES_CLEAR_ALL_KEY, value: null });
    } else {
      this.pending.forEach((value: PreferenceValue | null, key: string) => {
        events.push({ key: key, value: value });
      });
    }
    this.pending.clear();
    this.clearedPending = false;
    for (const event of events) {
      this.dispatch(event);
    }
    return ok(undefined);
  }

  observeChanges(listener: (change: PreferenceChange) => void): Subscription {
    this.listeners.push(listener);
    return new FakePreferencesSubscription(() => {
      const index: number = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    });
  }

  hasPendingChanges(): boolean {
    return this.pending.size > 0 || this.clearedPending;
  }

  private dispatch(change: PreferenceChange): void {
    const snapshot: ((change: PreferenceChange) => void)[] = this.listeners.slice();
    for (const listener of snapshot) {
      listener(change);
    }
  }
}
