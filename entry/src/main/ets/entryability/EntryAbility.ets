import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { bootstrap, BootstrapResult } from '../Bootstrap';
import { appDeepLinkQueue } from '../deeplink/DeepLinkQueue';
import { TdlibParametersConfig } from '@tgx/feature-auth';
import { TELEGRAM_CREDENTIALS } from '../config/AppCredentials';
import { initSettingsStore, loadChatFontSize, KEY_CHAT_FONT_SIZE } from '../store/SettingsStore';
import { AppLockGate } from '../applock/AppLockGate';
import { appLockGate, installAppLock } from '../applock/AppLockWiring';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate — bootstrapping TDLib + AuthCoordinator');

    // DEEPLINK-101：冷启动的链接比页面早到（loadContent 还没跑），先入队，
    // 等 pages/Index 进过 home 再补投。这里只记长度——uri 可携带邀请哈希。
    this.captureWantUri(want, 'onCreate');

    const filesDir: string = this.context.filesDir;
    const cacheDir: string = this.context.cacheDir;

    const tdlibParams: TdlibParametersConfig = {
      apiId: TELEGRAM_CREDENTIALS.apiId,
      apiHash: TELEGRAM_CREDENTIALS.apiHash,
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
      result.lifecycle.onDestroy();
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // DEEPLINK-101：热启动（应用已在后台，从别处点 Telegram 链接进来）。
    hilog.info(DOMAIN, TAG, 'onNewWant');
    this.captureWantUri(want, 'onNewWant');
  }

  /**
   * 把 want 里的链接交给深链队列。
   *
   * 日志只记长度与来源，**不记 uri 正文**：`t.me/+inviteHash` 里的哈希等同凭证，
   * 与本仓 `openLink failed` 只记事件不记 URL 的既有口径一致。
   */
  private captureWantUri(want: Want, source: string): void {
    const uri: string | undefined = want.uri;
    if (uri === undefined || uri === null || uri.trim().length === 0) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'want uri from %{public}s, length=%{public}d', source, uri.trim().length);
    appDeepLinkQueue.enqueue(uri);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // SET-105 / FEAT-UI-002：把聊天字号接入磁盘持久化。
    //
    // 这里用 `preferences` Kit（见 store/SettingsStore.ets）而不是 ArkUI 的
    // `PersistentStorage.persistProp`——后者在这套 SDK 上「写盘成功、恢复静默
    // 失败」（详细实测记录见 SettingsStore.ets 顶部注释）。
    //
    // 时序要点：必须在 `loadContent` 之前把盘上的值灌进 AppStorage，
    // 页面 aboutToAppear 才能读到；否则首帧会先按默认档渲染再跳一次。
    initSettingsStore(this.context);
    const restoredChatFontSize: number = loadChatFontSize();
    AppStorage.setOrCreate<string>(KEY_CHAT_FONT_SIZE, `${restoredChatFontSize}`);
    hilog.info(DOMAIN, TAG, 'chatFontSize restored: %{public}s', `${restoredChatFontSize}`);

    // 应用锁（APPLOCK-101）：自动锁定档位存在上面那条 preferences 盘上，
    // 所以装配必须排在 initSettingsStore 之后；bootstrap() 决定「这次起来要不要锁」，
    // 必须排在 loadContent 之前，否则解锁前会闪一帧主界面。
    if (installAppLock(AppStorage.get<BootstrapResult>('bootstrapResult'))) {
      const appLock: AppLockGate | null | undefined = appLockGate();
      if (appLock !== null && appLock !== undefined) {
        appLock.bootstrap();
      }
    }

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
    const result: BootstrapResult | undefined = AppStorage.get<BootstrapResult>('bootstrapResult');
    if (result !== undefined && result !== null) {
      result.lifecycle.onForeground();
    }
    // 应用锁：回到前台先问一次「该锁吗」，判定用的是后台时长，不是这里的调用时机。
    const appLock: AppLockGate | null = appLockGate();
    if (appLock !== null) {
      appLock.onForeground();
    }
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
    const result: BootstrapResult | undefined = AppStorage.get<BootstrapResult>('bootstrapResult');
    if (result !== undefined && result !== null) {
      result.lifecycle.onBackground();
    }
    const appLock: AppLockGate | null = appLockGate();
    if (appLock !== null) {
      appLock.onBackground();
    }
  }
}
