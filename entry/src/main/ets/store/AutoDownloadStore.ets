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
 * entry 装配层 — 自动媒体下载策略的偏好存储实现（AUTODL-101）。
 *
 * 契约在 `core/domain`（`AutoDownloadPolicyStore`），这里只负责把它接到
 * `entry/store/SettingsStore.ets` 那份已经验证可用的 `preferences` 上：
 * 一个账号 × 一个分区 = 一个数字掩码，读不到就是「从没设置过」。
 *
 * ## 为什么按账号隔离
 *
 * 账号 A 关掉的自动下载不该让账号 B 也跟着关 —— Android 端就是把
 * `settings_autodownload` 存在每个账号自己的 Tdlib 参数目录里。这里用
 * 前缀 + accountKey + 分区拼键，语义等价。
 *
 * ## 为什么带缓存
 *
 * 聊天页每条消息解析附件时都会问一次策略（`resolveMediaAttachment`）。
 * `preferences` 本身在内存里，但每条消息重新拼三次键、判三次类型仍是纯浪费，
 * 所以 `current()` 只回缓存，**每个账号每进程最多读一次盘**；`save()` 立刻刷新
 * 缓存，因此设置页刚勾完，还开着的聊天页下一条同步就能按新策略放行。
 */

import {
  AUTO_DOWNLOAD_SCOPES,
  AUTO_DOWNLOAD_STORAGE_PREFIX,
  AutoDownloadChatScope,
  AutoDownloadPolicy,
  AutoDownloadPolicyStore
} from '@tgx/core-domain';
import { readSettingsNumber, writeSettingsNumber } from './SettingsStore';

/**
 * 完整偏好键。分隔符用 `:` 而账号名可能含 `_`；读取端只按 `AUTO_DOWNLOAD_SCOPES`
 * 里枚举出的固定分区拼键，所以不存在两个账号互相读到对方的值的情况。
 */
function policyKey(accountKey: string, scope: AutoDownloadChatScope): string {
  return `${AUTO_DOWNLOAD_STORAGE_PREFIX}${accountKey}:${scope}`;
}

export class PreferencesAutoDownloadPolicyStore implements AutoDownloadPolicyStore {
  private readonly accountKeyProvider: () => string;
  /** 已尝试读盘的账号；与 cachedPolicy 一起构成「每账号读一次」。 */
  private loadedAccountKey: string = '';
  private cachedPolicy: AutoDownloadPolicy | null = null;

  constructor(accountKeyProvider: () => string) {
    this.accountKeyProvider = accountKeyProvider;
  }

  /** 强制读盘并刷新缓存；从没设置过返回 null（调用方回落默认，不回写）。 */
  public load(): AutoDownloadPolicy | null {
    const accountKey: string = this.accountKeyProvider();
    const values: (number | null)[] = [];
    let hasAnyValue: boolean = false;
    for (let i = 0; i < AUTO_DOWNLOAD_SCOPES.length; i++) {
      const value: number | null = readSettingsNumber(policyKey(accountKey, AUTO_DOWNLOAD_SCOPES[i]));
      if (value !== null) {
        hasAnyValue = true;
      }
      values.push(value);
    }
    this.loadedAccountKey = accountKey;
    this.cachedPolicy = hasAnyValue ? AutoDownloadPolicy.fromStorageValues(values) : null;
    return this.cachedPolicy;
  }

  /** 聊天页的高频入口：只回缓存，账号切换后才重新读一次盘。 */
  public current(): AutoDownloadPolicy | null {
    const accountKey: string = this.accountKeyProvider();
    if (this.loadedAccountKey === accountKey) {
      return this.cachedPolicy;
    }
    this.load();
    return this.cachedPolicy;
  }

  public save(policy: AutoDownloadPolicy): boolean {
    const accountKey: string = this.accountKeyProvider();
    const masks: number[] = policy.toStorageValues();
    for (let i = 0; i < AUTO_DOWNLOAD_SCOPES.length; i++) {
      const mask: number | undefined = masks[i];
      if (!writeSettingsNumber(policyKey(accountKey, AUTO_DOWNLOAD_SCOPES[i]), mask !== undefined ? mask : 0)) {
        return false;
      }
    }
    this.loadedAccountKey = accountKey;
    this.cachedPolicy = policy;
    return true;
  }
}
