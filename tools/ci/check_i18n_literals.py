#!/usr/bin/env python3
"""tools/ci/check_i18n_literals.py — 视图层文案与词典一致性守卫（I18N-LITERAL-101 引入）。

背景：`Lang` 与 EN/ZH 两本词典从 SET-103 起就在，设置线（feature/settings）也都走 `this.t(...)`，
但聊天/资料/贴纸那几批页面是直接把中文写进 `Text('清空历史记录')` 的。写死中文的代价不是「不国际化」
这么抽象 —— 上一轮就撞过一次：`Index.ets` 用了 key `'Sticker set: %s'`，两本词典里都没有这一项，
`Lang` 缺译文时**原样回吐 key**，于是 Toast 上屏的是 `Sticker set: %s` 本身。也就是说
「key 拼错」和「漏翻译」在屏幕上长得一模一样，没人会当场发现。

本脚本守四条：

  R1 视图层字面量禁令：`entry` 与各 `feature/*` 的 **pages/ 与 components/** 下，任何 .ets 文件
     里都不允许出现含汉字的字符串字面量（emoji 不在 `一-鿿` 段内，不会被误伤）。
     理由是这一层是「文案的显示端」：文案的真相只在 `Lang.ets` 一处，页面里出现中文就说明
     这一句永远不会随语言变，而下一个改词典的人根本看不到它。
     就地豁免：行尾写 `// i18n-allow <原因>`。豁免必须带原因 —— 本仓目前只有三类合法豁免：
     日期/相对时间的**形态**（`10月3日` vs `Oct 3`，不是换词条而是换排布，归 I18N-DATE 一包），
     语言选择器里的**本族名**（'简体中文' 在英文界面也该是 '简体中文'），以及 R4 的**源语言标签**
     （English 界面里的 'English' 本来就该长这样）。
  R2 key 必须双词典命中：`getString('X')` / `.t('X')` / `t('X')` / `formatByKey('X', ...)` 的**字面量**
     key 必须同时存在于 EN 与 ZH。这就是上面那次事故的直接防线。动态 key（变量、三元）不在射程内，
     所以 R3 兜住整本表。
  R3 两本词典 key 集合全等：EN 有 ZH 没有 = 中文界面回吐英文原文；ZH 有 EN 没有 = 英文界面回吐中文。
     两个方向都是「界面上出现另一种语言」，所以全等比「ZH 覆盖 EN 的差集」更严，也更便宜。
  R4 文案槽位里不许放「词典里已经有的英文字面量」（I18N-LITERAL-102 引入）：R1 只禁汉字，于是
     `Text('Reply')` 这一路仍然畅通 —— 中文界面上它永远显示 `Reply`，而词典里明明有 `'Reply': '回复'`。
     为什么不把 R1 直接扩成「禁一切英文字面量」：英文单词同时是**技术 token**（`'zh'`、`'mtproto'`、
     `$r('app.media.ic_help')`、`kind === 'channel'`），无差别拦会产生几十条必须逐行写理由的误伤，
     守卫一旦需要大量豁免就没人当真。所以 R4 只认**文案槽位**：ArkUI 里直接吃显示串的调用
     （`Text(` / `Button(` / `MenuItem(` / `TextInput(` / `.searchButton(` …）、对象字面量里直接
     作为显示字段的名字（`placeholder:` / `title:` / `content:` / `label:` …）、以及 `this.` 上首字母
     大写的自定义 `@Builder`（这类调用在本仓只有一种用途：渲染一块 UI）。
     两种写法明确豁免且不需要就地标记：
       ① 位于 `t()` / `getString()` / `formatByKey()` 实参位 —— 那就是在查词典，正是要的形状；
       ② 被名字以 `Key` 结尾的调用或字段接收（`labelKey:` / `FieldLabelKey('Server Address')`）——
          本仓「传 key 不传串」的既有约定（`SelfProfilePage.ets` 的 `labelKey` 行就是这么写的），
          约定优先于标记：新 builder 想收 key 就把名字改成 `…Key`，否则它收到的就是显示串。
     射程外的一类如实记下：把 key 存在数据行里再传进 `Text(row.labelKey)` 的**构造点**
     （`new DrawerMenuRow('calls', icon, 'Calls', false)`）不是文案槽位，守卫看不见；
     那一类靠 R2（接进 `t()` 之后缺项会被拦）与 `*Key` 命名约束兜。

用法：python3 tools/ci/check_i18n_literals.py [--quiet]
退出码：0 = 无违规；1 = 存在违规；2 = 前置条件坏了（词典解析不出来）
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
LANG_FILE = ROOT / 'core' / 'common' / 'src' / 'main' / 'ets' / 'Lang.ets'

VIEW_DIRS = ['entry/src/main/ets'] + [
    str(p.relative_to(ROOT)) for p in ROOT.glob('feature/*/src/main/ets')
]
VIEW_SEGMENTS = ('/pages/', '/components/')
SKIP_PARTS = ('/oh_modules/', '/build/', '/.test/', '/.preview/')

# 汉字段（CJK Unified Ideographs）。emoji（😀 ★ ✋）与假名/谚文都不在此段，故意只拦汉字：
# 本仓的界面文案只有中英两档，拦假名只会误伤测试里的样例数据。
CJK_RE = re.compile(r'[一-鿿]')
LITERAL_RE = re.compile(r"(['\"`])((?:\\.|(?!\1).)*)\1")
ALLOW_RE = re.compile(r'//\s*i18n-allow(?P<reason>[^\n]*)')

# R2：字面量 key 的四种写法。`t('X')` / `.t('X')` / `getString('X')` / `formatByKey('X',`
KEY_CALL_RE = re.compile(
    r"""(?:\.\s*(?:t|getString|formatByKey)\s*\(\s*|(?<![\w.])t\s*\(\s*)"""
    r"""'((?:[^'\\]|\\.)+)'"""
)

# R4：查词典的调用与「传 key」的命名约定。
KEY_CALL_NAMES = frozenset(('t', 'getString', 'formatByKey'))
KEY_CARRIER_SUFFIX = 'Key'
# R4：直接吃显示串的 ArkUI 调用/属性。
DISPLAY_CALL_NAMES = frozenset((
    'Text', 'Button', 'Label', 'Toggle', 'MenuItem', 'TextInput', 'TextEditor',
    'searchButton', 'showToast', 'promptAction', 'setTitle', 'setSubtitle',
))
DISPLAY_FIELDS = frozenset((
    'placeholder', 'title', 'content', 'label', 'text', 'message', 'description',
    'promptText', 'cancelText', 'confirmText', 'buttonText',
))
QUOTES = ('\'', '"', '`')


def is_comment(stripped: str) -> bool:
    return stripped.startswith('//') or stripped.startswith('/*') or stripped.startswith('*')


def code_lines(path):
    """逐行产出参与扫描的代码行（跳过整行注释与块注释；三条规则用同一套口径）。"""
    in_block = False
    for idx, line in enumerate(path.read_text(encoding='utf-8').splitlines()):
        stripped = line.strip()
        if stripped.startswith('/*'):
            in_block = True
        if in_block:
            if stripped.endswith('*/'):
                in_block = False
            continue
        if is_comment(stripped):
            continue
        yield idx, line, stripped


def view_files():
    out = []
    for d in VIEW_DIRS:
        base = ROOT / d
        if not base.is_dir():
            continue
        for path in sorted(base.rglob('*.ets')):
            rel = str(path.relative_to(ROOT))
            if any(part in SKIP_PARTS for part in rel):
                continue
            if not any(seg in rel for seg in VIEW_SEGMENTS):
                continue
            out.append((rel, path))
    return out


def scan_literals(files):
    """R1：视图层文件里的汉字字面量（`// i18n-allow 原因` 可豁免）。"""
    problems = []
    allowed = []
    for rel, path in files:
        for idx, line, stripped in code_lines(path):
            hit = None
            for m in LITERAL_RE.finditer(line):
                if CJK_RE.search(m.group(2)):
                    hit = m.group(2)[:40]
                    break
            if hit is None:
                continue
            allow = ALLOW_RE.search(line)
            if allow is not None:
                if not allow.group('reason').strip():
                    problems.append(f'{rel}:{idx + 1}: i18n-allow 必须写原因'
                                    f'（本仓合法豁免只有日期形态、本族名与源语言标签三类）')
                else:
                    allowed.append(f'{rel}:{idx + 1}')
                continue
            problems.append(f'{rel}:{idx + 1}: 视图层写死中文文案 -> {hit}（改走 Lang key，'
                            f'确需保留请标 // i18n-allow <原因>）')
    return problems, allowed


def scan_line_literals(line):
    """把一行拆成「字面量 + 它被谁接走」，供 R4 判定槽位。

    只做粗粒度语法位置判定，不是解析器：
      callers —— 该行内所有仍未闭合的调用的被调名（`(` 前的标识符段），元数据里同时记住
                 它是不是成员调用（`this.` / `obj.` 后面那种），用来认 `@Builder`；
      field   —— 紧邻该字面量之前的 `名字:`，即对象字面量里的键名。
    字符串内部的括号与引号一律不解析（逐字符跳到配对的引号结束），所以 `Text('a(b')` 不误。
    """
    out = []
    stack = []
    field = None
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if ch in QUOTES:
            j = i + 1
            buf = []
            while j < n:
                c = line[j]
                if c == '\\':
                    if j + 1 < n:
                        buf.append(line[j + 1])
                    j += 2
                    continue
                if c == ch:
                    break
                buf.append(c)
                j += 1
            out.append((''.join(buf), tuple(stack), field))
            i = j + 1
            field = None
            continue
        if ch in '([{':
            k = i - 1
            while k >= 0 and (line[k].isalnum() or line[k] in '_$'):
                k -= 1
            stack.append((line[k + 1:i] if ch == '(' else None,
                          k >= 0 and line[k] == '.'))
            field = None
            i += 1
            continue
        if ch in ')]}':
            if stack:
                stack.pop()
            i += 1
            continue
        if ch == ':':
            k = i - 1
            while k >= 0 and (line[k].isalnum() or line[k] in '_$'):
                k -= 1
            field = line[k + 1:i] or None
            i += 1
            continue
        if ch == ',':
            field = None
        i += 1
    return out


def display_slot_reason(callers, field):
    """字面量所处文案槽位的写法；不属于文案槽位则回 None（R4 不管它）。"""
    names = [name for name, _ in callers if name]
    # 豁免 ①：t()/getString()/formatByKey() 的实参 —— 这就是在查词典，正是要的形状。
    if any(name in KEY_CALL_NAMES for name in names):
        return None
    # 豁免 ②：`*Key` 约定的调用/字段 —— 它收的是 key，不是串。
    if any(name.endswith(KEY_CARRIER_SUFFIX) for name in names):
        return None
    for name, member in callers:
        if not name:
            continue
        if name in DISPLAY_CALL_NAMES:
            return f'{name}('
        if member and name[0].isupper():
            # 首字母大写且挂在 `this.` 上的成员调用在本仓只有 @Builder 一种用途：渲染 UI。
            return f'@Builder {name}('
    if field is not None and field in DISPLAY_FIELDS:
        return f'{field}:'
    return None


def scan_display_slots(files, dicts):
    """R4：词典里已存在的英文字面量不许直接写进文案槽位（`// i18n-allow 原因` 可豁免）。"""
    problems = []
    allowed = []
    known = dicts['EN'] | dicts['ZH']
    for rel, path in files:
        for idx, line, stripped in code_lines(path):
            for value, callers, field in scan_line_literals(line):
                if not value or CJK_RE.search(value) or value not in known:
                    continue
                reason = display_slot_reason(callers, field)
                if reason is None:
                    continue
                allow = ALLOW_RE.search(line)
                if allow is not None:
                    if not allow.group('reason').strip():
                        problems.append(f'{rel}:{idx + 1}: i18n-allow 必须写原因'
                                        f'（本仓合法豁免只有日期形态、本族名与源语言标签三类）')
                    else:
                        allowed.append(f'{rel}:{idx + 1}')
                    continue
                problems.append(f'{rel}:{idx + 1}: 文案槽位 {reason} 里写死了词典已知的英文 '
                                f'-> {value}（改走 this.t(...) 或把参数改名成 *Key，'
                                f'确需保留请标 // i18n-allow <原因>）')
    return problems, allowed


def load_dicts():
    if not LANG_FILE.is_file():
        print(f'[i18n] ERROR: 找不到词典 {LANG_FILE}', file=sys.stderr)
        sys.exit(2)
    text = LANG_FILE.read_text(encoding='utf-8')
    out = {}
    for name in ('EN', 'ZH'):
        m = re.search(r'const ' + name + r'_DICTIONARY: Record<string, string> = \{(.*?)\n\};',
                      text, re.S)
        if m is None:
            print(f'[i18n] ERROR: Lang.ets 未解析出 {name}_DICTIONARY', file=sys.stderr)
            sys.exit(2)
        out[name] = set(re.findall(r"^\s*'((?:[^'\\]|\\.)+)'\s*:", m.group(1), re.M))
    return out


def scan_keys(files, dicts):
    """R2：字面量 key 必须两本词典都有。"""
    problems = []
    checked = set()
    for rel, path in files:
        for idx, line, stripped in code_lines(path):
            for m in KEY_CALL_RE.finditer(line):
                key = m.group(1)
                checked.add(key)
                if key not in dicts['EN'] or key not in dicts['ZH']:
                    missing = [n for n in ('EN', 'ZH') if key not in dicts[n]]
                    problems.append(f'{rel}:{idx + 1}: key {key!r} 缺 {" 与 ".join(missing)} 词条'
                                    f'（Lang 缺译文会原样回吐 key，屏幕上就是一串英文标识）')
    return problems, checked


def scan_parity(dicts):
    """R3：两本词典 key 集合全等。"""
    problems = []
    for a, b in (('EN', 'ZH'), ('ZH', 'EN')):
        for key in sorted(dicts[a] - dicts[b]):
            problems.append(f'key {key!r} 只在 {a} 词典里（{b} 界面会直接回吐这一串）')
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--quiet', action='store_true')
    args = parser.parse_args()

    files = view_files()
    dicts = load_dicts()

    literal_problems, allowed_literal = scan_literals(files)
    slot_problems, allowed_slot = scan_display_slots(files, dicts)
    key_problems, checked = scan_keys(files, dicts)
    parity_problems = scan_parity(dicts)

    allowed = allowed_literal + allowed_slot
    failed = bool(literal_problems or slot_problems or key_problems or parity_problems)
    if not args.quiet or failed:
        for msg in literal_problems:
            print(f'[i18n] LITERAL {msg}')
        for msg in slot_problems:
            print(f'[i18n] ENGLISH-SLOT {msg}')
        for msg in key_problems:
            print(f'[i18n] MISSING-KEY {msg}')
        for msg in parity_problems:
            print(f'[i18n] PARITY {msg}')
        if not args.quiet:
            print(f'[i18n] 视图层文件 {len(files)} 个，字面量 key 调用点覆盖 {len(checked)} 个，'
                  f'词典 EN {len(dicts["EN"])} / ZH {len(dicts["ZH"])} 条，'
                  f'就地豁免 {len(allowed)} 处（写死中文 {len(allowed_literal)} / 写死英文 {len(allowed_slot)}）')
    if failed:
        print(f'[i18n] FAILED: 写死中文 {len(literal_problems)} / 写死英文 {len(slot_problems)} / '
              f'缺词条 {len(key_problems)} / 词典不对称 {len(parity_problems)}', file=sys.stderr)
        return 1
    print('[i18n] OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
