#!/usr/bin/env python3
"""tools/ci/check_path_portability.py — 守卫脚本自身的跨平台路径口径自检。

## 为什么需要这个守卫

本仓的静态守卫有四个都要「按路径过滤/豁免」：`check_i18n_literals.py`、
`check_design_tokens.py`、`check_appstorage_pairs.py`、`check_accessibility_labels.py`。
它们共享同一条历史伤疤，而且**分三批暴露**：

1. `relative_to()` 在 Windows 上产出反斜杠，而 SKIP/豁免表按 `/` 写 → 过滤静默失效
   （2026-10-20，i18n 报 43 条幽灵 + 分层颠倒；design_tokens 直接 FileNotFoundError 崩）；
2. `subprocess(text=True)` 不指定 encoding → 中文 Windows 按 GBK 解码 UTF-8 输出崩
   （同期，check_codegen.py 明明 up to date 却报 AttributeError）；
3. `any(part in SKIP_PARTS for part in p.parts)` —— SKIP_PARTS 元素带斜杠、
   `p.parts` 只可能是裸目录名，两者永不相等 → 过滤从上线起就是**死代码**
   （2026-10-24 才发现；当时 SCAN_DIRS 恰好不含那些目录，所以没造成实际违规，
   但它是一道失效的防线）。

三批的共同点是**规则本身看起来完全正常**，坏的是「路径口径」这个元数据层。
所以这里不再逐个守卫补丁，而是用一条**机械可判的自检**把口径钉死：

  R1 凡出现 `relative_to(ROOT)` 的地方，必须紧跟 `.replace('\\\\', '/')`，
     或经由名为 `repo_rel` 的辅助函数；
  R2 凡 `p.parts` / `.parts` 与某个常量集合按 `in` 比较的地方，
     该常量集合里**不许**出现带斜杠的元素（`/build/` 那种），
     因为 `parts` 里永远是裸目录名；
  R3 凡 `subprocess.run(..., text=True)` 必须同时给 `encoding='utf-8'`
     （中文 Windows 的 locale 是 GBK）。

这条守卫只扫 `tools/ci/*.py` 自身，秒级完成，不依赖任何构建产物。
"""
import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CI_DIR = ROOT / 'tools' / 'ci'

# 自我豁免：本文件里难免出现被检查的那些字面形状（否则没法描述规则）。
SELF = pathlib.Path(__file__).name

REL_TO_RE = re.compile(r'\.relative_to\(\s*ROOT\s*\)')
# R2 的精确定义：只有当 `part`（或任意循环变量）遍历的是 **`.parts`** 时，
# 「常量里带斜杠」才是死代码。遍历字符串（`for part in repo_rel(p)` /
# `for part in rel`）时带斜杠是对的 —— 那正是子串匹配。
PARTS_IN_RE = re.compile(r'for\s+(\w+)\s+in\s+[\w.]*\.parts\b')
_CONST_TUPLE_RE = re.compile(r"^(\w+)\s*=\s*(?:frozenset\()?\(([^)]*)\)", re.M)
SUBPROCESS_RE = re.compile(r'subprocess\.run\(')


def read(path: pathlib.Path) -> str:
    return path.read_text(encoding='utf-8')


def strip_comments(text: str) -> str:
    """去掉注释与文档串后再判 —— 注释里举例说明不算违规。

    **必须保持行数不变**（被清掉的行留空串占位）：本守卫按行号报违规，
    早先直接 `continue` 跳过整行，470 行的文件被压成 371 行，报出来的行号
    全部错位 —— 拿 154 行去看，看到的是一句完全无关的 `j -= 1`。
    「行号对不上」比「不报」更糟：它会把人引到错的地方。
    """
    out = []
    in_block = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith('#'):
            out.append('')
            continue
        if in_block:
            if '"""' in line or "'''" in line:
                in_block = False
            out.append('')
            continue
        if stripped.startswith('"""') or stripped.startswith("'''"):
            if not (stripped.count('"""') >= 2 or stripped.count("'''") >= 2):
                in_block = True
            out.append('')
            continue
        hash_at = line.find('#')
        if hash_at >= 0:
            line = line[:hash_at]
        out.append(line)
    return '\n'.join(out)


def check_relative_to(code: str, name: str) -> list:
    """R1：`relative_to(ROOT)` 的结果必须归一成 `/`，或落在 repo_rel() 里。

    只在**同一行**同时出现「赋值」与 `relative_to(ROOT)` 时判 —— 那才是
    「这个相对路径被算出来并可能被后续过滤/比较使用」的那一份。
    直接嵌在推导式、f-string 里的不影响过滤语义，不报（早先不区分时
    对四个脚本一次报出 4 条假阳性，全是 `relative_to` 在别处、而这一行
    恰好有别的 `=`）。
    """
    problems = []
    lines = code.splitlines()
    for idx, line in enumerate(lines):
        if REL_TO_RE.search(line) is None:
            continue
        # 本行必须是一个赋值（`x = ... relative_to ...`），而不是在别处用它
        if re.search(r'(?<![=!<>])=(?!=)', line) is None:
            continue
        # 允许：赋值处就带 replace（归一化的正确形状）
        if ".replace('\\\\', '/')" in line or '.replace("\\\\", "/")' in line:
            continue
        # 允许：这是 repo_rel 的函数体（替身本体）
        enclosing = '\n'.join(lines[max(0, idx - 3):idx + 2])
        if 'def repo_rel' in enclosing:
            continue
        problems.append(
            f'{name}:{idx + 1}: relative_to(ROOT) 的结果未归一成 "/" '
            f'（必须 replace("\\\\", "/") 或走 repo_rel()；否则 Windows 上过滤静默失效）')
    return problems


def const_values(code: str, const_name: str) -> list:
    for m in _CONST_TUPLE_RE.finditer(code):
        if m.group(1) == const_name:
            return re.findall(r"""['"]([^'"]*)['"]""", m.group(2))
    return []


def check_parts_compare(code: str, name: str) -> list:
    """R2：遍历 `.parts` 的循环体里，与常量集合按 `in` 比较的元素不许带斜杠。

    精确到「循环变量来自 `.parts`」这一层：
      - `for part in p.parts:` + `if any(part in SKIP_PARTS …)`  → 判（SKIP 元素须裸名）
      - `for part in rel:`      + `if any(part in SKIP_PARTS …)`  → 不判（rel 是字符串，
                                                                     带斜杠才对）
    这条区分是必要的：早先不分时，本守卫对四个脚本一次报出 25 条假阳性，
    把「子串匹配」误判成「parts 比较」。
    """
    problems = []
    lines = code.splitlines()
    for idx, line in enumerate(lines):
        m = PARTS_IN_RE.search(line)
        if m is None:
            continue
        loop_var = m.group(1)
        # 在该循环头之后的一段窗口里找 `loop_var in <CONST>` 形状
        window = '\n'.join(lines[idx:idx + 12])
        use_re = re.compile(re.escape(loop_var) + r'\s+in\s+([A-Z_][A-Z0-9_]*)')
        for u in use_re.finditer(window):
            const_name = u.group(1)
            for v in const_values(code, const_name):
                if '/' in v or '\\' in v:
                    line_no = idx + 1
                    problems.append(
                        f'{name}:{line_no}: {const_name} 的元素 {v!r} 带斜杠，'
                        f'但它被拿去与 `.parts` 比较 —— `parts` 里永远是裸目录名'
                        f'（"oh_modules" 而非 "/oh_modules/"），这个比较永远为假，等于没有过滤')
    return problems


def check_subprocess_encoding(code: str, name: str) -> list:
    """R3：subprocess.run(..., text=True) 必须显式给 encoding。"""
    problems = []
    for m in SUBPROCESS_RE.finditer(code):
        tail = code[m.start():m.start() + 400]
        # 截到本调用的右括号为止（粗略：到下一个空行为止）
        if 'text=True' not in tail and 'universal_newlines' not in tail:
            continue
        if 'encoding=' in tail:
            continue
        line_no = code[:m.start()].count('\n') + 1
        problems.append(
            f'{name}:{line_no}: subprocess.run(text=True) 未指定 encoding —— '
            f'中文 Windows 的 locale 是 GBK，解 UTF-8 输出会抛 UnicodeDecodeError，'
            f'且症状是「明明成功却报崩」')
    return problems


# ---- --self-test：证明上面三条真的会拦 --------------------------------------------
# 与 i18n 守卫同一套纪律：规则要「该拦必拦、不该报必不报」，否则全绿没有意义。
SELF_CASES = (
    ('r1-bad', check_relative_to,
     'rel = str(path.relative_to(ROOT))\n', True),
    ('r1-good-replace', check_relative_to,
     "rel = str(path.relative_to(ROOT)).replace('\\\\', '/')\n", False),
    ('r1-good-helper', check_relative_to,
     "def repo_rel(path):\n    return str(path.relative_to(ROOT)).replace('\\\\\\\\', '/')\n", False),
    ('r2-bad', check_parts_compare,
     "SKIP = ('/build/', '/oh_modules/')\n"
     "if any(part in SKIP for part in p.parts):\n    pass\n", True),
    ('r2-good', check_parts_compare,
     "SKIP = ('build', 'oh_modules')\n"
     "if any(part in SKIP for part in p.parts):\n    pass\n", False),
    ('r3-bad', check_subprocess_encoding,
     "res = subprocess.run(cmd, capture_output=True, text=True)\n", True),
    ('r3-good', check_subprocess_encoding,
     "res = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8')\n", False),
    ('r3-good-binary', check_subprocess_encoding,
     "res = subprocess.run(cmd, capture_output=True)\n", False),
)


def self_test() -> int:
    failures = 0
    for label, fn, src, expect_fire in SELF_CASES:
        problems = fn(strip_comments(src), 'sample.py')
        fired = bool(problems)
        if fired != expect_fire:
            print(f'[path-selftest] FAIL {label}: 期望 {"报告" if expect_fire else "不报"}，'
                  f'实际 {"报告" if fired else "不报"}', file=sys.stderr)
            failures += 1
    if failures:
        print(f'[path-selftest] FAILED: {failures} / {len(SELF_CASES)} 项对照不符', file=sys.stderr)
        return 1
    print(f'[path-selftest] OK: {len(SELF_CASES)} 项对照全部符合预期')
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    if self_test() != 0:
        print('[path] FAILED: 负向对照不符 —— 先修脚本，再谈代码', file=sys.stderr)
        return 1

    problems = []
    scanned = 0
    for path in sorted(CI_DIR.glob('*.py')):
        if path.name == SELF:
            continue
        code = strip_comments(read(path))
        scanned += 1
        problems += check_relative_to(code, path.name)
        problems += check_parts_compare(code, path.name)
        problems += check_subprocess_encoding(code, path.name)

    if problems:
        for msg in problems:
            print(f'[path] {msg}')
        print(f'[path] FAILED: {len(problems)} 处路径口径问题', file=sys.stderr)
        return 1
    print(f'[path] OK: {scanned} 个 CI 脚本的路径口径一致（归一化 / parts 比较 / 子进程编码）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
