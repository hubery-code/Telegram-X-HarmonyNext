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
  OnBirthdayLoaded,
  OnSharedTabSelected,
  OnSharedContentLoaded,
  OnSharedGroupsLoaded,
  OnSharedContentFailed,
  OpenSharedChatRequested,
  ProfileIntent
} from './contract/ProfileIntent';
export {
  CreatePrivateChatEffect,
  FetchSharedContent,
  FetchSharedGroups,
  FetchMoreSharedContent,
  OpenSharedChatEffect,
  ProfileEffect
} from './contract/ProfileEffect';
export {
  SharedMediaItem,
  SharedFileItem,
  SharedLinkItem,
  SharedGroupItem
} from './contract/SharedContentItems';
export { profileReducer } from './reducer/ProfileReducer';
export {
  ProfileCoordinatorOptions,
  ProfileUiStateListener,
  ProfileCoordinator
} from './coordinator/ProfileCoordinator';
export { ProfilePage } from './pages/ProfilePage';

// PROFILE-102：群聊/频道资料页导出
export {
  ChatMemberUiItem,
  ChatProfileUiStateOptions,
  ChatProfileUiState
} from './contract/ChatProfileUiState';
export {
  ChatProfileIntent,
  OpenChatProfile,
  OnChatLoaded,
  OnBasicGroupFullInfoLoaded,
  OnSupergroupFullInfoLoaded,
  OnChatMembersLoaded,
  OnChatAvatarLoaded,
  OnChatProfileError,
  SelectChatMember,
  CopyInviteLinkRequested,
  BackRequested
} from './contract/ChatProfileIntent';
export {
  ChatProfileEffect,
  FetchChatDetailsEffect,
  NavigateToUserProfileEffect,
  CopyInviteLinkEffect,
  NavigateBackEffect
} from './contract/ChatProfileEffect';
export { chatProfileReducer } from './reducer/ChatProfileReducer';
export {
  ChatProfileCoordinatorOptions,
  ChatProfileCoordinator
} from './coordinator/ChatProfileCoordinator';
export { ChatProfilePage } from './pages/ChatProfilePage';
