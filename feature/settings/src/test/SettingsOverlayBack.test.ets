/**
 * feature/settings — 覆盖层物理返回键收口的单测（SET-BACK-101）。
 *
 * 断言的是**层级**，不是各个关闭意图自己的语义（那些由 SettingsReducer / PrivacySettings 覆盖）：
 * 谁的在最上面就先关谁，且覆盖层全空时必须交回 null 让 entry 去 pop。
 */

import { describe, it, expect } from '@ohos/hypium';
import { SettingsUiState } from '../main/ets/contract/SettingsUiState';
import { PrivacyDetailState } from '../main/ets/model/PrivacyDetail';
import { settingsOverlayCloseIntent } from '../main/ets/model/SettingsOverlayBack';

function detail(pickerTarget: 'always' | 'never' | null): PrivacyDetailState {
  return PrivacyDetailState.forLoading('show_last_seen').copyWith({ pickerTarget: pickerTarget });
}

export default function settingsOverlayBackTest(): void {
  describe('SettingsOverlayBack', () => {
    it('idle_returnsNullSoRouterPops', 0, () => {
      expect(settingsOverlayCloseIntent(SettingsUiState.initial())).assertNull();
    });

    it('devicesPage_closesDevicesOnly', 0, () => {
      const state: SettingsUiState = SettingsUiState.initial().copyWith({ showDevicesPage: true });
      expect(settingsOverlayCloseIntent(state)?.kind).assertEqual('closeDevicesPage');
    });

    it('proxyPage_closesProxy', 0, () => {
      // 这两层是原来那串 if 漏掉的：返回键直接把设置页 pop 掉，子页留在状态里。
      const state: SettingsUiState = SettingsUiState.initial().copyWith({ showProxyPage: true });
      expect(settingsOverlayCloseIntent(state)?.kind).assertEqual('closeProxyPage');
    });

    it('autoDownloadPage_closesAutoDownload', 0, () => {
      const state: SettingsUiState =
        SettingsUiState.initial().copyWith({ showAutoDownloadPage: true });
      expect(settingsOverlayCloseIntent(state)?.kind).assertEqual('closeAutoDownloadPage');
    });

    it('privacyList_closesPrivacyPage', 0, () => {
      const state: SettingsUiState = SettingsUiState.initial().copyWith({ showPrivacyPage: true });
      expect(settingsOverlayCloseIntent(state)?.kind).assertEqual('closePrivacyPage');
    });

    it('privacyDetail_closesKeyPageNotList', 0, () => {
      // 关键一条：详情页压在列表页之上，只能派 closePrivacyKeyPage ——
      // closePrivacyPage 会把 privacyDetail 直接置 null，未提交的规则改动就丢了写回时机。
      const state: SettingsUiState = SettingsUiState.initial().copyWith({
        showPrivacyPage: true,
        privacyDetail: detail(null)
      });
      expect(settingsOverlayCloseIntent(state)?.kind).assertEqual('closePrivacyKeyPage');
    });

    it('privacyPicker_closesPickerBeforeDetail', 0, () => {
      const state: SettingsUiState = SettingsUiState.initial().copyWith({
        showPrivacyPage: true,
        privacyDetail: detail('always')
      });
      expect(settingsOverlayCloseIntent(state)?.kind).assertEqual('closePrivacyPicker');
    });

    it('passcodeKeyboard_cancelsFlowBeforeLeavingPage', 0, () => {
      const page: SettingsUiState = SettingsUiState.initial().copyWith({ showPasscodePage: true });
      expect(settingsOverlayCloseIntent(page)?.kind).assertEqual('closePasscodePage');
      const keypad: SettingsUiState = page.copyWith({ passcodeFlow: 'enter' });
      expect(settingsOverlayCloseIntent(keypad)?.kind).assertEqual('cancelPasscodeFlow');
    });

    it('passcodeBeatsEverythingBelowIt', 0, () => {
      // 应用锁页在 Stack 里最上，所以哪怕代理页也开着，先关的仍是它。
      const state: SettingsUiState = SettingsUiState.initial().copyWith({
        showPasscodePage: true,
        showProxyPage: true,
        showAutoDownloadPage: true
      });
      expect(settingsOverlayCloseIntent(state)?.kind).assertEqual('closePasscodePage');
    });

    it('logoutConfirm_closesBeforeAccountSwitcher', 0, () => {
      const state: SettingsUiState = SettingsUiState.initial().copyWith({
        showAccountSwitcher: true,
        showLogoutConfirm: true
      });
      expect(settingsOverlayCloseIntent(state)?.kind).assertEqual('cancelLogout');
      const switcherOnly: SettingsUiState =
        SettingsUiState.initial().copyWith({ showAccountSwitcher: true });
      expect(settingsOverlayCloseIntent(switcherOnly)?.kind).assertEqual('closeAccountSwitcher');
    });

    it('staysDeterministicWithEverythingOpen', 0, () => {
      // 一次只关一层：连续调用的结果序列就是用户连按返回键应看到的路径。
      let state: SettingsUiState = SettingsUiState.initial().copyWith({
        showPasscodePage: true,
        showProxyPage: true,
        showAutoDownloadPage: true,
        showDevicesPage: true,
        showPrivacyPage: true,
        showAccountSwitcher: true,
        showLogoutConfirm: true
      });
      const kinds: string[] = [];
      for (let i = 0; i < 20; i++) {
        const intent = settingsOverlayCloseIntent(state);
        if (intent === null) {
          break;
        }
        kinds.push(intent.kind);
        state = closeOverlay(state, intent.kind);
      }
      expect(kinds.join(',')).assertEqual([
        'closePasscodePage', 'closeAutoDownloadPage', 'closeProxyPage',
        'closePrivacyPage', 'closeDevicesPage', 'cancelLogout', 'closeAccountSwitcher'
      ].join(','));
    });
  });
}

/** 测试内的「这一层关掉了」：只翻转对应标志，语义与 reducer 的关闭分支一致。 */
function closeOverlay(state: SettingsUiState, kind: string): SettingsUiState {
  if (kind === 'closePasscodePage') {
    return state.copyWith({ showPasscodePage: false });
  }
  if (kind === 'closeAutoDownloadPage') {
    return state.copyWith({ showAutoDownloadPage: false });
  }
  if (kind === 'closeProxyPage') {
    return state.copyWith({ showProxyPage: false });
  }
  if (kind === 'closePrivacyPage') {
    return state.copyWith({ showPrivacyPage: false });
  }
  if (kind === 'closeDevicesPage') {
    return state.copyWith({ showDevicesPage: false });
  }
  if (kind === 'cancelLogout') {
    return state.copyWith({ showLogoutConfirm: false });
  }
  return state.copyWith({ showAccountSwitcher: false });
}
