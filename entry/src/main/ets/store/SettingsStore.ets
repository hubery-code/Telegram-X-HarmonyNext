import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CHAT_FONT_SIZE_DEFAULT, clampChatFontSize } from '@tgx/core-design-system';

/**
 * 本地设置存储（entry 装配层专用）。
 *
 * ## 为什么不用 `PersistentStorage.persistProp`
 *
 * 原本用 ArkUI 的 `PersistentStorage.persistProp<string>('chatFontSize', '15')`，
 * 模拟器实测（API 26 / Phone 模拟器）**恢复不生效**：
 *
 *   1. 设置页把字号调到 26 → 落盘文件内容确实变成了 26：
 *      `…/haps/entry/files/persistent_storage`
 *      `<?xml version="1.0" encoding="UTF-8"?>`
 *      `<preferences version="1.0"><string key="chatFontSize">26</string></preferences>`
 *   2. 杀进程重启后 `AppStorage.get('chatFontSize')` 拿到的是默认值 `'15'`；
 *   3. 同一个进程里用 `fileIo` 直接读那个文件，内容还是 26 —— 文件在、值在、
 *      权限也够，就是 `persistProp` 没把它恢复进 AppStorage；
 *   4. `setTimeout(1500ms)` 后再读仍是 `'15'`，排除「异步恢复还没落」；
 *   5. 不管声明成 `<number>` 还是 `<string>`，结果都一样。
 *
 * 即 `PersistentStorage` 的读写两端在这套 SDK 上对不上（落盘统一序列化成
 * `<string>`，读回时又匹配不上），且失败是**静默**的——不报错、不写日志，
 * 只表现为「设置完重启就变回默认」，排查成本极高。
 *
 * 因此这里退回到底层、行为确定的 `preferences` Kit API：读写同一路径、同一个
 * key、值类型固定为 number，并在读取端做一次 `clampChatFontSize` 收敛。
 *
 * ## 分层说明
 *
 * 这是一层「端口实现」。业务侧（`feature_settings` 的 reducer）只写 `AppStorage`，
 * 不碰 Kit；由 entry 作为装配层在 `@Watch` 回调里落盘，并在启动时读盘回灌
 * `ThemeManager` 与 `AppStorage`。这样业务层依旧零 Kit 依赖。
 */

const DOMAIN: number = 0x0000;
const TAG: string = 'SettingsStore';

/** 存储文件名，落在 `<el2>/base/<bundle>/haps/<module>/preferences/` 下。 */
const STORE_NAME: string = 'tgx_settings';

/** 已经落盘的设置项 key。 */
export const KEY_CHAT_FONT_SIZE: string = 'chatFontSize';

let store: preferences.Preferences | undefined = undefined;

/**
 * 打开存储。必须在 `onWindowStageCreate` 里、`loadContent` 之前调用一次，
 * 这样首帧就能拿到已恢复的字号，不会先按默认档渲染再跳一次。
 */
export function initSettingsStore(context: common.Context): void {
  try {
    store = preferences.getPreferencesSync(context, { name: STORE_NAME });
    hilog.info(DOMAIN, TAG, 'settings store opened: %{public}s', STORE_NAME);
  } catch (e) {
    store = undefined;
    hilog.error(DOMAIN, TAG, 'settings store open failed: %{public}s', JSON.stringify(e));
  }
}

/**
 * 读聊天字号。缺值 / 脏值一律收敛到合法档位，绝不抛错——设置读不出来不应该
 * 影响启动。
 */
export function loadChatFontSize(): number {
  if (store === undefined) {
    return CHAT_FONT_SIZE_DEFAULT;
  }
  try {
    const raw: preferences.ValueType = store.getSync(KEY_CHAT_FONT_SIZE, CHAT_FONT_SIZE_DEFAULT);
    if (typeof raw === 'number') {
      return clampChatFontSize(raw);
    }
    if (typeof raw === 'string') {
      return clampChatFontSize(raw);
    }
    return CHAT_FONT_SIZE_DEFAULT;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'chatFontSize read failed: %{public}s', JSON.stringify(e));
    return CHAT_FONT_SIZE_DEFAULT;
  }
}

/** 写聊天字号。写入前先吸附档位；flush 立即落盘，避免进程被杀丢设置。 */
export function saveChatFontSize(fontSize: number | string): void {
  if (store === undefined) {
    return;
  }
  const applied: number = clampChatFontSize(fontSize);
  try {
    store.putSync(KEY_CHAT_FONT_SIZE, applied);
    store.flush();
    hilog.info(DOMAIN, TAG, 'chatFontSize persisted: %{public}s', `${applied}`);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'chatFontSize write failed: %{public}s', JSON.stringify(e));
  }
}
