import { describe, it, expect } from '@ohos/hypium';
import {
  Theme,
  LightTheme,
  DarkTheme
} from '../main/ets/Theme';
import {
  ThemeManager,
  resolveTheme,
  resolveThemeMode,
  themeModeFromColorMode,
  themePreferenceFromStored
} from '../main/ets/ThemeManager';

export default function themeManagerTest(): void {
  describe('ThemeManagerTest', () => {
    it('resolveThemeMode_lightPreferenceAlwaysResolvesLight', 0, () => {
      expect(resolveThemeMode('light', 'light')).assertEqual('light');
      expect(resolveThemeMode('light', 'dark')).assertEqual('light');
    });

    it('resolveThemeMode_darkPreferenceAlwaysResolvesDark', 0, () => {
      expect(resolveThemeMode('dark', 'light')).assertEqual('dark');
      expect(resolveThemeMode('dark', 'dark')).assertEqual('dark');
    });

    it('resolveThemeMode_systemPreferenceFollowsSystemMode', 0, () => {
      expect(resolveThemeMode('system', 'light')).assertEqual('light');
      expect(resolveThemeMode('system', 'dark')).assertEqual('dark');
      expect(resolveThemeMode('system')).assertEqual('light');
    });

    it('resolveTheme_returnsCorrectThemeInstances', 0, () => {
      expect(resolveTheme('light', 'light')).assertEqual(LightTheme);
      expect(resolveTheme('dark', 'light')).assertEqual(DarkTheme);
      expect(resolveTheme('system', 'dark')).assertEqual(DarkTheme);
      expect(resolveTheme('system', 'light')).assertEqual(LightTheme);

      const scaledTheme = resolveTheme('light', 'light', 1.5);
      expect(scaledTheme.fontScale).assertEqual(1.5);
      expect(scaledTheme.mode).assertEqual('light');
    });

    it('initial_hasSystemPreferenceAndLightEffective', 0, () => {
      const tm = new ThemeManager();
      expect(tm.getPreference()).assertEqual('system');
      expect(tm.getSystemMode()).assertEqual('light');
      expect(tm.getEffectiveMode()).assertEqual('light');
      expect(tm.getTheme()).assertEqual(LightTheme);
    });

    it('themeManager_setPreference_updatesThemeAndNotifies', 0, () => {
      const tm = new ThemeManager();
      let notifiedTheme: Theme | null = null;
      let callCount: number = 0;

      tm.subscribe((theme: Theme): void => {
        notifiedTheme = theme;
        callCount++;
      });

      tm.setPreference('dark');
      expect(callCount).assertEqual(1);
      expect(notifiedTheme).assertEqual(DarkTheme);
      expect(tm.getPreference()).assertEqual('dark');
      expect(tm.getEffectiveMode()).assertEqual('dark');

      tm.setPreference('light');
      expect(callCount).assertEqual(2);
      expect(notifiedTheme).assertEqual(LightTheme);
      expect(tm.getPreference()).assertEqual('light');
      expect(tm.getEffectiveMode()).assertEqual('light');
    });

    it('themeManager_setPreference_samePreferenceIsNoOp', 0, () => {
      const tm = new ThemeManager('dark');
      let callCount: number = 0;

      tm.subscribe((_theme: Theme): void => {
        callCount++;
      });

      tm.setPreference('dark');
      expect(callCount).assertEqual(0);
    });

    it('themeManager_setSystemMode_withSystemPreference_updatesThemeAndNotifies', 0, () => {
      const tm = new ThemeManager('system', 'light');
      let notifiedTheme: Theme | null = null;
      let callCount: number = 0;

      tm.subscribe((theme: Theme): void => {
        notifiedTheme = theme;
        callCount++;
      });

      tm.setSystemMode('dark');
      expect(callCount).assertEqual(1);
      expect(notifiedTheme).assertEqual(DarkTheme);
      expect(tm.getEffectiveMode()).assertEqual('dark');

      tm.setSystemColorMode('light');
      expect(callCount).assertEqual(2);
      expect(notifiedTheme).assertEqual(LightTheme);
      expect(tm.getEffectiveMode()).assertEqual('light');
    });

    it('themeManager_setSystemMode_withExplicitPreference_doesNotChangeTheme', 0, () => {
      const tm = new ThemeManager('dark', 'light');
      let callCount: number = 0;

      tm.subscribe((_theme: Theme): void => {
        callCount++;
      });

      tm.setSystemMode('dark');
      expect(callCount).assertEqual(0);
      expect(tm.getEffectiveMode()).assertEqual('dark');

      tm.setSystemMode('light');
      expect(callCount).assertEqual(0);
      expect(tm.getEffectiveMode()).assertEqual('dark');
    });

    it('themeManager_subscribe_unsubscribeStopsNotifications', 0, () => {
      const tm = new ThemeManager();
      let callCount1: number = 0;
      let callCount2: number = 0;

      const unsub1 = tm.subscribe((_theme: Theme): void => {
        callCount1++;
      });

      const listener2 = (_theme: Theme): void => {
        callCount2++;
      };
      tm.subscribe(listener2);

      tm.setPreference('dark');
      expect(callCount1).assertEqual(1);
      expect(callCount2).assertEqual(1);

      unsub1();
      tm.unsubscribe(listener2);

      tm.setPreference('light');
      expect(callCount1).assertEqual(1);
      expect(callCount2).assertEqual(1);
    });

    it('themeManager_subscribe_notifyImmediatelyCallsListener', 0, () => {
      const tm = new ThemeManager('dark');
      let initialTheme: Theme | null = null;

      tm.subscribe((theme: Theme): void => {
        initialTheme = theme;
      }, true);

      expect(initialTheme).assertEqual(DarkTheme);
    });

    it('themeManager_setFontScale_updatesEffectiveTheme', 0, () => {
      const tm = new ThemeManager('light');
      tm.setFontScale(1.5);
      expect(tm.getFontScale()).assertEqual(1.5);
      expect(tm.getTheme().fontScale).assertEqual(1.5);
    });

    it('themeManager_reset_restoresDefaults', 0, () => {
      const tm = new ThemeManager('dark', 'dark', 1.5);
      let callCount: number = 0;
      tm.subscribe((_theme: Theme): void => {
        callCount++;
      });

      tm.reset();
      expect(tm.getPreference()).assertEqual('system');
      expect(tm.getSystemMode()).assertEqual('light');
      expect(tm.getFontScale()).assertEqual(1.0);
      expect(tm.getEffectiveMode()).assertEqual('light');

      tm.setPreference('dark');
      expect(callCount).assertEqual(0);
    });

    it('themePreferenceFromStored_acceptsOnlyTheThreeBuckets', 0, () => {
      expect(themePreferenceFromStored('system')).assertEqual('system');
      expect(themePreferenceFromStored('light')).assertEqual('light');
      expect(themePreferenceFromStored('dark')).assertEqual('dark');
    });

    /**
     * APPSTORAGE-PAIR-101：读盘侧的兜底语义。
     *
     * 缺值与脏值都回 'system'，**不回 'light' 也不回 'dark'**——显式档位会永久改写
     * 「跟随系统」这个语义，用户下一次就没法回到跟随了。'light'/'dark' 这两个
     * 解析结果形状的输入同样按脏值处理，防止有人误把 ThemeMode 存进偏好键。
     */
    it('themePreferenceFromStored_neverFallsBackToAnExplicitBucket', 0, () => {
      expect(themePreferenceFromStored(null)).assertEqual('system');
      expect(themePreferenceFromStored(undefined)).assertEqual('system');
      expect(themePreferenceFromStored('')).assertEqual('system');
      expect(themePreferenceFromStored('System')).assertEqual('system');
      expect(themePreferenceFromStored('auto')).assertEqual('system');
      expect(themePreferenceFromStored('  dark  ')).assertEqual('system');
    });

    /**
     * `COLOR_MODE_DARK` 是数字 **0**，所以判定必须是等值比较而非真值判断。
     * 这是本包最容易写错的一行：`if (colorMode)` 会把深色当成假。
     */
    it('themeModeFromColorMode_treatsZeroAsDark', 0, () => {
      expect(themeModeFromColorMode(0)).assertEqual('dark');
      expect(themeModeFromColorMode(1)).assertEqual('light');
    });

    it('themeModeFromColorMode_unreadableAndNotSetResolveLight', 0, () => {
      expect(themeModeFromColorMode(null)).assertEqual('light');
      expect(themeModeFromColorMode(undefined)).assertEqual('light');
      // COLOR_MODE_NOT_SET：系统没告知，按 ThemeManager 的构造默认档（light）收，
      // 不引入第三种状态。
      expect(themeModeFromColorMode(-1)).assertEqual('light');
    });

    /**
     * APPSTORAGE-PAIR-101：`setSystemMode` 此前在全仓**零调用者**，于是「跟随系统」
     * 恒解析为浅色。这组用例把这条门的正确行为钉住，EntryAbility 的
     * hydrateTheme/onConfigurationUpdate 是它的两个新调用点。
     */
    it('themeManager_setSystemMode_movesEffectiveThemeUnderSystemPreference', 0, () => {
      const tm = new ThemeManager();
      let callCount: number = 0;
      tm.subscribe((_theme: Theme): void => {
        callCount++;
      });

      tm.setSystemMode('dark');
      expect(callCount).assertEqual(1);
      expect(tm.getEffectiveMode()).assertEqual('dark');
      expect(tm.getTheme()).assertEqual(DarkTheme);

      // 同值不重复通知——回灌与 onConfigurationUpdate 都会被系统反复触发。
      tm.setSystemMode('dark');
      expect(callCount).assertEqual(1);
    });

    it('themeManager_setSystemMode_doesNotOverrideExplicitPreference', 0, () => {
      const tm = new ThemeManager('light');
      let callCount: number = 0;
      tm.subscribe((_theme: Theme): void => {
        callCount++;
      });

      tm.setSystemMode('dark');
      expect(callCount).assertEqual(0);
      expect(tm.getEffectiveMode()).assertEqual('light');
    });
  });
}
