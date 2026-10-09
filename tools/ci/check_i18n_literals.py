#!/usr/bin/env python3
"""tools/ci/check_i18n_literals.py — 视图层文案与词典一致性守卫（I18N-LITERAL-101 引入）。

背景：`Lang` 与 EN/ZH 两本词典从 SET-103 起就在，设置线（feature/settings）也都走 `this.t(...)`，
但聊天/资料/贴纸那几批页面是直接把中文写进 `Text('清空历史记录')` 的。写死中文的代价不是「不国际化」
这么抽象 —— 上一轮就撞过一次：`Index.ets` 用了 key `'Sticker set: %s'`，两本词典里都没有这一项，
`Lang` 缺译文时**原样回吐 key**，于是 Toast 上屏的是 `Sticker set: %s` 本身。也就是说
「key 拼错」和「漏翻译」在屏幕上长得一模一样，没人会当场发现。

本脚本守三条：

  R1 视图层字面量禁令：`entry` 与各 `feature/*` 的 **pages/ 与 components/** 下，任何 .ets 文件
     里都不允许出现含汉字的字符串字面量（emoji 不在 `一-鿿` 段内，不会被误伤）。
     理由是这一层是「文案的显示端」：文案的真相只在 `Lang.ets` 一处，页面里出现中文就说明
     这一句永远不会随语言变，而下一个改词典的人根本看不到它。
     就地豁免：行尾写 `// i18n-allow <原因>`。豁免必须带原因 —— 本仓目前只有两类合法豁免：
     日期/相对时间的**形态**（`10月3日` vs `Oct 3`，不是换词条而是换排布，归 I18N-DATE 一包），
     以及语言选择器里的**本族名**（'简体中文' 在英文界面也该是 '简体中文'）。
  R2 key 必须双词典命中：`getString('X')` / `.t('X')` / `t('X')` / `formatByKey('X', ...)` 的**字面量**
     key 必须同时存在于 EN 与 ZH。这就是上面那次事故的直接防线。动态 key（变量、三元）不在射程内，
     所以 R3 兜住整本表。
  R3 两本词典 key 集合全等：EN 有 ZH 没有 = 中文界面回吐英文原文；ZH 有 EN 没有 = 英文界面回吐中文。
     两个方向都是「界面上出现另一种语言」，所以全等比「ZH 覆盖 EN 的差集」更严，也更便宜。

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


def is_comment(stripped: str) -> bool:
    return stripped.startswith('//') or stripped.startswith('/*') or stripped.startswith('*')


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
                                    f'（本仓只有日期形态与本族名两类合法豁免）')
                else:
                    allowed.append(f'{rel}:{idx + 1}')
                continue
            problems.append(f'{rel}:{idx + 1}: 视图层写死中文文案 -> {hit}（改走 Lang key，'
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

    literal_problems, allowed = scan_literals(files)
    key_problems, checked = scan_keys(files, dicts)
    parity_problems = scan_parity(dicts)

    failed = bool(literal_problems or key_problems or parity_problems)
    if not args.quiet or failed:
        for msg in literal_problems:
            print(f'[i18n] LITERAL {msg}')
        for msg in key_problems:
            print(f'[i18n] MISSING-KEY {msg}')
        for msg in parity_problems:
            print(f'[i18n] PARITY {msg}')
        if not args.quiet:
            print(f'[i18n] 视图层文件 {len(files)} 个，字面量 key 调用点覆盖 {len(checked)} 个，'
                  f'词典 EN {len(dicts["EN"])} / ZH {len(dicts["ZH"])} 条，'
                  f'就地豁免 {len(allowed)} 处')
    if failed:
        print(f'[i18n] FAILED: 写死文案 {len(literal_problems)} / 缺词条 {len(key_problems)} / '
              f'词典不对称 {len(parity_problems)}', file=sys.stderr)
        return 1
    print('[i18n] OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
