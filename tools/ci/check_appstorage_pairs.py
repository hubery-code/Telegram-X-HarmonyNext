#!/usr/bin/env python3
"""tools/ci/check_appstorage_pairs.py — AppStorage 键读写配对守卫（APPSTORAGE-PAIR-101 引入）。

背景：`AppStorage` 是 ArkUI 的进程内全局袋，本仓用它做「业务层 → 装配层」的唯一通道
（业务层零 Kit 依赖，落盘由 entry 完成）。键名是**字符串约定**，两端各写一次，编译器和
运行时都不校验 —— 于是长出过一整类静默失效：

  `SettingsReducer` 里 `AppStorage.setOrCreate('appLanguage', pref)` 全仓只有这一个写、
  零个读。用户在应用内选的语言在第一次冷启动时全丢，不报错、不打日志、测试也全绿。
  同一段代码里还留着一个更早的兄弟键 `'languagePreference'`，同样只有写。
  （LANG-PERSIST-101 修的是这一类的第一起；`'themeMode'` / `'themePreference'` 是第二起。）

规则四条：

  R1 配对：每个键必须**既有写又有读**。
     写 = `AppStorage.set(...)` / `AppStorage.setOrCreate(...)`；
     读 = `AppStorage.get(...)` / `AppStorage.has(...)` / `@StorageProp` / `@StorageLink`；
     `PersistentStorage.persistProp(...)` 同时算两端。
     只有写没有读 → DEAD-WRITE（值进了内存没人取，等于把设置写在空气上）；
     只有读没有写 → ORPHAN-READ（永远读到装饰器里的默认值，看着像功能其实是常量）。
  R2 键必须是**字面量**，或能解析到字面量的 `const`
     （`export const KEY_APP_LANGUAGE: string = 'appLanguage';`）。
     拼接、模板串、解析不到的变量都拦 —— 配对判定的前提是两个端点解析出同一个串。
  R3 常量名与字面量形状一致：`KEY_APP_LANGUAGE` ↔ `'appLanguage'`。
     钉的是跨层契约：reducer 那端写的是字面量、store 这端用的是常量，两边一旦漂移
     （本仓真漂移过：`appLanguage` vs `languagePreference`），编译和运行都不响。
  R4 豁免：违规行本身或其上一行含 `appstorage-allow <原因>` 即跳过（必须带原因）。

用法：python3 tools/ci/check_appstorage_pairs.py [--basis]
  --basis 只打印键清单与各端点计数，用于盘点与写文档。
退出码：0 = 无违规；1 = 存在违规；2 = 脚本自身前置条件坏了（扫不到任何源文件）
"""

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

SCAN_DIRS = (
    ['entry/src/main/ets']
    + [str(p.relative_to(ROOT)) for p in ROOT.glob('feature/*/src/main/ets')]
    + [str(p.relative_to(ROOT)) for p in ROOT.glob('core/*/src/main/ets')]
    + [str(p.relative_to(ROOT)) for p in ROOT.glob('platform/*/src/main/ets')]
)

SKIP_PARTS = ('/oh_modules/', '/build/', '/.test/', '/.preview/', '/node_modules/')

ALLOW_RE = re.compile(r'appstorage-allow\s+\S')

# 三个捕获组依次是：单引号字面量、双引号字面量、标识符（可能带成员访问）。
KEY_ARG_RE = r"(?:'([A-Za-z0-9_]+)'|\"([A-Za-z0-9_]+)\"|([A-Za-z_][A-Za-z0-9_.]*))"
WRITE_RE = re.compile(r'AppStorage\s*\.\s*(?:setOrCreate|set)\s*(?:<[^>()]*>)?\s*\(\s*' + KEY_ARG_RE)
GET_RE = re.compile(r'AppStorage\s*\.\s*(?:get|has)\s*(?:<[^>()]*>)?\s*\(\s*' + KEY_ARG_RE)
DECOR_RE = re.compile(r'@Storage(?:Prop|Link)\s*\(\s*' + KEY_ARG_RE)
PERSIST_RE = re.compile(
    r'PersistentStorage\s*\.\s*persistProp\s*(?:<[^>()]*>)?\s*\(\s*' + KEY_ARG_RE)
CONST_RE = re.compile(
    r'(?:export\s+)?const\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*(?:readonly\s+)?string)?\s*=\s*'
    r"[\"']([A-Za-z0-9_]+)[\"']"
)


def strip_comments(text: str) -> str:
    """把行注释与块注释替换成等量空格，保住行号与列位置。

    行号必须保住：违规定位和 R4 的「上一行豁免」都按行算。字符串里的 `//`
    （深链、URL）不能当注释，所以按字符扫描并跟踪引号状态。
    """
    out = []
    i = 0
    n = len(text)
    in_block = False
    quote = ''
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ''
        if in_block:
            if ch == '*' and nxt == '/':
                in_block = False
                out.append('  ')
                i += 2
                continue
            out.append('\n' if ch == '\n' else ' ')
            i += 1
            continue
        if quote:
            out.append(ch)
            if ch == '\\':
                if i + 1 < n:
                    out.append(text[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = ''
            i += 1
            continue
        if ch in ('"', "'", '`'):
            quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == '/' and nxt == '/':
            while i < n and text[i] != '\n':
                out.append(' ')
                i += 1
            continue
        if ch == '/' and nxt == '*':
            in_block = True
            out.append('  ')
            i += 2
            continue
        out.append(ch)
        i += 1
    return ''.join(out)


def collect_files():
    files = []
    for rel_dir in SCAN_DIRS:
        d = ROOT / rel_dir
        if not d.is_dir():
            continue
        for p in sorted(d.rglob('*.ets')):
            if any(part in str(p) for part in SKIP_PARTS):
                continue
            files.append(p)
    return files


def camel_of_const(name: str) -> str:
    """KEY_APP_LANGUAGE -> appLanguage（剥掉 KEY_ 前缀，snake 转 lowerCamel）。"""
    body = name[len('KEY_'):] if name.startswith('KEY_') else name
    parts = [seg for seg in body.split('_') if seg]
    if not parts:
        return ''
    return parts[0].lower() + ''.join(seg[:1].upper() + seg[1:].lower() for seg in parts[1:])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--basis', action='store_true', help='只打印键清单与端点计数')
    args = parser.parse_args()

    files = collect_files()
    if not files:
        print('[appstorage] ERROR: 未扫描到任何 .ets 源文件（目录约定变了？）', file=sys.stderr)
        return 2

    consts = {}
    bodies = {}
    raw_lines = {}
    for path in files:
        rel = str(path.relative_to(ROOT))
        try:
            text = path.read_text(encoding='utf-8')
        except OSError as exc:
            print(f'[appstorage] ERROR: 读取失败 {rel}: {exc}', file=sys.stderr)
            return 2
        bodies[rel] = strip_comments(text)
        raw_lines[rel] = text.splitlines()
        for name, value in CONST_RE.findall(bodies[rel]):
            consts.setdefault(name, value)

    writers = {}
    readers = {}
    dynamic = []

    def add(bucket, key, rel, lineno, expr):
        bucket.setdefault(key, []).append((rel, lineno, expr))

    def exempt(rel, lineno):
        if lineno > len(raw_lines[rel]):
            return False
        if ALLOW_RE.search(raw_lines[rel][lineno - 1]):
            return True
        return lineno >= 2 and bool(ALLOW_RE.search(raw_lines[rel][lineno - 2]))

    def resolve(rel, lineno, expr):
        """字面量直接用；标识符查常量表；查不到记 R2 并返回 None。"""
        if re.fullmatch(r"[\"'][A-Za-z0-9_]+[\"']", expr):
            return expr.strip('"\'')
        head = expr.split('.')[0]
        if head in consts:
            return consts[head]
        dynamic.append((rel, lineno, expr))
        return None

    for rel, body in bodies.items():
        for lineno, line in enumerate(body.splitlines(), start=1):
            for regex, role in ((WRITE_RE, 'write'), (GET_RE, 'read'),
                                (DECOR_RE, 'read'), (PERSIST_RE, 'both')):
                for m in regex.finditer(line):
                    literal, dquote, ident = m.group(1), m.group(2), m.group(3)
                    if literal or dquote:
                        key = literal or dquote
                        expr = key
                    else:
                        key = resolve(rel, lineno, ident)
                        expr = ident
                    if key is None:
                        continue
                    if role in ('write', 'both'):
                        add(writers, key, rel, lineno, expr)
                    if role in ('read', 'both'):
                        add(readers, key, rel, lineno, expr)

    name_drift = []
    for name, value in sorted(consts.items()):
        if not name.startswith('KEY_'):
            continue
        expected = camel_of_const(name)
        if expected and expected != value:
            name_drift.append((name, value, expected))

    all_keys = sorted(set(writers) | set(readers))
    dead_writes = [(k, v) for k, v in
                   ((k, writers[k]) for k in all_keys if k in writers and k not in readers)
                   if not all(exempt(rel, lineno) for rel, lineno, _ in v)]
    orphan_reads = [(k, v) for k, v in
                    ((k, readers[k]) for k in all_keys if k in readers and k not in writers)
                    if not all(exempt(rel, lineno) for rel, lineno, _ in v)]
    dynamic = [(rel, lineno, expr) for rel, lineno, expr in dynamic if not exempt(rel, lineno)]

    if args.basis:
        print(f'[appstorage] 扫描 {len(files)} 个文件，常量 {len(consts)} 个，键 {len(all_keys)} 个')
        for key in all_keys:
            print(f'  {key}: 写 {len(writers.get(key, []))} / 读 {len(readers.get(key, []))}')
        return 0

    problems = 0
    where = lambda expr, key: f'（键表达式 {expr}）' if expr != key else ''
    for key, hits in dead_writes:
        problems += 1
        for rel, lineno, expr in hits:
            print(f'[appstorage] DEAD-WRITE 键 {key!r} 只有写没有读（值进内存即丢）—— '
                  f'{rel}:{lineno}: {raw_lines[rel][lineno - 1].strip()}{where(expr, key)}')
    for key, hits in orphan_reads:
        problems += 1
        for rel, lineno, expr in hits:
            print(f'[appstorage] ORPHAN-READ 键 {key!r} 只有读没有写（读到的是默认值）—— '
                  f'{rel}:{lineno}: {raw_lines[rel][lineno - 1].strip()}{where(expr, key)}')
    for rel, lineno, expr in dynamic:
        problems += 1
        print(f'[appstorage] DYNAMIC-KEY 键表达式 {expr} 解析不到字面量，配对判定失效 —— '
              f'{rel}:{lineno}: {raw_lines[rel][lineno - 1].strip()}')
    for name, value, expected in name_drift:
        problems += 1
        print(f'[appstorage] NAME-DRIFT 常量 {name} = {value!r}，与应有的键名形状 {expected!r} 不一致')

    if problems:
        print(f'[appstorage] FAIL: 违规 {problems} 处（死写 {len(dead_writes)} / 孤儿读 {len(orphan_reads)}'
              f' / 动态键 {len(dynamic)} / 名值漂移 {len(name_drift)}）')
        return 1

    print(f'[appstorage] OK: {len(all_keys)} 个 AppStorage 键全部成对'
          f'（写 {sum(len(v) for v in writers.values())} 处 / 读 {sum(len(v) for v in readers.values())} 处），'
          f'动态键 0 处、名值漂移 0 处')
    return 0


if __name__ == '__main__':
    sys.exit(main())
