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
 * entry 装配层 — 「贴纸与表情」设置的偏好存储实现（TGS-104）。
 *
 * 一个账号 = 一个整数位掩码，键 = `stickers_` + accountKey，读不到就是「从没设置过」；
 * 位的语义（含 Android 那位是**否定位**这件事）全在 `core/domain/media/StickerSettings`，
 * 这里只管读写。
 *
 * 缓存与 `PreferencesDataSaverStore` 同一套理由：聊天页每张贴纸挂动画前都要问一次
 * 「现在到底循不循环」，所以 `current()` 只回缓存、每个账号每进程最多读一次盘，
 * `save()` 立刻刷新缓存 —— 设置页刚勾完，回到还开着的会话，下一张挂上的贴纸就按新值走。
 */

import { STICKER_SETTINGS_STORAGE_PREFIX, StickerSettings, StickerSettingsStore } from '@tgx/core-domain';
import { readSettingsNumber, writeSettingsNumber } from './SettingsStore';

function stickerSettingsKey(accountKey: string): string {
  return `${STICKER_SETTINGS_STORAGE_PREFIX}${accountKey}`;
}

export class PreferencesStickerSettingsStore implements StickerSettingsStore {
  private readonly accountKeyProvider: () => string;
  private loadedAccountKey: string = '';
  private cachedSettings: StickerSettings | null = null;

  constructor(accountKeyProvider: () => string) {
    this.accountKeyProvider = accountKeyProvider;
  }

  /** 强制读盘并刷新缓存；从没设置过返回 null（调用方回落默认，不回写）。 */
  public load(): StickerSettings | null {
    const accountKey: string = this.accountKeyProvider();
    const mask: number | null = readSettingsNumber(stickerSettingsKey(accountKey));
    this.loadedAccountKey = accountKey;
    this.cachedSettings = mask === null ? null : StickerSettings.fromMask(mask);
    return this.cachedSettings;
  }

  /** 挂动画前的高频入口：只回缓存，账号切换后才重新读一次盘。 */
  public current(): StickerSettings | null {
    const accountKey: string = this.accountKeyProvider();
    if (this.loadedAccountKey === accountKey) {
      return this.cachedSettings;
    }
    this.load();
    return this.cachedSettings;
  }

  public save(settings: StickerSettings): boolean {
    const accountKey: string = this.accountKeyProvider();
    if (!writeSettingsNumber(stickerSettingsKey(accountKey), settings.toMask())) {
      return false;
    }
    this.loadedAccountKey = accountKey;
    this.cachedSettings = settings;
    return true;
  }
}
