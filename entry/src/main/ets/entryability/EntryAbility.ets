import { AbilityConstant, bundleManager, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { i18n } from '@kit.LocalizationKit';
import { LanguagePreference, Lang, languagePreferenceFromStored, systemLanguageFromLocale } from '@tgx/core-common';
import { bootstrap, BootstrapResult } from '../Bootstrap';
import { appDeepLinkQueue } from '../deeplink/DeepLinkQueue';
import { TdlibParametersConfig } from '@tgx/feature-auth';
import { TELEGRAM_CREDENTIALS } from '../config/AppCredentials';
import {
  initSettingsStore,
  loadChatFontSize,
  readSettingsString,
  KEY_APP_LANGUAGE,
  KEY_CHAT_FONT_SIZE
} from '../store/SettingsStore';
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

    // LANG-PERSIST-101：把语言接回系统 locale 与磁盘。此前有两条静默失效：
    //   ① 设置页选的偏好只写进 AppStorage（进程级内存），冷启动即回到「跟随系统」；
    //   ② 全仓没有任何地方把系统语言灌进 Lang，`systemLanguage` 恒为构造默认的 'en'，
    //      于是「跟随系统」在 zh-Hans 的机器上一直说英文——显式选 en/zh 反而能生效，
    //      因为它不走这一位。
    // 顺序：先灌系统语言档（它只影响 'system' 偏好下的有效语言），再灌盘上的显式偏好。
    // 两步都排在 loadContent 之前，首帧即为正确语言，不需要二次重渲。
    this.hydrateLanguage();

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

  /**
   * LANG-PERSIST-101：启动时的语言回灌，两条写入方向都在这里。
   *
   * 「读盘 + 回落」与「写盘」刻意分开：这一位只有 entry 知道磁盘，业务层
   * （`feature_settings` 的 reducer）继续只管写 AppStorage，由 pages/Index 的
   * `@Watch` 落盘。所以偏好改动不需要任何新通道：reducer 写键 → entry 观察 → 落盘。
   */
  private hydrateLanguage(): void {
    const locale: string | null = this.systemLocale();
    const effectivePreference: LanguagePreference =
      languagePreferenceFromStored(readSettingsString(KEY_APP_LANGUAGE));
    Lang.getInstance().setSystemLanguage(systemLanguageFromLocale(locale));
    Lang.getInstance().setLanguage(effectivePreference);
    // reducer 只在用户选择时写这个键；冷启动先种一次，`@StorageProp('appLanguage')`
    // 首帧与「用户从没动过语言」这条路径才都有值可读。
    AppStorage.setOrCreate<string>(KEY_APP_LANGUAGE, effectivePreference);
    // 只记语言档，不记任何账号信息。
    hilog.info(DOMAIN, TAG, 'language restored: locale=%{public}s preference=%{public}s effective=%{public}s',
      locale === null ? 'unreadable' : locale, effectivePreference, Lang.getInstance().getLanguage());
  }

  /**
   * 系统语言 locale（`'zh-Hans'` / `'en-US'` 这类 BCP-47 串）。
   *
   * 包 try 而不是直取：读不到时回落 null → `systemLanguageFromLocale` 收为 'en'，
   * 与既有默认档一致。设置读不出来不该把启动带崩。
   */
  private systemLocale(): string | null {
    try {
      return i18n.System.getSystemLanguage();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'system language unreadable: %{public}s', String(e));
      return null;
    }
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
