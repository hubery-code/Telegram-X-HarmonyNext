/**
 * feature/settings — 模块公共导出（SET-101 + SET-104）。
 */

// Contract: UiState
export {
  SettingsThemeMode,
  SettingsUiStateOptions,
  SettingsUiState
} from './contract/SettingsUiState';

// Contract: Intent
export {
  UserProfileData,
  LoadUserProfile,
  ToggleNotifications,
  ToggleNotificationScope,
  LoadNotificationSettings,
  NotificationSettingsLoaded,
  NotificationSettingsUpdated,
  NotificationSettingsUpdateFailed,
  NotificationScopeUpdated,
  NotificationScopeUpdateFailed,
  ChangeThemeMode,
  RequestLogout,
  CancelLogout,
  ConfirmLogout,
  ClearCacheRequested,
  LoadStorageStats,
  StorageStatsLoaded,
  CacheCleared,
  ProfileLoaded,
  SetErrorMessage,
  SwitchAccount,
  RequestAddAccount,
  OpenAccountSwitcher,
  CloseAccountSwitcher,
  SetAvailableAccounts,
  OpenDevicesPage,
  CloseDevicesPage,
  SectionFocused,
  LoadActiveSessions,
  ActiveSessionsLoaded,
  ActiveSessionsLoadFailed,
  TerminateSessionIntent,
  TerminateAllOtherSessionsIntent,
  OpenPrivacyPage,
  ClosePrivacyPage,
  LoadPrivacySettings,
  PrivacySettingsLoaded,
  TogglePrivacySetting,
  PrivacySettingUpdated,
  PrivacySettingUpdateFailed,
  OpenPasscodePage,
  ClosePasscodePage,
  LoadPasscodeState,
  CancelPasscodeFlow,
  SettingsIntent
} from './contract/SettingsIntent';

// Contract: Effect
export {
  LoadProfileEffect,
  LoadNotificationSettingsEffect,
  SetNotificationsEnabledEffect,
  SetNotificationScopeEnabledEffect,
  LogoutEffect,
  ClearCacheEffect,
  LoadStorageStatsEffect,
  ShowToastEffect,
  NavigateToAuthEffect,
  SwitchAccountEffect,
  RequestAddAccountEffect,
  LoadActiveSessionsEffect,
  TerminateSessionEffect,
  TerminateAllOtherSessionsEffect,
  LoadPrivacySettingsEffect,
  SetPrivacySettingEffect,
  SettingsEffect
} from './contract/SettingsEffect';

// Model
export { ActiveSessionItem } from './model/ActiveSessionItem';
export { formatBytes, formatStorageLabel } from './model/StorageSize';
export {
  PrivacyChoice,
  PrivacySettingItem,
  PrivacySettingKey,
  PRIVACY_SETTING_KEYS,
  choiceFromRules,
  isPrivacyChoiceWritable,
  nextPrivacyChoice,
  privacyChoiceLabel,
  privacySettingLabel,
  rulesForChoice,
  toUserPrivacySetting
} from './model/PrivacySettings';
export {
  SettingsSectionKey,
  SettingsCardKey,
  parseSettingsSection,
  settingsSectionTitleKey,
  settingsCardsForSection,
  sectionShowsCard
} from './model/SettingsSection';
export {
  NotificationScopeKey,
  NOTIFICATIONS_MUTED_FOREVER_SECONDS,
  withNotificationsEnabled,
  areNotificationsEnabled,
  isNotificationScopeEnabled
} from './model/NotificationSettings';

// Reducer
export { settingsReducer } from './reducer/SettingsReducer';

// Coordinator
export {
  SettingsCoordinator,
  SettingsUiStateListener
} from './coordinator/SettingsCoordinator';

// UI Pages
export { SettingsPage, AVATAR_PALETTE } from './pages/SettingsPage';
export { DevicesSubPage, formatSessionDate } from './pages/DevicesSubPage';
export { PrivacySubPage } from './pages/PrivacySubPage';
export { PasscodeKeypad } from './pages/PasscodeKeypad';
export { PasscodeSubPage } from './pages/PasscodeSubPage';
