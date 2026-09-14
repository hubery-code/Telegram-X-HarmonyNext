import { describe, it, expect } from '@ohos/hypium';
import {
  ThemeManager,
  LightTheme,
  DarkTheme,
  ThemePreference
} from '@tgx/core-design-system';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv } from '@tgx/feature-template';
import { SettingsThemeMode, SettingsUiState } from '../main/ets/contract/SettingsUiState';
import { ChangeThemeMode } from '../main/ets/contract/SettingsIntent';
import { ShowToastEffect } from '../main/ets/contract/SettingsEffect';
import { settingsReducer } from '../main/ets/reducer/SettingsReducer';

function makeEnv(): ReducerEnv {
  return {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('settings-theme-test-')
  };
}

export default function settingsThemeTest(): void {
  describe('SettingsThemeTest', () => {
    it('initialState_defaultsToSystem', 0, () => {
      ThemeManager.getInstance().reset();
      const state = SettingsUiState.initial();
      expect(state.themeMode).assertEqual('system');
    });

    it('initialState_acceptsExplicitThemePreference', 0, () => {
      const stateLight = SettingsUiState.initial('light');
      expect(stateLight.themeMode).assertEqual('light');

      const stateDark = SettingsUiState.initial('dark');
      expect(stateDark.themeMode).assertEqual('dark');

      const stateSystem = SettingsUiState.initial('system');
      expect(stateSystem.themeMode).assertEqual('system');
    });

    it('reducer_changeThemeMode_toDark_syncsGlobalThemeManager', 0, () => {
      ThemeManager.getInstance().reset();
      const state = SettingsUiState.initial('system');
      const result = settingsReducer(state, new ChangeThemeMode('dark'), makeEnv());

      expect(result.state.themeMode).assertEqual('dark');
      expect(ThemeManager.getInstance().getPreference()).assertEqual('dark');
      expect(ThemeManager.getInstance().getEffectiveTheme()).assertEqual(DarkTheme);
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as ShowToastEffect).message).assertEqual('Theme mode set to dark');
    });

    it('reducer_changeThemeMode_toLight_syncsGlobalThemeManager', 0, () => {
      ThemeManager.getInstance().reset();
      ThemeManager.getInstance().setPreference('dark');
      const state = SettingsUiState.initial('dark');
      const result = settingsReducer(state, new ChangeThemeMode('light'), makeEnv());

      expect(result.state.themeMode).assertEqual('light');
      expect(ThemeManager.getInstance().getPreference()).assertEqual('light');
      expect(ThemeManager.getInstance().getEffectiveTheme()).assertEqual(LightTheme);
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as ShowToastEffect).message).assertEqual('Theme mode set to light');
    });

    it('reducer_changeThemeMode_toSystem_syncsGlobalThemeManager', 0, () => {
      ThemeManager.getInstance().reset();
      ThemeManager.getInstance().setPreference('dark');
      const state = SettingsUiState.initial('dark');
      const result = settingsReducer(state, new ChangeThemeMode('system'), makeEnv());

      expect(result.state.themeMode).assertEqual('system');
      expect(ThemeManager.getInstance().getPreference()).assertEqual('system');
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as ShowToastEffect).message).assertEqual('Theme mode set to system');
    });

    it('reducer_changeThemeMode_sameMode_isNoOpAndEmitsZeroEffects', 0, () => {
      ThemeManager.getInstance().reset();
      ThemeManager.getInstance().setPreference('dark');
      const state = SettingsUiState.initial('dark');
      const result = settingsReducer(state, new ChangeThemeMode('dark'), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
      expect(ThemeManager.getInstance().getPreference()).assertEqual('dark');
    });

    it('themeManager_systemModeChange_updatesEffectiveThemeWhenPreferenceIsSystem', 0, () => {
      ThemeManager.getInstance().reset();
      const state = SettingsUiState.initial('system');
      expect(state.themeMode).assertEqual('system');

      ThemeManager.getInstance().setSystemMode('dark');
      expect(ThemeManager.getInstance().getEffectiveTheme()).assertEqual(DarkTheme);

      ThemeManager.getInstance().setSystemMode('light');
      expect(ThemeManager.getInstance().getEffectiveTheme()).assertEqual(LightTheme);
    });

    it('themePreference_typeEquivalence', 0, () => {
      const mode: SettingsThemeMode = 'system';
      const pref: ThemePreference = mode;
      expect(pref).assertEqual('system');
    });
  });
}
