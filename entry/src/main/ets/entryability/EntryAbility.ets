import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { bootstrap, BootstrapResult } from '../Bootstrap';
import { TdlibParametersConfig } from '@tgx/feature-auth';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate — bootstrapping TDLib + AuthCoordinator');

    const filesDir: string = this.context.filesDir;
    const cacheDir: string = this.context.cacheDir;

    const tdlibParams: TdlibParametersConfig = {
      apiId: 21724,
      apiHash: '3e0cb5efcd52300aec5994fdfc5bdc16',
      databaseDirectory: `${filesDir}/tdlib/db`,
      filesDirectory: `${filesDir}/tdlib/files`,
      systemLanguageCode: 'en',
      deviceModel: 'HarmonyOS NEXT',
      applicationVersion: '0.1.0',
      useTestDc: false
    };

    try {
      const result: BootstrapResult = bootstrap(filesDir, cacheDir, tdlibParams);
      result.coordinator.start();
      AppStorage.setOrCreate<BootstrapResult>('bootstrapResult', result);
      hilog.info(DOMAIN, TAG, 'bootstrap succeeded — coordinator started');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'bootstrap failed: %{public}s', String(e));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
    const result: BootstrapResult | undefined = AppStorage.get<BootstrapResult>('bootstrapResult');
    if (result !== undefined && result !== null) {
      result.coordinator.destroy();
      result.registry.stop();
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadContent succeeded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }
}
