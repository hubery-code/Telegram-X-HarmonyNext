/**
 * feature/self — 模块统一导出入口（SELF-101：我的资料页）。
 */

export { SelfProfileUiStateOptions, SelfProfileUiState } from './contract/SelfProfileUiState';
export {
  OnProfileLoaded,
  OnAvatarFileLoaded,
  OnProfileFailed,
  EditTapped,
  SettingsSectionTapped,
  SelfProfileIntent
} from './contract/SelfProfileIntent';
export { FetchMeEffect, SelfProfileEffect } from './contract/SelfProfileEffect';
export { selfProfileReducer } from './reducer/SelfProfileReducer';
export {
  SelfProfileCoordinatorOptions,
  SelfProfileUiStateListener,
  SelfProfileCoordinator
} from './coordinator/SelfProfileCoordinator';
export { SelfProfilePage } from './pages/SelfProfilePage';
