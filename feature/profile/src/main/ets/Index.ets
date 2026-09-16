/**
 * feature/profile — 模块统一导出入口（PROFILE-101：群聊点头像查看用户资料）。
 */

export { ProfileUiStateOptions, ProfileUiState } from './contract/ProfileUiState';
export {
  MessageUserRequested,
  OnProfileLoaded,
  OnBioLoaded,
  OnAvatarFileLoaded,
  OnProfileFailed,
  ProfileIntent
} from './contract/ProfileIntent';
export { CreatePrivateChatEffect, ProfileEffect } from './contract/ProfileEffect';
export { profileReducer } from './reducer/ProfileReducer';
export {
  ProfileCoordinatorOptions,
  ProfileUiStateListener,
  ProfileCoordinator
} from './coordinator/ProfileCoordinator';
export { ProfilePage } from './pages/ProfilePage';
