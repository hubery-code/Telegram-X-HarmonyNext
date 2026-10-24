"""删符号之后的一致性扫描：找「导出了/定义了但已经删掉、引用处却没改」的残留。

## 为什么需要它

删一个功能（或删一批常量）时，最容易漏的不是删除本身，而是**引用处**：
删了 `DEFAULT_RECENT_GIFS` 但 `Index.ets` 还在 `export { ... DEFAULT_RECENT_GIFS }`、
删了 `LoadProxies` 但某个页面的 `aboutToAppear` 还在 `new LoadProxies()`。
这类错误编译器一定会报，但一次全量构建 10~20 分钟，而纯文本扫描几秒就能定位。

2026-10-24 那一轮就是这么撞上的：REMOVE-PROXY-101 与 GIF-SEND-101 各自删完了
「自己的文件」，却在**别人的文件**里留下了三处引用（`SettingsOverlayBack` 的重复
import、`SettingsPage` 的 `LoadProxies`、`Index.ets` 的 `DEFAULT_RECENT_GIFS`），
每跑一次构建才暴露一批。

## 射程与判据

只扫**非生成代码**（排除 `core/td_api_generated` —— 那里 3205 个 DTO 天然会出现
`ProxyType` 之类的名字，那是 IDL 自动生成的类型，不是我们的消费点；不排除会让扫描
慢十倍并报一堆假阳性）。

判据只认三种「真引用」形状，避免误报：
  - `import ... { Name } ...` 里出现；
  - `new Name(` 构造；
  - `Name(` 直接调用。
纯注释、纯文档串不算。

## 刻意不做的事

**不做「导入但未使用」检查**。试过一版，对全仓报出 171 条，其中绝大多数是无害的
历史遗留（ArkTS 对未使用 import 不报错），信噪比太低，真问题会被淹掉。
"""
import glob
import io
import re
import sys

SKIP_PARTS = ('/oh_modules/', '/build/', '/.test/', '/.preview/',
              '/node_modules/', '/td_api_generated/')

# 本次及以后「已删除」的符号清单。删新东西时往这里加一行即可。
REMOVED_SYMBOLS = (
    # GIF-SEND-101：占位动图库整体删除
    'DEFAULT_RECENT_GIFS', 'DEFAULT_GIF_PACKS',
    # REMOVE-PROXY-101：代理功能整体删除
    'ProxySettings', 'ProxySubPage', 'LoadProxies', 'SaveProxy', 'DeleteProxy',
    'ProxyRow', 'OpenProxyPage', 'CloseProxyPage', 'PingProxy',
)


def source_files():
    out = []
    for pat in ('feature/*/src/**/*.ets', 'core/*/src/**/*.ets',
                'platform/*/src/**/*.ets', 'entry/src/**/*.ets'):
        for p in glob.glob(pat, recursive=True):
            norm = p.replace('\\', '/')
            if any(s in norm for s in SKIP_PARTS):
                continue
            out.append(norm)
    return out


def main() -> int:
    files = source_files()
    problems = []
    for p in files:
        try:
            text = io.open(p, encoding='utf-8', errors='ignore').read()
        except OSError:
            continue
        for i, line in enumerate(text.splitlines(), 1):
            s = line.strip()
            if s.startswith(('//', '*', '/*')):
                continue
            for name in REMOVED_SYMBOLS:
                if not re.search(r'\b' + re.escape(name) + r'\b', s):
                    continue
                is_import = ('import' in s) or (s.startswith(name)) or (', ' + name in s)
                is_ctor = ('new ' + name) in s
                is_call = (name + '(') in s
                if is_import or is_ctor or is_call:
                    problems.append(f'{p}:{i}: 仍引用已删除的 {name} -> {s[:90]}')

    if problems:
        for x in problems:
            print('[removed-symbol] ' + x)
        print(f'[removed-symbol] FAILED: {len(problems)} 处残留引用', file=sys.stderr)
        return 1
    print(f'[removed-symbol] OK: {len(files)} 个文件，{len(REMOVED_SYMBOLS)} 个已删除符号无残留引用')
    return 0


if __name__ == '__main__':
    sys.exit(main())
