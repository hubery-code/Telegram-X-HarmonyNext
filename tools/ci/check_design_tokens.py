#!/usr/bin/env python3
"""tools/ci/check_design_tokens.py — 设计 token 静态校验（INTEG-002 引入）。

背景（真实事故）：`T.typography.caption1` 这类**拼错的 token 名**在 ArkTS 下
**编译期不报错**——`Theme.typography` 被当成可索引对象，取到的是 `undefined`，
只有在**该渲染分支真的被执行**时才在 `.fontSize(undefined.fontSize)` 处抛
`TypeError`，进而被 ArkUI 记为 JsError 直接杀进程（exit 254）。

SEARCH-101 的 SearchPage 有 5 处 `caption1`、2 处 `caption2`、2 处 `radius.xs`，
因为搜索结果分段只在"有结果"时渲染，所以单测（reducer 纯函数）与空态真机都
测不出来；直到 INTEG-002 把搜索页接上导航、输入真实关键词才必现崩溃。

本脚本把这类缺陷前移到 CI：扫描所有 `.<namespace>.<name>` 用法，与
core/design_system 里真实定义的 token 名逐一比对，发现未定义即失败。

正则不限定接收者：PRIVACY-101 的详情页选择器写 `this.getTheme().typography.title3`
而不是 `T.typography.title3`，旧的「只认 T. 前缀」口径完全看不见它，装上真机一打开就
JsError 杀进程。写法五花八门，未定义的 token 名才是问题本身。

用法：python3 tools/ci/check_design_tokens.py [--quiet]
退出码：0 = 全部合法；1 = 存在未定义 token
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DS = ROOT / 'core' / 'design_system' / 'src' / 'main' / 'ets'

# 每个命名空间对应的定义文件与成员声明形状。
NAMESPACES = {
    'typography': ('Typography.ets', r'^\s+([A-Za-z0-9_]+):\s*TextStyle;'),
    'colors': ('Colors.ets', r'^\s+([A-Za-z0-9_]+):\s*string;'),
    'spacing': ('Spacing.ets', r'^\s+([A-Za-z0-9_]+):\s*number;'),
    'radius': ('Radius.ets', r'^\s+([A-Za-z0-9_]+):\s*number;'),
}

SKIP_PARTS = ('/oh_modules/', '/build/', '/.test/', '/design_system/')
USAGE_RE = re.compile(r'\.(typography|colors|spacing|radius)\.([A-Za-z0-9_]+)')


def load_defined() -> dict:
    defined = {}
    for ns, (filename, pattern) in NAMESPACES.items():
        path = DS / filename
        if not path.is_file():
            print(f'[tokens] ERROR: 找不到定义文件 {path}', file=sys.stderr)
            sys.exit(2)
        text = path.read_text(encoding='utf-8')
        names = set(re.findall(pattern, text, re.M))
        if not names:
            print(f'[tokens] ERROR: {filename} 未解析出任何 token（声明形状变了？）', file=sys.stderr)
            sys.exit(2)
        defined[ns] = names
    return defined


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--quiet', action='store_true')
    args = parser.parse_args()

    defined = load_defined()
    if not args.quiet:
        for ns in sorted(defined):
            print(f'[tokens] {ns}: {len(defined[ns])} 个')

    violations = {}
    for path in sorted(ROOT.rglob('*.ets')):
        rel = '/' + str(path.relative_to(ROOT))
        if any(part in rel for part in SKIP_PARTS):
            continue
        text = path.read_text(encoding='utf-8', errors='ignore')
        for match in USAGE_RE.finditer(text):
            ns, name = match.group(1), match.group(2)
            if name not in defined[ns]:
                line = text[:match.start()].count('\n') + 1
                violations.setdefault(f'{ns}.{name}', []).append(f'{path.relative_to(ROOT)}:{line}')

    if not violations:
        print('[tokens] OK: 未发现未定义的 design token')
        return 0

    print(f'[tokens] FAIL: 发现 {len(violations)} 个未定义的 design token', file=sys.stderr)
    print('[tokens] 这类错误编译期不报错，只在渲染到该分支时抛 TypeError 杀进程。', file=sys.stderr)
    for key in sorted(violations):
        ns = key.split('.')[0]
        candidates = sorted(defined[ns])
        print(f'  - T.{key}  ({len(violations[key])} 处)', file=sys.stderr)
        for loc in violations[key][:10]:
            print(f'      {loc}', file=sys.stderr)
        print(f'      可用: {", ".join(candidates)}', file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main())
