/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * entry 装配层 — 省流量（Data Saver）的偏好存储实现（AUTODL-102）。
 *
 * 一个账号 = 一个整数位标记，键 = `datasaver_` + accountKey，读不到就是「从没设置过」，
 * 与 Android 的 `settings_datasaver`（`TdlibFilesManager.java:1007` + `makeKey` 按账号
 * 隔离 `:1015-1017`）一一对应。位的语义在 `core/domain/media/DataSaver`，这里只管读写。
 *
 * 缓存与 `PreferencesAutoDownloadPolicyStore` 同一套理由：聊天页每条附件都要问一次
 * 「现在是不是省流量」，所以 `current()` 只回缓存、每个账号每进程最多读一次盘，
 * `save()` 立刻刷新缓存，设置页刚勾完、还开着的聊天页下一条同步就按新状态拦。
 */

import { DATA_SAVER_STORAGE_PREFIX, DataSaverSettings, DataSaverStore } from '@tgx/core-domain';
import { readSettingsNumber, writeSettingsNumber } from './SettingsStore';

function dataSaverKey(accountKey: string): string {
  return `${DATA_SAVER_STORAGE_PREFIX}${accountKey}`;
}

export class PreferencesDataSaverStore implements DataSaverStore {
  private readonly accountKeyProvider: () => string;
  private loadedAccountKey: string = '';
  private cachedSettings: DataSaverSettings | null = null;

  constructor(accountKeyProvider: () => string) {
    this.accountKeyProvider = accountKeyProvider;
  }

  /** 强制读盘并刷新缓存；从没设置过返回 null（调用方回落默认，不回写）。 */
  public load(): DataSaverSettings | null {
    const accountKey: string = this.accountKeyProvider();
    const mask: number | null = readSettingsNumber(dataSaverKey(accountKey));
    this.loadedAccountKey = accountKey;
    this.cachedSettings = mask === null ? null : DataSaverSettings.fromMask(mask);
    return this.cachedSettings;
  }

  /** 下载门的高频入口：只回缓存，账号切换后才重新读一次盘。 */
  public current(): DataSaverSettings | null {
    const accountKey: string = this.accountKeyProvider();
    if (this.loadedAccountKey === accountKey) {
      return this.cachedSettings;
    }
    this.load();
    return this.cachedSettings;
  }

  public save(settings: DataSaverSettings): boolean {
    const accountKey: string = this.accountKeyProvider();
    if (!writeSettingsNumber(dataSaverKey(accountKey), settings.toMask())) {
      return false;
    }
    this.loadedAccountKey = accountKey;
    this.cachedSettings = settings;
    return true;
  }
}
