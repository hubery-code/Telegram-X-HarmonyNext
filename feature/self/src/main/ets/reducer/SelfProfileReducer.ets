/**
 * feature/self — 我的资料页纯 reducer（SELF-101）。
 *
 * 与 ProfileReducer 同约定：未知 kind 走尾部 default 原样返回；
 * EditTapped 是占位动作（协调器仅 log），不产生状态变更与效应；
 * SettingsSectionTapped 对白名单分区发 OpenSettingsSection，交装配层路由；
 * 资料获取由协调器 start() 直接驱动，
 * reducer 只负责状态回灌。
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { SelfProfileUiState } from '../contract/SelfProfileUiState';
import {
  OnProfileLoaded,
  OnAvatarFileLoaded,
  OnProfileFailed,
  SettingsSectionTapped,
  SelfProfileIntent
} from '../contract/SelfProfileIntent';
import { SelfProfileEffect, OpenSettingsSection } from '../contract/SelfProfileEffect';

/** 入口行可落地的设置分区；其余取值（含拼错的外部串）不产生效应。 */
const SELF_SETTINGS_SECTIONS: string[] = ['devices', 'notifications', 'data_and_storage', 'privacy'];

export function isSelfSettingsSection(section: string): boolean {
  return SELF_SETTINGS_SECTIONS.indexOf(section) >= 0;
}

export const selfProfileReducer: Reducer<SelfProfileUiState, SelfProfileIntent, SelfProfileEffect> = (
  state: SelfProfileUiState,
  intent: SelfProfileIntent,
  _env: ReducerEnv
): ReducerResult<SelfProfileUiState, SelfProfileEffect> => {
  switch (intent.kind) {
    case 'onProfileLoaded': {
      const loaded: OnProfileLoaded = intent as OnProfileLoaded;
      return reduced(state.copyWith({
        displayName: loaded.displayName,
        username: loaded.username,
        phone: loaded.phone,
        birthdayText: loaded.birthdayText,
        bio: loaded.bio,
        statusText: loaded.statusText,
        avatarLetters: loaded.avatarLetters,
        avatarColorIndex: loaded.avatarColorIndex,
        isLoading: false,
        errorMessage: null
      }));
    }

    case 'onAvatarFileLoaded': {
      const avatar: OnAvatarFileLoaded = intent as OnAvatarFileLoaded;
      return reduced(state.copyWith({ avatarPath: avatar.path }));
    }

    case 'onProfileFailed': {
      const failed: OnProfileFailed = intent as OnProfileFailed;
      return reduced(state.copyWith({ isLoading: false, errorMessage: failed.error.message }));
    }

    case 'editTapped':
      // 占位动作：编辑资料页尚未拆包，由协调器打日志。
      return reduced(state);

    case 'settingsSectionTapped': {
      const tapped: SettingsSectionTapped = intent as SettingsSectionTapped;
      if (!isSelfSettingsSection(tapped.section)) {
        return reduced(state);
      }
      return reduced(state, [new OpenSettingsSection(tapped.section)]);
    }

    default:
      return reduced(state);
  }
};
