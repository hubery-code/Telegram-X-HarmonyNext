/**
 * platform/storage — PreferencesPort 的 HarmonyOS Preferences Kit adapter（PLAT-002）。
 *
 * 对应计划 §5.6：Preferences 只保存小型、非敏感开关（主题、字号、UI 偏好）。
 * 持久化走 @ohos.data.preferences；内存视图 / 变更合并 / flush 派发语义由
 * PreferenceStoreCore 提供（与平台无关，单测覆盖）。
 *
 * 用法（entry 装配层）：
 *   const store = await HarmonyPreferencesAdapter.open(context, 'tgx_ui_prefs');
 * 设备测试可用同步工厂 openSync（getPreferencesSync，API 10+）。
 *
 * 已知限制（登记，见 README）：同一偏好文件只应由一个 adapter 实例持有
 * （跨实例/跨进程同步不订阅 Kit 的 change 事件，由装配层保证单实例）。
 */

import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { BusinessError } from '@ohos.base';
import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import {
  PreferencesPort,
  PreferenceValue,
  PreferenceChange,
  Subscription
} from '@tgx/platform-ports';
import {
  PreferenceStoreCore,
  PreferencePersistence,
  PreferenceWrite
} from '../core/PreferenceStoreCore';

/** Kit 抛出的异常统一映射：BusinessError 数字码 → platform/code（retryable=true）。 */
function asPlatformError(origin: string, e: Object): AppError {
  const be: BusinessError = e as BusinessError;
  if (be !== null && be !== undefined && typeof be.code === 'number') {
    return AppErrors.platform(be.code, `${origin} failed (preferences kit)`, true);
  }
  return AppErrors.unknown(origin, `${origin} failed (non-business error)`);
}

function collectPrimitiveValues(all: Object): Map<string, PreferenceValue> {
  const data: Map<string, PreferenceValue> = new Map();
  const record: Record<string, Object> = all as Record<string, Object>;
  for (const key of Object.keys(record)) {
    const value: Object = record[key];
    if (typeof value === 'string') {
      data.set(key, value);
    } else if (typeof value === 'number' && Number.isFinite(value)) {
      data.set(key, value);
    } else if (typeof value === 'boolean') {
      data.set(key, value);
    }
  }
  return data;
}

class KitPreferencePersistence implements PreferencePersistence {
  private readonly pref: preferences.Preferences;

  constructor(pref: preferences.Preferences) {
    this.pref = pref;
  }

  async persist(writes: PreferenceWrite[]): Promise<Result<void, AppError>> {
    try {
      for (const write of writes) {
        if (write.kind === 'put') {
          await this.pref.put(write.key, write.value);
        } else {
          await this.pref.delete(write.key);
        }
      }
      await this.pref.flush();
      return ok(undefined);
    } catch (e) {
      return err(asPlatformError('preferences.persist', e));
    }
  }
}

export class HarmonyPreferencesAdapter implements PreferencesPort {
  private readonly core: PreferenceStoreCore;

  private constructor(core: PreferenceStoreCore) {
    this.core = core;
  }

  /** 打开（异步，生产路径）。 */
  static async open(context: common.Context, storeName: string): Promise<Result<HarmonyPreferencesAdapter, AppError>> {
    if (storeName.length === 0) {
      return err(AppErrors.parameter('invalid', 'storeName', 'empty preferences store name'));
    }
    try {
      const pref: preferences.Preferences = await preferences.getPreferences(context, { name: storeName });
      const all: Object = await pref.getAll();
      const core: PreferenceStoreCore = new PreferenceStoreCore(collectPrimitiveValues(all),
        new KitPreferencePersistence(pref));
      return ok(new HarmonyPreferencesAdapter(core));
    } catch (e) {
      return err(asPlatformError('preferences.open', e));
    }
  }

  /** 打开（同步，API 10+，供设备测试的同步工厂使用）。 */
  static openSync(context: common.Context, storeName: string): Result<HarmonyPreferencesAdapter, AppError> {
    if (storeName.length === 0) {
      return err(AppErrors.parameter('invalid', 'storeName', 'empty preferences store name'));
    }
    try {
      const pref: preferences.Preferences = preferences.getPreferencesSync(context, { name: storeName });
      const all: Object = pref.getAllSync();
      const core: PreferenceStoreCore = new PreferenceStoreCore(collectPrimitiveValues(all),
        new KitPreferencePersistence(pref));
      return ok(new HarmonyPreferencesAdapter(core));
    } catch (e) {
      return err(asPlatformError('preferences.openSync', e));
    }
  }

  getString(key: string): Result<string | null, AppError> {
    return this.core.getString(key);
  }

  getNumber(key: string): Result<number | null, AppError> {
    return this.core.getNumber(key);
  }

  getBoolean(key: string): Result<boolean | null, AppError> {
    return this.core.getBoolean(key);
  }

  put(key: string, value: PreferenceValue): Result<void, AppError> {
    return this.core.put(key, value);
  }

  remove(key: string): Result<void, AppError> {
    return this.core.remove(key);
  }

  clear(): Result<void, AppError> {
    return this.core.clear();
  }

  flush(): Promise<Result<void, AppError>> {
    return this.core.flush();
  }

  observeChanges(listener: (change: PreferenceChange) => void): Subscription {
    return this.core.observeChanges(listener);
  }

  hasPendingChanges(): boolean {
    return this.core.hasPendingChanges();
  }
}
