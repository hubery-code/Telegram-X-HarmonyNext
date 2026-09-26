/**
 * core/common — 无障碍标签槽位表（A11Y-101）。
 *
 * ## 为什么要有这张表
 *
 * 图标按钮（`Row { Image($r('app.media.ic_back')) }.onClick(...)`）在 ArkUI 的无障碍树里
 * 是一个**没有文本的节点**，屏幕朗读只能播报「按钮」，用户在按下之前不知道它是返回还是删除。
 * 补标签如果只是在各页面里随手写 `.accessibilityText('返回')`，三个月后就会同时存在
 * '返回' / 'Back' / '上一页' 三种说法，并且没人知道哪些控件漏了。
 *
 * 所以本表是标签的**唯一真相**：一个交互语义一个槽位，槽位的值是 `Lang` 的 key，
 * 页面里只写 `.accessibilityText(a11y(A11y.BACK))`。
 * `tools/ci/check_accessibility_labels.py` 据此守住三件事：图标-only 的可点击组件必须有标签、
 * 标签只能走 `a11y(...)`（实参里不允许字面量字符串）、每个槽位的 key 在 EN 与 ZH 两套词典里都有。
 *
 * ## 为什么不直接放字符串
 *
 * `Lang` 缺译文时会**原样回吐 key**，所以「key 存在」不等于「有中文」。槽位值必须是词典里
 * 真实存在的 key，守卫脚本才会把漏翻译变成构建失败，而不是屏幕上冒出一句 `A11yBack`。
 *
 * ## 怎么加新标签
 *
 * 本表与 `Lang.ets` 里 `A11Y-101 BEGIN/END` 之间的条目由
 * `tools/ci/generate_a11y_labels.py` 从同一份清单生成；改标签就改那个脚本的 LABELS 再重跑，
 * 这样「表里有 = 词典里有」是构造出来的，不是靠人记住。
 */

import { Lang } from './Lang';

export class A11y {
  // 导航与头部
  static readonly BACK: string = 'A11yBack';
  static readonly CLOSE: string = 'A11yClose';
  static readonly MORE: string = 'A11yMore';
  static readonly SEARCH: string = 'A11ySearch';
  static readonly CALL: string = 'A11yCall';
  static readonly MENU: string = 'A11yMenu';
  static readonly SETTINGS: string = 'A11ySettings';
  static readonly SWITCH_ACCOUNT: string = 'A11ySwitchAccount';
  static readonly OPEN_PROFILE: string = 'A11yOpenProfile';

  // 输入栏与登录
  static readonly ATTACH: string = 'A11yAttach';
  static readonly EMOJI: string = 'A11yEmoji';
  static readonly KEYBOARD: string = 'A11yKeyboard';
  static readonly SEND: string = 'A11ySend';
  static readonly RECORD_VOICE: string = 'A11yRecordVoice';
  static readonly CANCEL_RECORDING: string = 'A11yCancelRecording';
  static readonly SEND_RECORDING: string = 'A11ySendRecording';
  static readonly DELETE_CHAR: string = 'A11yDeleteChar';
  static readonly SHOW_PASSWORD: string = 'A11yShowPassword';
  static readonly HIDE_PASSWORD: string = 'A11yHidePassword';

  // 消息与媒体
  static readonly FORWARD: string = 'A11yForward';
  static readonly PLAY: string = 'A11yPlay';
  static readonly PAUSE: string = 'A11yPause';
  static readonly DOWNLOAD: string = 'A11yDownload';
  static readonly CANCEL_DOWNLOAD: string = 'A11yCancelDownload';
  static readonly CANCEL_UPLOAD: string = 'A11yCancelUpload';
  static readonly RETRY_SEND: string = 'A11yRetrySend';
  static readonly OPEN_MEDIA: string = 'A11yOpenMedia';
  static readonly OPEN_FILE: string = 'A11yOpenFile';
  static readonly CLOSE_PINNED: string = 'A11yClosePinned';
  static readonly SELECT_MESSAGE: string = 'A11ySelectMessage';
  static readonly DESELECT_MESSAGE: string = 'A11yDeselectMessage';
  static readonly MUTE_SOUND: string = 'A11yMuteSound';
  static readonly UNMUTE_SOUND: string = 'A11yUnmuteSound';

  // 表情板
  static readonly BOARD_TAB_EMOJI: string = 'A11yBoardTabEmoji';
  static readonly BOARD_TAB_STICKERS: string = 'A11yBoardTabStickers';
  static readonly BOARD_TAB_GIF: string = 'A11yBoardTabGif';
  static readonly BOARD_CELL: string = 'A11yBoardCell';
  static readonly BOARD_PACK: string = 'A11yBoardPack';

  // 行内操作
  static readonly EDIT: string = 'A11yEdit';
  static readonly DELETE: string = 'A11yDelete';
  static readonly ADD_CONTACT: string = 'A11yAddContact';

  // 复用词典已有通用文案
  static readonly CANCEL: string = 'Cancel';
}

/**
 * 全部槽位 key（与上面的表同批生成）。单测据此断言「表里有 = 两套词典里都有」：
 * 只改了生成脚本、忘了往 Lang 注入条目时，这里就会多出一个查不到译文的 key。
 */
export const A11Y_SLOTS: string[] = [
  A11y.BACK,
  A11y.CLOSE,
  A11y.MORE,
  A11y.SEARCH,
  A11y.CALL,
  A11y.MENU,
  A11y.SETTINGS,
  A11y.SWITCH_ACCOUNT,
  A11y.OPEN_PROFILE,
  A11y.ATTACH,
  A11y.EMOJI,
  A11y.KEYBOARD,
  A11y.SEND,
  A11y.RECORD_VOICE,
  A11y.CANCEL_RECORDING,
  A11y.SEND_RECORDING,
  A11y.DELETE_CHAR,
  A11y.SHOW_PASSWORD,
  A11y.HIDE_PASSWORD,
  A11y.FORWARD,
  A11y.PLAY,
  A11y.PAUSE,
  A11y.DOWNLOAD,
  A11y.CANCEL_DOWNLOAD,
  A11y.CANCEL_UPLOAD,
  A11y.RETRY_SEND,
  A11y.OPEN_MEDIA,
  A11y.OPEN_FILE,
  A11y.CLOSE_PINNED,
  A11y.SELECT_MESSAGE,
  A11y.DESELECT_MESSAGE,
  A11y.MUTE_SOUND,
  A11y.UNMUTE_SOUND,
  A11y.BOARD_TAB_EMOJI,
  A11y.BOARD_TAB_STICKERS,
  A11y.BOARD_TAB_GIF,
  A11y.BOARD_CELL,
  A11y.BOARD_PACK,
  A11y.EDIT,
  A11y.DELETE,
  A11y.ADD_CONTACT,
  A11y.CANCEL,
];

/**
 * 取某个槽位在当前语言下的播报文本。
 *
 * 只走 `Lang.getInstance()`，不接页面的 `effectiveLang`：无障碍文本在 `build()` 求值，
 * 订阅了语言变化的页面重绘时这里读到的就是新语言。
 */
export function a11y(key: string, ...args: (string | number)[]): string {
  return Lang.getInstance().getString(key, ...args);
}
