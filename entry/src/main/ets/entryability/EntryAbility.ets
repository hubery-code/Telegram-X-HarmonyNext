import { AbilityConstant, bundleManager, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { bootstrap, BootstrapResult } from '../Bootstrap';
import { appDeepLinkQueue } from '../deeplink/DeepLinkQueue';
import { TdlibParametersConfig } from '@tgx/feature-auth';
import { TELEGRAM_CREDENTIALS } from '../config/AppCredentials';
import { initSettingsStore, loadChatFontSize, KEY_CHAT_FONT_SIZE } from '../store/SettingsStore';
import { AppLockGate } from '../applock/AppLockGate';
import { appLockGate, installAppLock } from '../applock/AppLockWiring';
import {
  enableTdLibLogFileSink,
  TdLibLogSinkOutcome,
  TdLibLogSinkRequest,
  TdSyncExecuteFn
} from '../tdlog/TdLibLogSink';

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

      // TDLOG-BRIDGE-101：把 TDLib 的内部日志从 stderr（本端没人接，等于丢弃）
      // 改道到应用沙盒文件，整包取数 406 的服务器原文才有读数。
      //
      // 放在 bootstrap 之后、coordinator.start() 之前：这一步之后发出的请求
      // （setTdlibParameters 及其后全部）都能落盘；只漏掉 client 创建那一小段。
      // 不改 bootstrap 的签名——它是按位置收平台端口的装配函数，一个 debug 位
      // 不该挤进去变成第 9 个 `undefined`。
      this.installTdLibLogSink(result);

      result.coordinator.start();
      AppStorage.setOrCreate<BootstrapResult>('bootstrapResult', result);
      hilog.info(DOMAIN, TAG, 'bootstrap succeeded — coordinator started');
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'bootstrap failed: %{public}s', String(e));
    }
  }

  /**
   * 只有 debug 包才装日志落盘。
   *
   * 读的是 `appInfo.debug`（本机实测 `bm dump -n <bundle>` 里 `"debug": true`），
   * 不是编译期的 `BuildProfile.DEBUG`：后者由 hvigor 生成到各模块根的
   * `BuildProfile.ets`，而这条路径被 `.gitignore` 第 12 行排除、全仓零处引用，
   * 不该为了一个开关首次引入未验证的构建产物依赖。
   * Kit 调用失败按 false 收（宁可不写日志文件）。
   */
  private installTdLibLogSink(result: BootstrapResult): void {
    // 只把 execute 这一个动作交给日志模块：ArkTS 不做结构类型匹配，
    // 所以这里包闭包，而不是把整个 TdNativeBridgeLike 传下去。
    const execute: TdSyncExecuteFn = (requestUtf8: string): string | null => result.bridge.execute(requestUtf8);
    const request: TdLibLogSinkRequest = {
      filesDir: result.filesDir !== undefined ? result.filesDir : this.context.filesDir,
      debugBuild: this.isDebugBuild()
    };
    const outcome: TdLibLogSinkOutcome = enableTdLibLogFileSink(execute, request);
    // 只记状态、步骤与文件路径：TDLib 的应答原文不进 hilog（本仓既有隐私口径）。
    hilog.info(DOMAIN, TAG, 'tdlib log sink status=%{public}s step=%{public}s path=%{public}s verbosity=%{public}d',
      outcome.status, outcome.step, outcome.path, outcome.verbosity);
  }

  private isDebugBuild(): boolean {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      return info.appInfo.debug;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'debug flag unreadable, treating as release');
      return false;
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
