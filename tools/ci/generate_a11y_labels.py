#!/usr/bin/env python3
"""一次性生成 A11y.ets 槽位表与 Lang 词典里的 A11y* 条目（A11Y-101）。

标签的**唯一清单**就是下面的 LABELS 字典：`槽位名 -> (Lang key, 英文, 中文)`。
跑一次会把 `core/common/src/main/ets/A11y.ets` 的两个区块之间、以及 `Lang.ets`
两套词典里的 `A11Y-101 BEGIN/END` 标记之间整体重写，保证「表里有 = 词典里有」。
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

# (slot, key, en, zh) —— 顺序即 A11y.ets 里的分组顺序。
LABELS = [
    ('BACK', 'A11yBack', 'Back', '返回'),
    ('CLOSE', 'A11yClose', 'Close', '关闭'),
    ('MORE', 'A11yMore', 'More options', '更多选项'),
    ('SEARCH', 'A11ySearch', 'Search', '搜索'),
    ('CALL', 'A11yCall', 'Voice call', '语音通话'),
    ('MENU', 'A11yMenu', 'Menu', '菜单'),
    ('SETTINGS', 'A11ySettings', 'Settings', '设置'),
    ('SWITCH_ACCOUNT', 'A11ySwitchAccount', 'Switch account', '切换账号'),
    ('OPEN_PROFILE', 'A11yOpenProfile', 'Open {0} profile', '打开 {0} 的资料页'),

    ('ATTACH', 'A11yAttach', 'Attach', '附件'),
    ('EMOJI', 'A11yEmoji', 'Emoji', '表情'),
    ('KEYBOARD', 'A11yKeyboard', 'Switch to keyboard', '切换到键盘'),
    ('SEND', 'A11ySend', 'Send message', '发送消息'),
    ('RECORD_VOICE', 'A11yRecordVoice', 'Hold to record voice message', '按住录制语音消息'),
    ('CANCEL_RECORDING', 'A11yCancelRecording', 'Cancel recording', '取消录音'),
    ('SEND_RECORDING', 'A11ySendRecording', 'Send voice message', '发送语音消息'),
    ('DELETE_CHAR', 'A11yDeleteChar', 'Delete character', '删除一个字符'),
    ('SHOW_PASSWORD', 'A11yShowPassword', 'Show password', '显示密码'),
    ('HIDE_PASSWORD', 'A11yHidePassword', 'Hide password', '隐藏密码'),

    ('FORWARD', 'A11yForward', 'Forward', '转发'),
    ('PLAY', 'A11yPlay', 'Play', '播放'),
    ('PAUSE', 'A11yPause', 'Pause', '暂停'),
    ('DOWNLOAD', 'A11yDownload', 'Download', '下载'),
    ('CANCEL_DOWNLOAD', 'A11yCancelDownload', 'Cancel download', '取消下载'),
    ('CANCEL_UPLOAD', 'A11yCancelUpload', 'Cancel upload', '取消上传'),
    ('RETRY_SEND', 'A11yRetrySend', 'Retry sending', '重试发送'),
    ('OPEN_MEDIA', 'A11yOpenMedia', 'Open photo', '打开图片'),
    ('OPEN_FILE', 'A11yOpenFile', 'Open file', '打开文件'),
    ('CLOSE_PINNED', 'A11yClosePinned', 'Hide pinned message', '隐藏置顶消息'),
    ('SELECT_MESSAGE', 'A11ySelectMessage', 'Select message', '选中这条消息'),
    ('DESELECT_MESSAGE', 'A11yDeselectMessage', 'Deselect message', '取消选中这条消息'),
    ('MUTE_SOUND', 'A11yMuteSound', 'Mute sound', '关闭声音'),
    ('UNMUTE_SOUND', 'A11yUnmuteSound', 'Unmute sound', '打开声音'),

    ('BOARD_TAB_EMOJI', 'A11yBoardTabEmoji', 'Emoji', '表情'),
    ('BOARD_TAB_STICKERS', 'A11yBoardTabStickers', 'Stickers', '贴纸'),
    ('BOARD_TAB_GIF', 'A11yBoardTabGif', 'GIFs', '动图'),
    ('BOARD_CELL', 'A11yBoardCell', 'Sticker {0}', '贴纸 {0}'),
    ('BOARD_PACK', 'A11yBoardPack', 'Sticker pack {0}', '贴纸包 {0}'),

    ('EDIT', 'A11yEdit', 'Edit', '编辑'),
    ('DELETE', 'A11yDelete', 'Delete', '删除'),
    ('ADD_CONTACT', 'A11yAddContact', 'Add contact', '添加联系人'),

    ('CANCEL', 'Cancel', 'Cancel', '取消'),
]

GROUPS = [
    ('导航与头部', ['BACK', 'CLOSE', 'MORE', 'SEARCH', 'CALL', 'MENU', 'SETTINGS', 'SWITCH_ACCOUNT', 'OPEN_PROFILE']),
    ('输入栏与登录', ['ATTACH', 'EMOJI', 'KEYBOARD', 'SEND', 'RECORD_VOICE', 'CANCEL_RECORDING',
                 'SEND_RECORDING', 'DELETE_CHAR', 'SHOW_PASSWORD', 'HIDE_PASSWORD']),
    ('消息与媒体', ['FORWARD', 'PLAY', 'PAUSE', 'DOWNLOAD', 'CANCEL_DOWNLOAD', 'CANCEL_UPLOAD',
                'RETRY_SEND', 'OPEN_MEDIA', 'OPEN_FILE', 'CLOSE_PINNED', 'SELECT_MESSAGE', 'DESELECT_MESSAGE',
                'MUTE_SOUND', 'UNMUTE_SOUND']),
    ('表情板', ['BOARD_TAB_EMOJI', 'BOARD_TAB_STICKERS', 'BOARD_TAB_GIF', 'BOARD_CELL', 'BOARD_PACK']),
    ('行内操作', ['EDIT', 'DELETE', 'ADD_CONTACT']),
    ('复用词典已有通用文案', ['CANCEL']),
]

HEADER = '''/**
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

export class A11y {'''

FOOTER = '''}

/**
 * 全部槽位 key（与上面的表同批生成）。单测据此断言「表里有 = 两套词典里都有」：
 * 只改了生成脚本、忘了往 Lang 注入条目时，这里就会多出一个查不到译文的 key。
 */
export const A11Y_SLOTS: string[] = [
{SLOT_ARRAY}
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
'''


def render_ets() -> str:
    by_slot = {slot: (key, en, zh) for slot, key, en, zh in LABELS}
    out = [HEADER]
    for group, slots in GROUPS:
        out.append(f'  // {group}')
        for slot in slots:
            key = by_slot[slot][0]
            out.append(f"  static readonly {slot}: string = '{key}';")
        out.append('')
    text = '\n'.join(out).rstrip('\n') + '\n' + FOOTER
    text = text.replace('\n\n\n', '\n\n')
    slot_array = '\n'.join(f"  A11y.{slot}," for slot, _, _, _ in LABELS)
    return text.replace('{SLOT_ARRAY}', slot_array)


# 词典里已经存在的通用 key：槽位直接指向它，不重复注入（否则字典字面量里出现同名键）。
REUSED_KEYS = {'Cancel'}

COMMENT = ('// Accessibility labels for icon-only controls (A11Y-101). '
           'Spoken by the screen reader, never shown, so they read as a phrase.',
           '// 图标控件的无障碍标签（A11Y-101）：只被屏幕朗读播报，不显示在界面上。')


def render_dict(lang_index: int) -> str:
    lines = ['  ' + COMMENT[lang_index]]
    for slot, key, en, zh in LABELS:
        if key in REUSED_KEYS:
            continue
        value = en if lang_index == 0 else zh
        lines.append(f"  '{key}': '{value}',")
    return '\n'.join(lines)


def replace_block(path: pathlib.Path, begin: str, end: str, new_body: str) -> None:
    text = path.read_text(encoding='utf-8')
    pattern = re.compile(re.escape(begin) + r'.*?' + re.escape(end), re.S)
    if pattern.search(text) is None:
        print(f'[gen] ERROR: {path} 里找不到 {begin}', file=sys.stderr)
        sys.exit(2)
    text = pattern.sub(begin + '\n' + new_body + '\n' + end, text, count=1)
    path.write_text(text, encoding='utf-8')


def main() -> int:
    check_duplicates()
    a11y_path = ROOT / 'core' / 'common' / 'src' / 'main' / 'ets' / 'A11y.ets'
    a11y_path.write_text(render_ets(), encoding='utf-8')

    lang_path = ROOT / 'core' / 'common' / 'src' / 'main' / 'ets' / 'Lang.ets'
    text = lang_path.read_text(encoding='utf-8')
    for marker, idx in (('EN', 0), ('ZH', 1)):
        begin = f'  // A11Y-101 BEGIN {marker}'
        end = f'  // A11Y-101 END {marker}'
        if begin not in text or end not in text:
            print(f'[gen] ERROR: Lang.ets 缺 {begin}', file=sys.stderr)
            return 2
    text = inject(text, '  // A11Y-101 BEGIN EN', '  // A11Y-101 END EN', render_dict(0))
    text = inject(text, '  // A11Y-101 BEGIN ZH', '  // A11Y-101 END ZH', render_dict(1))
    lang_path.write_text(text, encoding='utf-8')
    print(f'[gen] 写入 {len(LABELS)} 个槽位')
    return 0


def inject(text: str, begin: str, end: str, body: str) -> str:
    head, rest = text.split(begin, 1)
    _, tail = rest.split(end, 1)
    return head + begin + '\n' + body.rstrip() + '\n' + end + tail


def check_duplicates() -> None:
    keys = [k for _, k, _, _ in LABELS]
    if len(set(keys)) != len(keys):
        print('[gen] ERROR: Lang key 重复', file=sys.stderr)
        sys.exit(2)
    slots = [s for s, _, _, _ in LABELS]
    if len(set(slots)) != len(slots):
        print('[gen] ERROR: 槽位名重复', file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    sys.exit(main())
