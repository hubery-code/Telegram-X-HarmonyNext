/**
 * feature/settings — 模块公共导出（SET-101）。
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
  CacheCleared,
  ProfileLoaded,
  SetErrorMessage,
  SettingsIntent
} from './contract/SettingsIntent';

// Contract: Effect
export {
  LoadProfileEffect,
  LogoutEffect,
  ClearCacheEffect,
  ShowToastEffect,
  NavigateToAuthEffect,
  SettingsEffect
} from './contract/SettingsEffect';

// Reducer
export { settingsReducer } from './reducer/SettingsReducer';

// Coordinator
export {
  SettingsCoordinator,
  SettingsUiStateListener
} from './coordinator/SettingsCoordinator';

// UI Pages
export { SettingsPage, AVATAR_PALETTE } from './pages/SettingsPage';
