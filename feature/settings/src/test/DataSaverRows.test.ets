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
 * feature/settings — 「省流量」卡行文案映射单元测试（AUTODL-102）。
 *
 * 与 `AutoDownloadRows` 守同一类问题：副标题不许与面板里的勾选不一致。
 * 这里只产 i18n 键，翻译在页面层，所以断言也只看键。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  DATA_SAVER_FLAG_ENABLED,
  DATA_SAVER_FLAG_WHEN_MOBILE,
  DATA_SAVER_FLAG_WHEN_ROAMING,
  DataSaverSettings
} from '@tgx/core-domain';
import { dataSaverAutoOnLabelKey, dataSaverAutoOnSummaryKey } from '../main/ets/model/DataSaverRows';

export default function dataSaverRowsTest(): void {
  describe('DataSaverRows', () => {

    it('autoOnLabel_keysMatchPanelRows', 0, () => {
      expect(dataSaverAutoOnLabelKey(DATA_SAVER_FLAG_WHEN_MOBILE)).assertEqual('Mobile data');
      expect(dataSaverAutoOnLabelKey(DATA_SAVER_FLAG_WHEN_ROAMING)).assertEqual('Roaming');
      // 主开关不进「自动开启」面板：给它一个空键，页面就不会多渲染一行
      expect(dataSaverAutoOnLabelKey(DATA_SAVER_FLAG_ENABLED)).assertEqual('');
      expect(dataSaverAutoOnLabelKey(0)).assertEqual('');
    });

    it('summary_fourStatesAndLoading', 0, () => {
      expect(dataSaverAutoOnSummaryKey(null)).assertEqual('Loading...');
      expect(dataSaverAutoOnSummaryKey(new DataSaverSettings(false, false, false)))
        .assertEqual('None');
      expect(dataSaverAutoOnSummaryKey(new DataSaverSettings(false, true, false)))
        .assertEqual('Mobile data');
      expect(dataSaverAutoOnSummaryKey(new DataSaverSettings(false, false, true)))
        .assertEqual('Roaming');
      expect(dataSaverAutoOnSummaryKey(new DataSaverSettings(false, true, true)))
        .assertEqual('Mobile and roaming');
      // 主开关与「自动开启」是两件事：手动开着时副标题仍按自动档描述
      expect(dataSaverAutoOnSummaryKey(new DataSaverSettings(true, false, false)))
        .assertEqual('None');
    });

    it('summary_readsThroughMasks', 0, () => {
      // 默认档来自存储掩码（Android 的默认就是「仅漫游」），不是页面写死的初值
      expect(dataSaverAutoOnSummaryKey(DataSaverSettings.fromMask(DATA_SAVER_FLAG_WHEN_ROAMING)))
        .assertEqual('Roaming');
      expect(dataSaverAutoOnSummaryKey(
        DataSaverSettings.fromMask(DATA_SAVER_FLAG_WHEN_MOBILE | DATA_SAVER_FLAG_WHEN_ROAMING)
      )).assertEqual('Mobile and roaming');
    });
  });
}
