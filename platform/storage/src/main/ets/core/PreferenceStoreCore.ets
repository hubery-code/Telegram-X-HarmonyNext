/**
 * platform/storage — PreferencesPort 纯 ArkTS 存储核心（PLAT-002，无 Kit 依赖）。
 *
 * PreferencesPort 的「内存视图 + 挂起变更跟踪 + flush 后按合并批次派发」语义
 * 与底层持久化无关，因此抽为本纯类，由两个生产 adapter 复用：
 * - HarmonyPreferencesAdapter（@ohos.data.preferences）
 * - RdbPreferencesAdapter（@ohos.data.relationalStore）
 *
 * 语义与 platform/ports 的 PreferencesPort 契约严格对齐（与 FakePreferencesStore
 * 行为一致）：put/remove/clear 立即作用于内存视图；变更事件仅在 persistence
 * persist 成功后派发；同 key 多次变更合并为最后一次；clear() 派发一次
 * key='*'（PREFERENCES_CLEAR_ALL_KEY）通配事件并吞掉批次内的逐 key 事件；
 * persist 失败不产生事件且变更保持挂起（可重试，写入操作幂等）。
 */

import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import {
  Subscription,
  PreferenceValue,
  PreferenceChange,
  PREFERENCES_CLEAR_ALL_KEY,
  PreferencesPort
} from '@tgx/platform-ports';

/** 一次 flush 的写入：put 键值。 */
export interface PutPreferenceWrite {
  readonly kind: 'put';
  readonly key: string;
  readonly value: PreferenceValue;
}

/** 一次 flush 的写入：delete 键。 */
export interface DeletePreferenceWrite {
  readonly kind: 'delete';
  readonly key: string;
}

/** 一次 flush 需要落盘的写入操作。 */
export type PreferenceWrite = PutPreferenceWrite | DeletePreferenceWrite;

/**
 * 持久化后端抽象：生产 adapter 分别用 Preferences Kit / RDB 实现；
 * 本地单测用内存实现（可注入失败）。
 */
export interface PreferencePersistence {
  persist(writes: PreferenceWrite[]): Promise<Result<void, AppError>>;
}

class CoreSubscription implements Subscription {
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

export class PreferenceStoreCore implements PreferencesPort {
  private data: Map<string, PreferenceValue>;
  private readonly persistence: PreferencePersistence;
  /** 自上次 flush 以来的脏变更：key -> 最新值（null 表示移除）。 */
  private pending: Map<string, PreferenceValue | null> = new Map();
  private clearedPending: boolean = false;
  private listeners: ((change: PreferenceChange) => void)[] = [];

  constructor(initial: Map<string, PreferenceValue>, persistence: PreferencePersistence) {
    this.data = initial;
    this.persistence = persistence;
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
    if (typeof value === 'number' && !Number.isFinite(value)) {
      return err(AppErrors.parameter('invalid', key, 'non-finite number is not storable'));
    }
    this.data.set(key, value);
    this.pending.set(key, value);
    this.clearedPending = false;
    return ok(undefined);
  }

  remove(key: string): Result<void, AppError> {
    this.data.delete(key);
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
    if (this.pending.size === 0 && !this.clearedPending) {
      return ok(undefined);
    }
    const events: PreferenceChange[] = [];
    const writes: PreferenceWrite[] = [];
    if (this.clearedPending) {
      const wildcard: PreferenceChange = { key: PREFERENCES_CLEAR_ALL_KEY, value: null };
      events.push(wildcard);
    } else {
      this.pending.forEach((value: PreferenceValue | null, key: string) => {
        const event: PreferenceChange = { key: key, value: value };
        events.push(event);
      });
    }
    this.pending.forEach((value: PreferenceValue | null, key: string) => {
      if (value === null) {
        const write: DeletePreferenceWrite = { kind: 'delete', key: key };
        writes.push(write);
      } else {
        const write: PutPreferenceWrite = { kind: 'put', key: key, value: value };
        writes.push(write);
      }
    });

    const savedPending: Map<string, PreferenceValue | null> = this.pending;
    const savedCleared: boolean = this.clearedPending;
    this.pending = new Map();
    this.clearedPending = false;

    const persisted: Result<void, AppError> = await this.persistence.persist(writes);
    if (persisted.err) {
      this.pending = savedPending;
      this.clearedPending = savedCleared;
      return persisted;
    }
    for (const event of events) {
      this.dispatch(event);
    }
    return ok(undefined);
  }

  observeChanges(listener: (change: PreferenceChange) => void): Subscription {
    this.listeners.push(listener);
    return new CoreSubscription(() => {
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
