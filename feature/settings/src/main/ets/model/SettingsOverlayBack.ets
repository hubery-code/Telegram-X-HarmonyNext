/**
 * feature/settings — 覆盖层的物理返回键收口（SET-BACK-101）。
 *
 * 设置页的每一种子页/弹层都是 `SettingsPage.build()` 里叠在同一层 Stack 上的**覆盖层**，
 * 不是导航栈里的页面 —— 所以硬件返回键不会自动关它们。之前 `entry` 里手写了一串
 * `if (showX) dispatch(new CloseX())`，漏了代理、自动下载和隐私详情页三层，
 * 后果不是「退多了」而是**丢数据**：隐私详情页的写回时机在 `closePrivacyKeyPage`
 * 上（Android 是 `SettingsPrivacyKeyController.onBlur() → saveChanges()`），
 * 而 `closePrivacyPage` 只把 `privacyDetail` 置 null，于是一按返回，未提交的规则改动
 * 一声不响地被丢掉。
 *
 * 所以顺序只有一条来源：`SettingsPage` 的渲染顺序（后渲染的在上层）反过来，
 * 最上层先关。改覆盖层叠放次序时，这里必须一起改 —— 两处真相就在这个函数收成一处。
 */

import {
  SettingsIntent,
  CancelLogout,
  CancelPasscodeFlow,
  CloseAccountSwitcher,
  CloseAutoDownloadPage,
  CloseDevicesPage,
  ClosePasscodePage,
  ClosePrivacyKeyPage,
  ClosePrivacyPage,
  ClosePrivacyPicker,
  CloseProxyPage
} from '../contract/SettingsIntent';
import { SettingsUiState } from '../contract/SettingsUiState';
import { PrivacyDetailState } from './PrivacyDetail';

/**
 * 返回这一次物理返回键应当派发的关闭意图；`null` 表示当前没有任何覆盖层，
 * 调用方（`entry`）才放行真正的路由 pop。
 */
export function settingsOverlayCloseIntent(state: SettingsUiState): SettingsIntent | null {
  if (state.showPasscodePage) {
    // 键盘弹着时先收键盘，再退子页 —— 和 Android 的 PasscodeActivity 一致。
    return state.passcodeFlow === 'idle' ? new ClosePasscodePage() : new CancelPasscodeFlow();
  }
  if (state.showAutoDownloadPage) {
    return new CloseAutoDownloadPage();
  }
  if (state.showProxyPage) {
    return new CloseProxyPage();
  }
  const detail: PrivacyDetailState | null = state.privacyDetail;
  if (detail !== null) {
    // 多选器开在详情页之上；详情页再压在隐私列表之上。
    // 关详情页就是「离开这一页」，reducer 在那一刻才把改动写回服务端。
    return detail.pickerTarget === null ? new ClosePrivacyKeyPage() : new ClosePrivacyPicker();
  }
  if (state.showPrivacyPage) {
    return new ClosePrivacyPage();
  }
  if (state.showDevicesPage) {
    return new CloseDevicesPage();
  }
  // 确认弹窗画在账号切换面板之上（SettingsPage 的 Stack 顺序），所以先关它。
  if (state.showLogoutConfirm) {
    return new CancelLogout();
  }
  if (state.showAccountSwitcher) {
    return new CloseAccountSwitcher();
  }
  return null;
}
