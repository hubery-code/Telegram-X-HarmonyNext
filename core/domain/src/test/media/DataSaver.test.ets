/**
 * core/domain — 省流量（Data Saver）单元测试（AUTODL-102）。
 *
 * 守住的回归：
 * 1. 位序是唯一跨版本可存的约定（`settings_datasaver` 就一个整数），
 *    所以三位逐位点亮 + 0..7 全量往返；
 * 2. 默认档必须等于 Android 的兜底 —— 只勾「漫游时自动开启」
 *    （`TdlibFilesManager.java:1192`）。读盘失败时回落的是这份默认，
 *    而不是「三位全 0」，否则用户在漫游里会被静默放行下载；
 * 3. 判定表是下载门的全部依据：5 个网络档 × 3 位共 8 种组合逐格钉死；
 * 4. 漫游只在蜂窝下成立 —— 读不到漫游信息时落回 mobile（更保守的那一侧）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { NetworkSnapshot, NetworkTransport } from '@tgx/platform-ports';
import {
  DATA_SAVER_AUTO_ON_FLAGS,
  DATA_SAVER_FLAG_ENABLED,
  DATA_SAVER_FLAG_WHEN_MOBILE,
  DATA_SAVER_FLAG_WHEN_ROAMING,
  DataSaverNetworkType,
  DataSaverSettings,
  dataSaverNetworkOfSnapshot,
  isDataSaverActive
} from '../../main/ets/media/DataSaver';

function snapshot(connected: boolean, transport: NetworkTransport, roaming: boolean): NetworkSnapshot {
  return {
    connected: connected,
    transport: transport,
    metered: transport === 'cellular',
    roaming: roaming
  };
}

export default function dataSaverTest() {
  describe('DataSaver', () => {

    it('keeps_flag_bit_positions_stable', 0, () => {
      // 位值一改，盘上已有的整数就会把「移动网络」读成「漫游」。
      expect(DATA_SAVER_FLAG_ENABLED).assertEqual(1);
      expect(DATA_SAVER_FLAG_WHEN_MOBILE).assertEqual(2);
      expect(DATA_SAVER_FLAG_WHEN_ROAMING).assertEqual(4);
      expect(DATA_SAVER_AUTO_ON_FLAGS.length).assertEqual(2);
    });

    it('round_trips_every_mask', 0, () => {
      for (let mask = 0; mask <= 7; mask++) {
        const settings: DataSaverSettings = DataSaverSettings.fromMask(mask);
        expect(settings.toMask()).assertEqual(mask);
        expect(settings.enabled).assertEqual((mask & DATA_SAVER_FLAG_ENABLED) !== 0);
        expect(settings.whenMobile).assertEqual((mask & DATA_SAVER_FLAG_WHEN_MOBILE) !== 0);
        expect(settings.whenRoaming).assertEqual((mask & DATA_SAVER_FLAG_WHEN_ROAMING) !== 0);
      }
    });

    it('defaults_to_roaming_only_like_android', 0, () => {
      const d: DataSaverSettings = DataSaverSettings.defaultSettings();
      expect(d.enabled).assertFalse();
      expect(d.whenMobile).assertFalse();
      expect(d.whenRoaming).assertTrue();
      expect(d.toMask()).assertEqual(DATA_SAVER_FLAG_WHEN_ROAMING);
    });

    it('falls_back_to_default_on_unusable_mask', 0, () => {
      const bad: number[] = [-1, -100, Number.NaN, Number.POSITIVE_INFINITY];
      for (const mask of bad) {
        expect(DataSaverSettings.fromMask(mask).equals(DataSaverSettings.defaultSettings())).assertTrue();
      }
      // 高位（VoIP 那三位本端不建模）不参与判定，但掩码要按位与保留原值语义。
      expect(DataSaverSettings.fromMask(8).enabled).assertFalse();
    });

    it('covers_the_whole_veto_table', 0, () => {
      const networks: DataSaverNetworkType[] = ['none', 'wifi', 'mobile', 'roaming', 'other'];
      for (let mask = 0; mask <= 7; mask++) {
        const settings: DataSaverSettings = DataSaverSettings.fromMask(mask);
        for (const network of networks) {
          const expected: boolean = settings.enabled
            || (network === 'mobile' && settings.whenMobile)
            || (network === 'roaming' && settings.whenRoaming);
          expect(isDataSaverActive(settings, network)).assertEqual(expected);
        }
      }
    });

    it('treats_missing_settings_as_android_default', 0, () => {
      // 读盘失败/还没读：按默认档走，即只有漫游拦得住。
      expect(isDataSaverActive(null, 'roaming')).assertTrue();
      expect(isDataSaverActive(null, 'mobile')).assertFalse();
      expect(isDataSaverActive(null, 'wifi')).assertFalse();
      expect(isDataSaverActive(null, 'none')).assertFalse();
    });

    it('changes_one_flag_without_touching_the_others', 0, () => {
      const source: DataSaverSettings = DataSaverSettings.defaultSettings();
      const next: DataSaverSettings = source.withFlag(DATA_SAVER_FLAG_WHEN_MOBILE, true);
      expect(source.whenMobile).assertFalse();
      expect(next.whenMobile).assertTrue();
      expect(next.whenRoaming).assertTrue();
      expect(next.enabled).assertFalse();
      // 未知位（VoIP）不得当成主开关。
      const untouched: DataSaverSettings = source.withFlag(8, true);
      expect(untouched.toMask()).assertEqual(source.toMask());
    });

    it('summarises_auto_on_in_four_states', 0, () => {
      expect(DataSaverSettings.fromMask(0).autoOnSummaryKey()).assertEqual('None');
      expect(DataSaverSettings.fromMask(2).autoOnSummaryKey()).assertEqual('Mobile data');
      expect(DataSaverSettings.fromMask(4).autoOnSummaryKey()).assertEqual('Roaming');
      expect(DataSaverSettings.fromMask(6).autoOnSummaryKey()).assertEqual('Mobile and roaming');
    });

    it('maps_snapshot_to_network_type', 0, () => {
      expect(dataSaverNetworkOfSnapshot(null)).assertEqual('none');
      expect(dataSaverNetworkOfSnapshot(snapshot(false, 'wifi', false))).assertEqual('none');
      expect(dataSaverNetworkOfSnapshot(snapshot(true, 'wifi', false))).assertEqual('wifi');
      expect(dataSaverNetworkOfSnapshot(snapshot(true, 'ethernet', false))).assertEqual('wifi');
      expect(dataSaverNetworkOfSnapshot(snapshot(true, 'cellular', false))).assertEqual('mobile');
      expect(dataSaverNetworkOfSnapshot(snapshot(true, 'cellular', true))).assertEqual('roaming');
      expect(dataSaverNetworkOfSnapshot(snapshot(true, 'other', false))).assertEqual('other');
      // 契约上 roaming 只可能随蜂窝出现；真收到「Wi-Fi 漫游」也按 Wi-Fi 处理。
      expect(dataSaverNetworkOfSnapshot(snapshot(true, 'wifi', true))).assertEqual('wifi');
    });
  });
}
