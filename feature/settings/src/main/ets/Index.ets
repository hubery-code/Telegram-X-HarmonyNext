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
  LoadActiveSessions,
  ActiveSessionsLoaded,
  ActiveSessionsLoadFailed,
  TerminateSessionIntent,
  TerminateAllOtherSessionsIntent,
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
  SettingsEffect
} from './contract/SettingsEffect';

// Model
export { ActiveSessionItem } from './model/ActiveSessionItem';
export { formatBytes, formatStorageLabel } from './model/StorageSize';
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
