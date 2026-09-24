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
 * feature/settings — 「自动媒体下载」行文案映射单元测试（AUTODL-101）。
 *
 * 守住的是「行文案不许撒谎」这一条：设置行显示的内容必须与点进去看到的勾选一致，
 * 所以分区一致时才列类型、不一致时必须退回「按会话类型分别设置」，
 * 且这些都只产 i18n 键（翻译在页面层）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AutoDownloadFlags, AutoDownloadPolicy } from '@tgx/core-domain';
import {
  AUTO_DOWNLOAD_KIND_ORDER,
  AUTO_DOWNLOAD_SCOPE_ORDER,
  autoDownloadKindEnabled,
  autoDownloadKindLabelKey,
  autoDownloadRowSummary,
  autoDownloadScopeLabelKey,
  autoDownloadScopeSummary,
  AutoDownloadScopeSummary
} from '../main/ets/model/AutoDownloadRows';

export default function autoDownloadRowsTest(): void {
  describe('AutoDownloadRows', () => {

    it('orders_matchDomainEnums', 0, () => {
      // 行顺序是界面约定，必须与掩码位序同源，否则子页顺序与存储位序分叉。
      expect(AUTO_DOWNLOAD_SCOPE_ORDER.length).assertEqual(3);
      expect(AUTO_DOWNLOAD_KIND_ORDER.length).assertEqual(7);
      expect(AUTO_DOWNLOAD_SCOPE_ORDER[0]).assertEqual('private');
      expect(AUTO_DOWNLOAD_KIND_ORDER[0]).assertEqual('photo');
    });

    it('labelKeys_coverEveryRow', 0, () => {
      expect(autoDownloadScopeLabelKey('private')).assertEqual('Private Chats');
      expect(autoDownloadScopeLabelKey('group')).assertEqual('Group Chats');
      expect(autoDownloadScopeLabelKey('channel')).assertEqual('Channels');
      for (const kind of AUTO_DOWNLOAD_KIND_ORDER) {
        expect(autoDownloadKindLabelKey(kind).length > 0).assertTrue();
      }
      // 视频便签与视频在 TGX 里是两种叫法，不能都翻成 Videos
      expect(autoDownloadKindLabelKey('videoNote')).assertEqual('Video message');
      expect(autoDownloadKindLabelKey('video')).assertEqual('Videos');
    });

    it('scopeSummary_nullIsLoading_notEmpty', 0, () => {
      const summary: AutoDownloadScopeSummary = autoDownloadScopeSummary(null);
      expect(summary.singleKey).assertEqual('Loading...');
      expect(summary.kindKeys.length).assertEqual(0);
    });

    it('scopeSummary_noneSelected_saysSoExplicitly', 0, () => {
      const summary: AutoDownloadScopeSummary = autoDownloadScopeSummary(new AutoDownloadFlags());
      expect(summary.singleKey).assertEqual('Download nothing automatically');
      expect(summary.kindKeys.length).assertEqual(0);
    });

    it('scopeSummary_listsEnabledKindsInRowOrder', 0, () => {
      // 掩码位序里 gif 在最后，但界面上 GIF 排在音乐之后；行文案要按界面顺序，
      // 否则子页里的类型顺序跟设置行显示的顺序对不上。
      expect(AUTO_DOWNLOAD_KIND_ORDER[3]).assertEqual('video');
      expect(AUTO_DOWNLOAD_KIND_ORDER[4]).assertEqual('file');
      expect(AUTO_DOWNLOAD_KIND_ORDER[5]).assertEqual('audio');
      expect(AUTO_DOWNLOAD_KIND_ORDER[6]).assertEqual('gif');
      const summary: AutoDownloadScopeSummary = autoDownloadScopeSummary(AutoDownloadFlags.defaultFlags());
      expect(summary.singleKey).assertEqual('');
      expect(summary.kindKeys.length).assertEqual(4);
      expect(summary.kindKeys[0]).assertEqual('Photos');
      expect(summary.kindKeys[1]).assertEqual('Voice message');
      expect(summary.kindKeys[2]).assertEqual('Video message');
      expect(summary.kindKeys[3]).assertEqual('GIFs');
    });

    it('rowSummary_sameAcrossScopes_showsKinds', 0, () => {
      const summary: AutoDownloadScopeSummary = autoDownloadRowSummary(AutoDownloadPolicy.defaultPolicy());
      expect(summary.singleKey).assertEqual('');
      expect(summary.kindKeys.length).assertEqual(4);
    });

    it('rowSummary_differentScopes_refusesToOversimplify', 0, () => {
      const policy: AutoDownloadPolicy = AutoDownloadPolicy.defaultPolicy()
        .withFlags('group', new AutoDownloadFlags());
      const summary: AutoDownloadScopeSummary = autoDownloadRowSummary(policy);
      expect(summary.singleKey).assertEqual('Varies by chat type');
      expect(summary.kindKeys.length).assertEqual(0);
    });

    it('rowSummary_nullIsLoading', 0, () => {
      const summary: AutoDownloadScopeSummary = autoDownloadRowSummary(null);
      expect(summary.singleKey).assertEqual('Loading...');
    });

    it('kindEnabled_readsFlagsAndToleratesNull', 0, () => {
      expect(autoDownloadKindEnabled(null, 'photo')).assertFalse();
      expect(autoDownloadKindEnabled(AutoDownloadFlags.defaultFlags(), 'photo')).assertTrue();
      expect(autoDownloadKindEnabled(AutoDownloadFlags.defaultFlags(), 'video')).assertFalse();
    });
  });
}
