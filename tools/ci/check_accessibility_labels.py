#!/usr/bin/env python3
"""tools/ci/check_accessibility_labels.py — 无障碍标签静态守卫（A11Y-101 引入）。

背景：本仓的图标按钮全部是 `Row() { Image($r('app.media.ic_xxx')) }.onClick(...)` 的形状，
**组件自身没有文本**。ArkUI 的屏幕朗读（Stage 引擎的 AccessibilityService）对这种节点只会
播报「按钮」，用户点下去之前不知道它是返回还是删除。Android 侧 `TGActivity` 给每个图标都
写了 `setContentDescription`，本端此前一处都没有。

本脚本把「图标控件必须有可读标签」前移到 CI，规则三条：

  R1 覆盖：任意**可点击**（链上有 `.onClick(`）的组件块，若块内只有图标没有文本，
     且链上没有 `.accessibilityText(`，判违规。
  R2 路由：`.accessibilityText(` 的实参必须写成 `a11y(A11y.<槽位>)`，不允许裸字符串
     也不允许直接 `Lang.getInstance()` —— 标签口径只能有 `A11y.ets` 一处真相。
  R3 翻译：`A11y.<槽位> = '<key>'` 的每个 key 必须同时存在于 `Lang.ets` 的 EN 与 ZH
     词典里（`Lang` 缺译文时原样回吐 key，所以「查得到」本身就是断言）。

用法：python3 tools/ci/check_accessibility_labels.py [--quiet] [--basis]
退出码：0 = 无违规；1 = 存在违规；2 = 脚本自身的前置条件坏了（找不到定义文件等）

`--basis` 只打印 R2/R3 与解析自检，跳过 R1（R1 的存量清单在 A11Y-101 落地前不为零）。
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
A11Y_FILE = ROOT / 'core' / 'common' / 'src' / 'main' / 'ets' / 'A11y.ets'
LANG_FILE = ROOT / 'core' / 'common' / 'src' / 'main' / 'ets' / 'Lang.ets'

SCAN_DIRS = ['entry/src/main/ets'] + [
    str(p.relative_to(ROOT)) for p in ROOT.glob('feature/*/src/main/ets')
]

SKIP_PARTS = ('/oh_modules/', '/build/', '/.test/', '/.preview/')

# 组件调用：行首缩进后紧跟大写开头的标识符和左括号。
OPENER_RE = re.compile(r'^([A-Z][A-Za-z0-9_]*)\s*\(')
ICON_RE = re.compile(r'\b(Image|SymbolGlyph)\s*\(')
TEXT_RE = re.compile(r'\b(Text|TextInput|TextArea|Button|Toggle|Chip|TextPicker)\s*\(')
# 只有承载可见文字的 Text 才算「有文本」；`Text('')` 与 `Text(this.x)` 之外的空串要放行。
EMPTY_TEXT_RE = re.compile(r'\bText\s*\(\s*[\'"][\'"]\s*\)')
ATTR_ACCESSIBILITY_TEXT = '.accessibilityText('
ATTR_ACCESSIBILITY_LEVEL = '.accessibilityLevel('
# 让一个组件变成「可按」的属性；`bindMenu` 也是（点下去出菜单，同样要先说清它是干什么的）。
CLICK_ATTRS = ('.onClick(', '.onTouch(', '.gesture(', '.bindMenu(', '.bindContextMenu(')

# 返回 `A11y.*` 槽位 key 的纯函数白名单（R2 放行，函数体由对应模块的单测断言）。
SLOT_SOURCE_HELPERS = ('mediaCircleA11ySlot',)


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip(' \t'))


def is_comment(stripped: str) -> bool:
    """注释行不是语句：链式属性之间夹了注释（本仓很常见），上下扫都要跳过它。"""
    return stripped.startswith('//') or stripped.startswith('/*') or stripped.startswith('*')


def strip_braces_outside_code(line: str) -> str:
    """去掉字符串字面量里的花括号，避免 `$r('a{b}')` 打乱配对。"""
    out = []
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote is None:
            if ch in ('"', "'"):
                quote = ch
            elif ch == '`':
                quote = '`'
            out.append(ch)
        else:
            if ch == '\\':
                out.append(ch)
                i += 1
                if i < len(line):
                    out.append(line[i])
            elif ch == quote:
                quote = None
                out.append(ch)
            else:
                out.append('\u0000')  # 字符串内容不参与配对
        i += 1
    return ''.join(out)


def net_braces(line: str) -> int:
    stripped = line.strip()
    if is_comment(stripped):
        return 0  # 注释里写的 `{`/`}` 不参与配对
    s = strip_braces_outside_code(line)
    return s.count('{') - s.count('}')


def owner_of(lines, click_idx):
    """从点击属性行往上找它所属的组件调用行与块范围。

    返回 (owner_idx, block_end_idx, chain_indent)；找不到返回 None。

    本仓有两种链式写法，都要认：
      A 容器：`Row() {` / `}` / `.onClick(` 三者同级（块右括号与链同级）。
      B 叶子：`Image(...)` 在链的**上一级缩进**，链上各属性同级。
    """
    k = indent_of(lines[click_idx])
    if k == 0:
        return None
    j = click_idx - 1
    while j >= 0:
        stripped = lines[j].strip()
        ind = indent_of(lines[j])
        if stripped == '':
            j -= 1
            continue
        if is_comment(stripped):
            j -= 1
            continue
        if ind > k:
            j -= 1  # 嵌套体 / 上一个属性的多行 lambda
            continue
        if stripped.startswith('.'):
            j -= 1  # 同一条链上的其它属性
            continue
        if ind == k and stripped == '}':
            return match_block(lines, j, k)
        if ind < k:
            m = OPENER_RE.match(stripped)
            if m is not None and '{' not in stripped:
                return (j, j, k)  # 写法 B：叶子组件的链
            return None
        return None
    return None


def match_block(lines, close_idx, k):
    """配对找回 `}` 所属组件的起始行；起始行与 `}` 同级。"""
    d = 0
    i = close_idx
    while i >= 0:
        d += net_braces(lines[i])
        if d == 0:
            if indent_of(lines[i]) != k:
                return None
            if OPENER_RE.match(lines[i].strip()) is None:
                return None
            return (i, close_idx, k)
        i -= 1
    return None


def chain_after(lines, block_end, k):
    """组件块右括号之后的链式属性文本，直到同级下一条语句。"""
    out = []
    j = block_end + 1
    depth = 0
    while j < len(lines):
        stripped = lines[j].strip()
        ind = indent_of(lines[j])
        if stripped == '':
            j += 1
            continue
        if is_comment(stripped) and depth == 0:
            j += 1  # 链上的注释不算链的结束，也不计入属性文本
            continue
        if depth == 0 and ind <= k and not stripped.startswith('.'):
            break
        if stripped.startswith('.') or depth > 0:
            out.append(stripped)
        depth += net_braces(lines[j])
        if depth < 0:
            break
        j += 1
    return '\n'.join(out)


def block_text(lines, owner, block_end):
    return '\n'.join(lines[owner:block_end + 1])


def scan_coverage(files):
    """R1：图标-only 的可点击组件必须有 accessibilityText。"""
    violations = []
    for path in files:
        rel = path.relative_to(ROOT)
        lines = path.read_text(encoding='utf-8').splitlines()
        for idx, line in enumerate(lines):
            stripped = line.strip()
            if not any(stripped.startswith(attr) for attr in CLICK_ATTRS):
                continue
            found = owner_of(lines, idx)
            if found is None:
                continue
            owner, block_end, k = found
            body = block_text(lines, owner, block_end)
            chain = chain_after(lines, block_end, k)
            if ATTR_ACCESSIBILITY_TEXT in chain:
                continue
            if not ICON_RE.search(body):
                continue
            if has_visible_text(body):
                continue
            violations.append((str(rel), owner + 1, lines[owner].strip()[:60]))
    return violations


def has_visible_text(body: str) -> bool:
    """块内是否存在承载可见文字的组件。

    `Text()`（空实参）不算；`Text('Chats')`、`Text(this.x)`、`Text() { Span(...) }`
    这类有文案的算，因为屏幕朗读本来就能播报。正则里的 `\\(` 已经吃掉左括号，
    所以 `head` 是**左括号之后**的内容。
    """
    for m in TEXT_RE.finditer(body):
        head = body[m.end():].lstrip()
        if head.startswith(')'):
            rest = head[1:].lstrip()
            if rest.startswith('{'):
                return True  # Text() { Span(...) }
            continue
        literal = re.match(r"(?:['\"])(.*?)(?:['\"])", head)
        if literal:
            if literal.group(1).strip() != '':
                return True
            continue
        arg = re.match(r'([^\n]*)', head).group(1)
        if arg.split(')')[0].strip() != '':
            return True  # Text(this.x) / Text(`${n} selected`)
    return False


def load_a11y_table():
    if not A11Y_FILE.is_file():
        print(f'[a11y] ERROR: 找不到标签表 {A11Y_FILE}', file=sys.stderr)
        sys.exit(2)
    text = A11Y_FILE.read_text(encoding='utf-8')
    slots = dict(re.findall(r"static\s+readonly\s+([A-Z0-9_]+)\s*:\s*string\s*=\s*'([^']+)'", text))
    if not slots:
        print('[a11y] ERROR: A11y.ets 未解析出任何槽位（声明形状变了？）', file=sys.stderr)
        sys.exit(2)
    return slots


def load_dicts():
    if not LANG_FILE.is_file():
        print(f'[a11y] ERROR: 找不到词典 {LANG_FILE}', file=sys.stderr)
        sys.exit(2)
    text = LANG_FILE.read_text(encoding='utf-8')
    out = {}
    for lang in ('en', 'zh'):
        m = re.search(r'const ' + lang.upper() + r'_DICTIONARY: Record<string, string> = \{(.*?)\n\};',
                      text, re.S)
        if m is None:
            print(f'[a11y] ERROR: Lang.ets 未解析出 {lang.upper()}_DICTIONARY', file=sys.stderr)
            sys.exit(2)
        out[lang] = set(re.findall(r"^\s*'((?:[^'\\]|\\.)+)'\s*:", m.group(1), re.M))
    return out


def scan_routing(files, slots):
    """R2 + R3：标签只能走 `a11y(A11y.<槽位>[, 参数])`，且每个槽位都在表里声明。

    允许三元与实参（`a11y(this.isPlaying ? A11y.PAUSE : A11y.PLAY)`、
    `a11y(A11y.BOARD_CELL, item.emoji)`），但**不允许出现字面量字符串** ——
    一旦允许字面量，同一个动作在另一个页面就会被写成另一种说法。

    也允许标签来源是**返回槽位 key 的纯函数**（见 `SLOT_SOURCE_HELPERS`）：媒体圆钮那种
    「五态一钮」的判据散在四个 @Builder 里必然漂移，收敛成函数后调用点仍是 `a11y(...)`，
    口径真相依旧只有一处。
    """
    problems = []
    used = set()
    slot_name_re = re.compile(r'\bA11y\.([A-Z0-9_]+)')
    for path in files:
        rel = str(path.relative_to(ROOT))
        text = path.read_text(encoding='utf-8')
        lines = text.split('\n')
        for m in re.finditer(r'\.accessibilityText\(([^\n]*)', text):
            arg = m.group(1)
            line_no = text[:m.start()].count('\n') + 1
            # 文档块里的示例链不是调用点。
            if is_comment(lines[line_no - 1].lstrip()):
                continue
            if not arg.lstrip().startswith('a11y('):
                problems.append(f'{rel}:{line_no}: 实参未走 a11y(A11y.<槽位>) -> {arg.strip()[:70]}')
                continue
            if re.search(r"['\"]", arg):
                problems.append(f'{rel}:{line_no}: 标签里出现字面量字符串 -> {arg.strip()[:70]}')
                continue
            names = slot_name_re.findall(arg)
            if not names:
                if any(helper in arg for helper in SLOT_SOURCE_HELPERS):
                    continue
                problems.append(f'{rel}:{line_no}: 标签没有引用任何 A11y 槽位 -> {arg.strip()[:70]}')
                continue
            for name in names:
                used.add(name)
                if name not in slots:
                    problems.append(f'{rel}:{line_no}: A11y.{name} 未在标签表中声明')
    return problems, used


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--quiet', action='store_true')
    parser.add_argument('--basis', action='store_true', help='跳过 R1 覆盖检查')
    args = parser.parse_args()

    files = []
    for d in SCAN_DIRS:
        base = ROOT / d
        if not base.is_dir():
            continue
        for p in sorted(base.rglob('*.ets')):
            if any(part in SKIP_PARTS for part in p.parts):
                continue
            files.append(p)

    slots = load_a11y_table()
    dicts = load_dicts()

    # R3：标签表 -> 词典
    translation_problems = []
    for name, key in sorted(slots.items()):
        for lang in ('en', 'zh'):
            if key not in dicts[lang]:
                translation_problems.append(
                    f'A11y.{name} = {key!r} 缺 {lang.upper()} 译文（Lang 会原样回吐 key）')

    # R3b：被用到的槽位必须在表里；表里没用到的槽位不算错（预留给下一批）。
    routing_problems, used = scan_routing(files, slots)

    coverage_problems = [] if args.basis else scan_coverage(files)

    failed = bool(translation_problems or routing_problems or coverage_problems)
    if not args.quiet or failed:
        for msg in translation_problems:
            print(f'[a11y] TRANSLATION {msg}')
        for msg in routing_problems:
            print(f'[a11y] ROUTING {msg}')
        for rel, line, snippet in coverage_problems:
            print(f'[a11y] UNLABELED {rel}:{line}: {snippet}')
        if not args.quiet:
            print(f'[a11y] 槽位 {len(slots)} 个，调用点引用 {len(used)} 个，'
                  f'扫描文件 {len(files)} 个，未标注图标控件 {len(coverage_problems)} 处')
    if failed:
        print(f'[a11y] FAILED: 翻译缺项 {len(translation_problems)} / 路由 {len(routing_problems)} / '
              f'未标注 {len(coverage_problems)}', file=sys.stderr)
        return 1
    print('[a11y] OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
