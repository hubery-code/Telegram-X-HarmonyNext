import { describe, it, expect } from '@ohos/hypium';
import {
  ThemeManager,
  LightTheme,
  DarkTheme,
  ThemePreference,
  themeModeFromColorMode,
  themePreferenceFromStored
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
      const toast: ShowToastEffect = result.effects[0] as ShowToastEffect;
      expect(toast.messageKey).assertEqual('Theme mode set to {0}');
      expect(String(toast.args[0])).assertEqual('dark');
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
      const toast: ShowToastEffect = result.effects[0] as ShowToastEffect;
      expect(toast.messageKey).assertEqual('Theme mode set to {0}');
      expect(String(toast.args[0])).assertEqual('light');
    });

    it('reducer_changeThemeMode_toSystem_syncsGlobalThemeManager', 0, () => {
      ThemeManager.getInstance().reset();
      ThemeManager.getInstance().setPreference('dark');
      const state = SettingsUiState.initial('dark');
      const result = settingsReducer(state, new ChangeThemeMode('system'), makeEnv());

      expect(result.state.themeMode).assertEqual('system');
      expect(ThemeManager.getInstance().getPreference()).assertEqual('system');
      expect(result.effects.length).assertEqual(1);
      const toast: ShowToastEffect = result.effects[0] as ShowToastEffect;
      expect(toast.messageKey).assertEqual('Theme mode set to {0}');
      expect(String(toast.args[0])).assertEqual('system');
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

    /**
     * APPSTORAGE-PAIR-101：`EntryAbility.hydrateTheme()` 的四步（读盘 → 校验回落 →
     * setSystemMode → setPreference）在这里可复现，因为它全程只用公开 API。
     *
     * 钉的是最易失的那一格：**偏好为 'system' 且系统深色**。'system' 与构造默认值
     * 相同，`setPreference` 会同值直接返回，所以这一格的深浅完全由 `setSystemMode`
     * 决定——而它此前全仓零调用者，于是这一格恒为浅色。
     */
    it('hydrateSequence_systemPreferenceWithDarkSystem_landsDark', 0, () => {
      const tm: ThemeManager = ThemeManager.getInstance();
      tm.reset();

      const storedPreference: string | null = 'system';
      const storedColorMode: number = 0;
      tm.setSystemMode(themeModeFromColorMode(storedColorMode));
      tm.setPreference(themePreferenceFromStored(storedPreference));

      expect(tm.getPreference()).assertEqual('system');
      expect(tm.getSystemMode()).assertEqual('dark');
      expect(tm.getEffectiveTheme()).assertEqual(DarkTheme);
    });

    /**
     * 同一串步骤在盘上什么都没有时（首装）必须回到浅色 + 跟随系统，
     * 且**不许**落到某个显式档位——显式档位会把「跟随系统」永久改写。
     */
    it('hydrateSequence_withoutDiskValue_staysSystemLight', 0, () => {
      const tm: ThemeManager = ThemeManager.getInstance();
      tm.reset();

      tm.setSystemMode(themeModeFromColorMode(null));
      tm.setPreference(themePreferenceFromStored(null));

      expect(tm.getPreference()).assertEqual('system');
      expect(tm.getEffectiveTheme()).assertEqual(LightTheme);
      tm.reset();
    });

    /**
     * 抽屉夜间模式开关是 reducer 之外的第二条主题写入路径（entry/pages/Index.ets）。
     * 它写的必须是**偏好**串的同一套词表，否则落盘的值在读盘侧会被当脏值丢掉。
     */
    it('drawerBucketValues_areValidPreferences', 0, () => {
      expect(themePreferenceFromStored('dark')).assertEqual('dark');
      expect(themePreferenceFromStored('light')).assertEqual('light');
      const drawerOn: boolean = true;
      const drawerOff: boolean = false;
      const asPreference: ThemePreference = themePreferenceFromStored(drawerOn ? 'dark' : 'light');
      expect(asPreference).assertEqual('dark');
      expect(themePreferenceFromStored(drawerOff ? 'dark' : 'light')).assertEqual('light');
    });
  });
}
