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
 * entry 装配层 — 按网络类型的自动下载限制的偏好存储实现（AUTODL-103）。
 *
 * Android 把每一档网络的两个字段挤进一个 int（`(exclude << 24) | size`，
 * `TdlibFilesManager.java:1133`），存在 `settings_limit_wifi|mobile|roaming`
 * 三个按账号隔离的键里。本端与 AUTODL-101 同口径**不做字节打包**：
 * 一个账号 × 一档网络 × 一个字段 = 一个键，共 3 × 2 = 6 个键，读脏了也只影响一格。
 *
 * 缓存的理由与 `PreferencesDataSaverStore` 相同：聊天页每条附件都要问一次
 * 「当前网络档的上限是多少」，`current()` 只回缓存、每账号每进程最多读一次盘，
 * `save()` 立刻刷新，设置页刚改完限制、还开着的聊天页下一条同步就按新值拦。
 */

import {
  DownloadLimitsByNetwork,
  DownloadLimitsStore,
  MEDIA_LIMIT_FIELD_EXCLUDE,
  MEDIA_LIMIT_FIELD_SIZE,
  MEDIA_LIMIT_NETWORKS,
  MEDIA_LIMIT_STORAGE_PREFIX,
  DataSaverNetworkType
} from '@tgx/core-domain';
import { readSettingsNumber, writeSettingsNumber } from './SettingsStore';

function limitKey(accountKey: string, network: DataSaverNetworkType, field: string): string {
  return `${MEDIA_LIMIT_STORAGE_PREFIX}${accountKey}:${network}:${field}`;
}

export class PreferencesDownloadLimitsStore implements DownloadLimitsStore {
  private readonly accountKeyProvider: () => string;
  private loadedAccountKey: string = '';
  private cachedLimits: DownloadLimitsByNetwork | null = null;

  constructor(accountKeyProvider: () => string) {
    this.accountKeyProvider = accountKeyProvider;
  }

  /** 强制读盘并刷新缓存；六格全是空（从没设置过）返回 null，调用方回落默认且不回写。 */
  public load(): DownloadLimitsByNetwork | null {
    const accountKey: string = this.accountKeyProvider();
    const values: (number | null)[] = [];
    let hasAnyValue: boolean = false;
    for (let i = 0; i < MEDIA_LIMIT_NETWORKS.length; i++) {
      const network: DataSaverNetworkType | undefined = MEDIA_LIMIT_NETWORKS[i];
      if (network === undefined) {
        continue;
      }
      const size: number | null = readSettingsNumber(limitKey(accountKey, network, MEDIA_LIMIT_FIELD_SIZE));
      const exclude: number | null = readSettingsNumber(limitKey(accountKey, network, MEDIA_LIMIT_FIELD_EXCLUDE));
      if (size !== null || exclude !== null) {
        hasAnyValue = true;
      }
      values.push(size);
      values.push(exclude);
    }
    this.loadedAccountKey = accountKey;
    this.cachedLimits = hasAnyValue ? DownloadLimitsByNetwork.fromStorageValues(values) : null;
    return this.cachedLimits;
  }

  /** 下载门的高频入口：只回缓存，账号切换后才重新读一次盘。 */
  public current(): DownloadLimitsByNetwork | null {
    const accountKey: string = this.accountKeyProvider();
    if (this.loadedAccountKey === accountKey) {
      return this.cachedLimits;
    }
    this.load();
    return this.cachedLimits;
  }

  /** 整份写回（六格一起）；任一格失败即返回 false，调用方按失败回滚读盘。 */
  public save(limits: DownloadLimitsByNetwork): boolean {
    const accountKey: string = this.accountKeyProvider();
    const values: number[] = limits.toStorageValues();
    for (let i = 0; i < MEDIA_LIMIT_NETWORKS.length; i++) {
      const network: DataSaverNetworkType | undefined = MEDIA_LIMIT_NETWORKS[i];
      if (network === undefined) {
        continue;
      }
      const size: number | undefined = values[i * 2];
      const exclude: number | undefined = values[i * 2 + 1];
      if (!writeSettingsNumber(limitKey(accountKey, network, MEDIA_LIMIT_FIELD_SIZE), size !== undefined ? size : 0)) {
        return false;
      }
      if (!writeSettingsNumber(
        limitKey(accountKey, network, MEDIA_LIMIT_FIELD_EXCLUDE),
        exclude !== undefined ? exclude : 0
      )) {
        return false;
      }
    }
    this.loadedAccountKey = accountKey;
    this.cachedLimits = limits;
    return true;
  }
}
