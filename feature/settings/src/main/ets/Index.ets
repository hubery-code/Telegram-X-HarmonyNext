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
  SettingsIntent
} from './contract/SettingsIntent';

// Contract: Effect
export {
  LoadProfileEffect,
  LogoutEffect,
  ClearCacheEffect,
  LoadStorageStatsEffect,
  ShowToastEffect,
  NavigateToAuthEffect,
  SwitchAccountEffect,
  RequestAddAccountEffect,
  SettingsEffect
} from './contract/SettingsEffect';

// Model
export { formatBytes, formatStorageLabel } from './model/StorageSize';

// Reducer
export { settingsReducer } from './reducer/SettingsReducer';

// Coordinator
export {
  SettingsCoordinator,
  SettingsUiStateListener
} from './coordinator/SettingsCoordinator';

// UI Pages
export { SettingsPage, AVATAR_PALETTE } from './pages/SettingsPage';
