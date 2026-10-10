#!/usr/bin/env python3
"""tools/ci/check_i18n_literals.py — 视图层文案与词典一致性守卫（I18N-LITERAL-101 引入）。

背景：`Lang` 与 EN/ZH 两本词典从 SET-103 起就在，设置线（feature/settings）也都走 `this.t(...)`，
但聊天/资料/贴纸那几批页面是直接把中文写进 `Text('清空历史记录')` 的。写死中文的代价不是「不国际化」
这么抽象 —— 上一轮就撞过一次：`Index.ets` 用了 key `'Sticker set: %s'`，两本词典里都没有这一项，
`Lang` 缺译文时**原样回吐 key**，于是 Toast 上屏的是 `Sticker set: %s` 本身。也就是说
「key 拼错」和「漏翻译」在屏幕上长得一模一样，没人会当场发现。

本脚本守八条（R4' 与 R5a/R5b 是各自规则内的子条，不另计）：

  R1 视图层字面量禁令：`entry` 与各 `feature/*` 的 **pages/ 与 components/** 下，任何 .ets 文件
     里都不允许出现含汉字的字符串字面量（emoji 不在 `一-鿿` 段内，不会被误伤）。
     理由是这一层是「文案的显示端」：文案的真相只在 `Lang.ets` 一处，页面里出现中文就说明
     这一句永远不会随语言变，而下一个改词典的人根本看不到它。
     就地豁免：行尾写 `// i18n-allow <原因>`。豁免必须带原因，且**日期/时间形态不在合法类别里**
     （I18N-DATE-101 起由 R8 收口）：本仓剩下的两类是语言选择器里的**本族名**
     （'简体中文' 在英文界面也该是 '简体中文'），以及 R4 的**源语言标签**
     （English 界面里的 'English' 本来就该长这样）。
  R2 key 必须双词典命中：`getString('X')` / `.t('X')` / `t('X')` / `formatByKey('X', ...)` 的**字面量**
     key 必须同时存在于 EN 与 ZH。这就是上面那次事故的直接防线。动态 key（变量、三元）不在射程内，
     所以 R3 兜住整本表。射程 = 视图层 + 数据层（I18N-LITERAL-103 起 coordinator/model 里的
     `getString('X')` 同样进检，否则这一路的新调用一个都不被查）。
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
  R4' 收紧（I18N-LITERAL-104）：口径从「词典已知的英文」扩成**「看着像文案的英文」**。
     第五十三轮设备取证抓到的一批（`SearchPage` 的 `Search Telegram`、`ChatProfilePage` 的
     `Channel Info` / `Description`）之所以四条规则一起放行，正是旧口径只认词典里**已有**的项 ——
     「压根没建词条」这个状态本身是漏洞，而且它是 R2 唯一管不到的写法（key 从没进过 `t()`，
     R2 无从判断）。收紧后按形状判「看着像文案」：含空格、或首字母大写、或命中词典，任一成立即算。
     这条形状判据把技术 token 挡在射程外（`'zh'` / `'mtproto'` / `'app.media.ic_help'` /
     `'proxy.example.com'` 都是小写、无空格、不在词典里），而 `All` / `Trending` / `Draft: `
     这类真文案全部落网；`${…}` 占位段先剥掉再判，于是 `@${username}`、`${n} ms` 不误伤；
     剥完不足两字符（头像兜底的 `'A'`）不算文案。仍然**只认文案槽位**，槽位外的英文不归本规则管。
     103 记为射程外的**构造点**（`new DrawerMenuRow('calls', icon, 'Calls', false)`）这一轮
     由 R5b 的新位置④与 R6 一起接管，不再需要视图层单独看它。
  R5 数据层展示串禁令（I18N-LITERAL-103 引入）：R1/R4 只看 `*/pages/` 与 `*/components/`，于是
     coordinator / model / reducer / contract 里拼好的显示串一路畅通 —— `return '最近上线'`、
     `this.toastPort.showToast('清空历史失败')`、`summary = 'Photo'` 都改不到词典。这类串比页面里的
     更隐蔽：它藏在「数据加工函数」里，改词典的人根本不会想到那一屏的字是这儿来的。
     口径与 R1/R4 同构，按文件分两层：
       R5a 汉字禁令 —— `entry` 与 `feature/*` 里 **不在** pages//components/ 下的 .ets，
            任何含汉字的字符串字面量都是违规（豁免同 R1：就地 `// i18n-allow <原因>`，
            日期形态那一类已由 R8 作废）。
       R5b 词典已知英文 —— 同批文件里，值命中词典（EN ∪ ZH）的英文字面量出现在四个位置之一：
            ① `return` 的**直接**操作数（`return 'Photo';`；要求字面量外层没有任何调用）；
            ② 显示出口 `showToast(` / `showHintToast(` 的实参；
            ③（I18N-LITERAL-104）**赋值右侧** —— `const message: string = x ? 'A' : 'B'`、
               `summary = 'Photo'`、`export const SAVED_MESSAGES_TITLE = 'Saved Messages'`
               这一整类「先存进中间变量、函数末尾才 return」的串。103 只登记了它们没管住，
               本包把 `SAVED_MESSAGES_TITLE` → `SAVED_MESSAGES_TITLE_KEY`、
               `ShowToastEffect.message` → `messageKey` 逐个改名，于是这一位置从此只放行 key 载体；
            ④（I18N-LITERAL-104）**构造器实参** —— `new ProxyStatus('Connected', …)`、
               `new DrawerMenuRow('saved', icon, 'Saved Messages', true)`。判这一类要认参数名，
               所以脚本先对全仓 `src/main/ets` 的 .ets 建一遍「class → constructor 参数表」索引
               （跨文件也查得到），参数名以 `key` 结尾（`key` / `labelKey` / `messageKey`）视为
               key 载体而豁免；参数表查不到（构造器在索引范围外的模块）不臆断，直接跳过。
            豁免在 R4 的两类（`t()`/`getString()`/`formatByKey()` 实参位、被 `*Key` 的调用或字段
            接收）之外再加一类，认同一枚约定的另一半：**函数名**以 `Key` 结尾（settings 那批
            `privacyModeLabelKey` / `appLinkReasonKey` 纯函数）时，返回值按定义就是 key，
            由页面 `t()` 解析。于是「`…Key` 结尾 = 传 key」在视图层和数据层两侧都被机器兜住。
     射程外的一类如实记下：**跨行调用里的实参**。本脚本按**行**建模调用栈，`(` 换行了就不进栈，
     于是 `TextInput({`↵`  placeholder: '…'` 这一类新位置看不见。本包实跑撞到过一次
     （`CodePage` 的 `Enter ${…}-digit code`），当时靠人工接线补上；收口要改成整文件括号栈，
     记在后续包里，不在这儿冒充已覆盖。
  R6 `*Key` 载体必须双词典命中（I18N-LITERAL-104 引入）：R4/R5b 为了「传 key 不传串」开了豁免，
     豁免自己就成了洞 —— `new ShowToastEffect('Cache cleared')` 被 `messageKey` 接走之后，
     没有任何一条规则检查这个 key 真在词典里。SET-103 那次事故（`'Sticker set: %s'` 两本词典都
     没有，Toast 上屏就是 key 原文）正是这个形状，而它此后会一直藏在「看起来已经国际化了」的写法里。
     R6 只认**文案语义**的 key 载体：取载体名的词根（camelCase 尾段或 SCREAMING_SNAKE 尾段），
     落在 label / title / subtitle / message / text / placeholder / hint / reason / summary /
     name / description / desc / error / prompt / content / snippet / cancel / confirm / button /
     category / section 之内，才要求该字面量 EN 与 ZH 双命中。
     `accountKey` / `chatKey` / `setKey` / `fileKey` / `cacheKey` 这些载体收的本来就是标识符，
     按词典要求会全是误伤，所以不进射程。
  R7 `@Builder` 的按值文案参数不许收已解析串（I18N-HOTSWITCH-101 引入）：ArkUI 对 `@Builder`
     的**按值参数**只在宿主 build 时求值一次并拷贝，之后语言位变了它也不重算 —— 第五十四轮设备
     取证实测：同一屏里 `Text(this.t(key))` 的行翻成中文，`SectionTitle(this.t(key))` 的分节标题
     仍是英文。R4/R6 都只看字面量本身，看不出「这一句是传进来的、所以不会跟着语言变」。
     所以 R7 按形状拦：先收 `@Builder` 里**不收 `*Key`** 的 `string` 形参（按值文案位），
     再看调用点有没有 `this.t(...)` / `getString(...)` / `formatByKey(...)` 现取的串。
     正确形状 = 传 key、builder 体内 `this.t(key)`（`NotificationScopeRowKey` / `FieldLabelKey` /
     `PickerSectionHeaderViewKey` 三个先例），或干脆内联进 build。
     口径是行内的，跨行写的 `this.Some(` + 下一行的 `this.t(...)` 扫不到（同「守卫跨行调用收口」一包）。
  R8 日期形态只许出自一个文件（I18N-DATE-101 引入）：R1~R7 全都只管**文案**，日期形态是它们
     的盲区 —— `'Sep'`、`21.09.2026`、`2026年9月` 在任何语言里都「没翻译错」，坏的是**没跟着界面
     语言切换**。第五十七轮设备实测：英文界面的会话列表出 `21.09.2026`、共享内容分组头出 `2026年9月`。
     所以按形状拦，射程比前七条宽（core/feature/platform/entry 的 `src/main/ets`）：
       ① 中文排布 —— 插值后紧跟 `年/月/日/岁`（`${month}月${day}日`）；
       ② 点分数字日期 —— `${…}.${…}`（旧会话列表的 `dd.MM.yyyy` 正是这个形状）；
       ③ 英文月份名/星期名 —— 字面量命中 `MONTH_WEEKDAY_NAMES` 且**不是**词典 key
          （`'Sunday'` 作为 `SHARED_WEEKDAY_KEYS` 的 key 是对的，`'Sep'` 不是任何 key）；
       ④ 旧的 `// i18n-allow 日期形态` 就地豁免 —— 这一类豁免自本包起作废，标了就报；
       ⑤ 手取时间字段 —— 调用 `getHours()` / `getMinutes()`（I18N-DATE-102 补）。前四类只
          拦**字符串形状**，而 `HH:mm` 是 `${pad2(date.getHours())}` 拼出来的：落盘后长得和
          任何数字串一样，抓不到。时制的差异只在「取完字段之后怎么排版」，所以把取字段这一
          步本身就收紧 —— 只有形态表本体能读时钟，业务层一律交 `DateParts` 进去。
     唯一放行的是 `core/common/src/main/ets/DateFormat.ets`（形态表本体）与 `Lang.ets`（词典）。

用法：python3 tools/ci/check_i18n_literals.py [--quiet]
退出码：0 = 无违规；1 = 存在违规；2 = 前置条件坏了（词典解析不出来）
"""

import argparse
import collections
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

# R8：日期形态串的唯一合法出处（I18N-DATE-101 引入）。
DATE_FORM_SOURCE = 'core/common/src/main/ets/DateFormat.ets'
# 词典本身不算「拼日期的模板」：`'Sunday': '星期日'` 是词条，业务层按 key 取它是对的。
DATE_DICT_SOURCE = 'core/common/src/main/ets/Lang.ets'
# 月份名与星期名（英文两档）。中文侧靠 `}月`/`}年`/`}日` 的排布形状拦，不需要表。
MONTH_WEEKDAY_NAMES = frozenset((
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    'January', 'February', 'March', 'April', 'June', 'July', 'August', 'September',
    'October', 'November', 'December',
    'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat',
))
# 中文日期排布：插值后面直接跟 `年/月/日/岁` 就是在本地拼串。
CN_DATE_SHAPE_RE = re.compile(r'\$\{[^{}]*\}\s*[年月日岁]')
# 点分数字日期（旧会话列表的 `dd.MM.yyyy`）。
DOT_DATE_SHAPE_RE = re.compile(r'\$\{[^{}]*\}\.\\\$\{[^{}]*\}|\$\{[^{}]*\}\.\$\{[^{}]*\}')
# 「日期形态」这一类就地豁免已作废：改走 DateFormat，标了就报。
DATE_ALLOW_REASON_RE = re.compile(r'日期|时间形态|相对时间')
# R8⑤：手写时钟取值。`HH:mm` 这类形态是 `${pad2(d.getHours())}` 拼出来的，字符串形状抓不到，
# 于是把「读时钟字段」这一步本身收紧：只有形态表本体能取值，业务层交 `DateParts` 进去。
CLOCK_FIELD_RE = re.compile(r'\.get(Hours|Minutes)\s*\(\s*\)')

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
# R5b：数据层里直接上屏的出口（Toast）。
DATA_DISPLAY_SINKS = frozenset(('showToast', 'showHintToast'))
# R5b：`return` 的直接操作数所在行（三元、模板串都算这一行的 return 操作数）。
RETURN_RE = re.compile(r'return\b')
QUOTES = ('\'', '"', '`')

# 104 收紧后的三条规则共用的基础设施：字面量的语法位置（Hit）与构造器参数表索引。
Hit = collections.namedtuple('Hit', 'value callers field prefix start line')
# `new Foo(` 的被调名与 `new` 关键字；`\s*$` 允许 `Foo (`。
CALL_TAIL_RE = re.compile(r'(?:(?P<newkw>\bnew)\s+)?(?P<ident>[A-Za-z_$][\w$]*)\s*$')
# R5b③：赋值右侧。`=(?!=)` 排除 `==`/`===`，`=>` 因为前面有 `>` 也不匹配。
ASSIGN_RE = re.compile(r'^\s*(?:(?:export|declare)\s+)?(?:const|let|var)\s+'
                       r'([A-Za-z_$][\w$]*)\s*(?::[^=;]+?)?\s*=(?!=)')
PLAIN_ASSIGN_RE = re.compile(r'^\s*([A-Za-z_$][\w$.]*)\s*=(?!=)')
# R4'：`${…}` 插值段不算文案内容，判形状之前先剥掉。
# 允许一层嵌套：`${this.t('{0} GIFs', n)}` 里的 `{0}` 是 key 自带的花括号，
# 早先的 `[^{}]*` 在它面前停下，于是整段没被剥掉，模板串被当成文案命中 R4'。
PLACEHOLDER_RE = re.compile(r'\$\{(?:[^{}]|\{[^{}]*\})*\}')
# 冒号是类型注解而不是对象字段的两种形状（见 scan_line_literals 的 `:` 分支）。
DECL_BEFORE_RE = re.compile(r'\b(?:const|let|var)\s+$')
TYPE_AFTER_RE = re.compile(r'\s*[A-Za-z_$][\w$<>\[\].]*\s*[=,);]')
# R6：只有「文案语义」的 `*Key` 载体才要求双词典命中（词根见 key_carrier_stem）。
# 名单外的 `accountKey` / `chatKey` / `setKey` / `fileKey` 收的是标识符，按词典要求全是误伤。
KEY_CARRIER_STEMS = frozenset((
    'label', 'title', 'subtitle', 'message', 'text', 'placeholder', 'hint', 'reason',
    'summary', 'name', 'description', 'desc', 'error', 'prompt', 'content', 'snippet',
    'cancel', 'confirm', 'button', 'category', 'section',
))


def is_comment(stripped: str) -> bool:
    return stripped.startswith('//') or stripped.startswith('/*') or stripped.startswith('*')


def code_lines(path):
    """逐行产出参与扫描的代码行（跳过整行注释与块注释；各条规则用同一套口径）。"""
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
    return partitioned_files(True)


def data_files():
    """R5 的射程：同批模块里**不在** pages//components/ 下的 .ets（数据层与装配层）。"""
    return partitioned_files(False)


def partitioned_files(view: bool):
    out = []
    for d in VIEW_DIRS:
        base = ROOT / d
        if not base.is_dir():
            continue
        for path in sorted(base.rglob('*.ets')):
            rel = str(path.relative_to(ROOT))
            if any(part in SKIP_PARTS for part in rel):
                continue
            in_view = any(seg in rel for seg in VIEW_SEGMENTS)
            if in_view != view:
                continue
            out.append((rel, path))
    return out


def date_form_files():
    """R8 的射程：core/feature/platform/entry 各模块的 `src/main/ets`（比 R1~R7 多出 core 与 platform）。

    按模块目录取而不是从 `feature` 整棵树 rglob —— 后者会把 `feature/*/build/default/cache/`
    里的**上一版打包源码**一起扫进来，报出一堆改不掉的幽灵违规。
    """
    dirs = [ROOT / 'entry' / 'src' / 'main' / 'ets']
    for top in ('core', 'feature', 'platform'):
        dirs.extend(sorted(ROOT.glob(f'{top}/*/src/main/ets')))
    out = []
    for base in dirs:
        if not base.is_dir():
            continue
        for path in sorted(base.rglob('*.ets')):
            rel = str(path.relative_to(ROOT))
            if any(part in rel for part in SKIP_PARTS):
                continue
            out.append((rel, path))
    return out


def scan_date_forms(files, dicts):
    """R8：月份名/星期名与日期排布只许出现在 `DateFormat.ets`。

    这一条存在的意义：日期形态不是文案，`Lang` 词典管不住它 —— 一个 `'Sep'` 在两种语言
    里都「翻译正确」，出错的是**没有跟着界面语言切换**。旧的两套并存正是这么漏过 R1~R7 的
    （英文界面的会话列表出 `21.09.2026`，中文形态的分组头出 `2026年9月`）。
    所以口径按形状而不是按语言：中文排布（`${…}年/月/日/岁`）、点分数字日期（`${…}.${…}`）、
    以及英文月份/星期名表，全部只许在那一个文件里。词典里的 `'Sunday': '星期日'` 是词条，
    业务层按 key 取它是对的，所以 `Lang.ets` 与「双词典都命中的 key」不进射程。
    ⑤ 是同一射程上的第二道：`d.getHours()` 拼出的 `HH:mm` 没有可识别的字符串形状，只能把
    「读时钟字段」这一步本身锁到形态表里 —— 业务层拿到的是 `DateParts`，档位由调用方传入。
    """
    problems = []
    for rel, path in files:
        if rel in (DATE_FORM_SOURCE, DATE_DICT_SOURCE):
            continue
        for idx, line, stripped in code_lines(path):
            allow = ALLOW_RE.search(line)
            if allow is not None and DATE_ALLOW_REASON_RE.search(allow.group('reason')):
                problems.append(f'{rel}:{idx + 1}: `i18n-allow 日期形态` 这一类豁免已随 '
                                f'I18N-DATE-101 作废（形态串的唯一出处是 {DATE_FORM_SOURCE}）')
            shape = CN_DATE_SHAPE_RE.search(line)
            if shape is not None:
                problems.append(f'{rel}:{idx + 1}: 就地拼中文日期排布 {shape.group(0)!r} —— '
                                f'语言驱动的形态表只在 {DATE_FORM_SOURCE}，此处应改调它')
            dot = DOT_DATE_SHAPE_RE.search(line)
            if dot is not None:
                problems.append(f'{rel}:{idx + 1}: 就地拼点分数字日期 {dot.group(0)!r} —— '
                                f'旧会话列表的 `dd.MM` 正是这个形状，改调 DateFormat')
            clock = CLOCK_FIELD_RE.search(line)
            if clock is not None:
                problems.append(f'{rel}:{idx + 1}: 就地读时钟字段 {clock.group(0).lstrip(".")!r} —— '
                                f'12/24 小时的档位只在 {DATE_FORM_SOURCE} 生效，'
                                f'改调 formatTimeOfDay(datePartsFrom(ms), lang, clock)')
            for lit in LITERAL_RE.finditer(line):
                value = lit.group(2)
                if value in MONTH_WEEKDAY_NAMES and value not in dicts['EN']:
                    problems.append(f'{rel}:{idx + 1}: 月份/星期名 {value!r} 出现在 '
                                    f'{DATE_FORM_SOURCE} 之外（它是 locale 数据不是文案，'
                                    f'加进词典只会多出一批只为拼日期而存在的 key）')
    return problems


def scan_literals(files, layer: str):
    """R1 / R5a：文件里的汉字字面量（`// i18n-allow 原因` 可豁免）。"""
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
                                    f'（本仓合法豁免只有本族名与源语言标签两类，日期形态归 R8）')
                else:
                    allowed.append(f'{rel}:{idx + 1}')
                continue
            problems.append(f'{rel}:{idx + 1}: {layer}写死中文文案 -> {hit}（改走 Lang key，'
                            f'确需保留请标 // i18n-allow <原因>）')
    return problems, allowed


def scan_line_literals(line):
    """把一行拆成「字面量 + 它在语法上的位置」，供 R4/R5b/R6 判定槽位。

    只做粗粒度语法位置判定，不是解析器。每个尚未闭合的调用/容器是一个栈帧
    `(被调名, 是否成员调用, 是否 new 构造, 该层已走过的实参序号)`：
      被调名 —— `(` 前的标识符段。103 之前这里是**逐字符回扫到非标识符**，于是
                 `new DrawerMenuRow(` 认出的名字是空的（停在 `new` 后面那个空格），
                 构造器实参整类位置看不见；现在交给 CALL_TAIL_RE，顺带标出 `new`；
      成员   —— 名字左边紧跟 `.`（`this.Builder(` / `obj.method(`），用来认 `@Builder`；
      序号   —— 同层逗号推进，把构造器实参对回参数名（R5b④ 与 R6 都要用）。
    字面量另带 `prefix`（它左边那半行）与 `start`（偏移），赋值位置（R5b③）要判断
    它是不是落在 `=` 的右边。
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
            out.append(Hit(''.join(buf), tuple(tuple(fr) for fr in stack),
                           field, line[:i], i, line))
            i = j + 1
            field = None
            continue
        if ch in '([{':
            name = None
            member = False
            ctor = False
            if ch == '(':
                m = CALL_TAIL_RE.search(line[:i])
                if m is not None:
                    name = m.group('ident')
                    ctor = m.group('newkw') is not None
                    member = line[:m.start('ident')].rstrip().endswith('.')
            stack.append([name, member, ctor, 0])
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
            ident = line[k + 1:i]
            # `const nameKey: string = …` 与 `(labelKey: string, …)` 的冒号是**类型注解**，
            # 不是对象字段。不认这一层，R6 会把日志片段 `',name=${setName}'` 当成 nameKey
            # 收到的词典 key（ChatCoordinator 的贴纸取数日志就是这么冒出来的误报）。
            annotation = ident != '' and (
                DECL_BEFORE_RE.search(line[:k + 1]) is not None
                or TYPE_AFTER_RE.match(line[i + 1:]) is not None)
            field = None if annotation else (ident or None)
            i += 1
            continue
        if ch == ',':
            if stack:
                stack[-1][3] += 1
            field = None
        i += 1
    return out


FUNCTION_RE = re.compile(r'\bfunction\s+([A-Za-z_$][\w$]*)\s*\(')
CLASS_HEAD_RE = re.compile(r'(?m)^[ \t]*(?:export[ \t]+)?(?:default[ \t]+)?'
                           r'class[ \t]+([A-Za-z_$][\w$]*)')
CTOR_HEAD_RE = re.compile(r'(?m)^[ \t]*(?:(?:public|private|protected|readonly)[ \t]+)?'
                          r'constructor[ \t]*\(([^)]*)\)')
# 索引范围比射程宽：构造器常常定义在同模块的 contract/model 里，而 `new` 发生在 coordinator。
INDEX_GLOBS = ('entry/src/main/ets/**/*.ets', 'feature/*/src/main/ets/**/*.ets',
               'core/*/src/main/ets/**/*.ets', 'platform/*/src/main/ets/**/*.ets')


def split_params(raw: str) -> tuple:
    """构造器参数表拆成参数名；`readonly labelKey: string` 这类只取 `labelKey`。

    只按 `([{` 计深度（不认尖括号：ArkTS 的泛型实参里带逗号的分隔类型极少，
    而 `=>` 里的 `>` 会先把深度算坏）。解构参数（`{ a, b }`）取不到名字，留空位。
    """
    parts = []
    depth = 0
    cur = ''
    for ch in raw:
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        if ch == ',' and depth == 0:
            parts.append(cur)
            cur = ''
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    names = []
    for part in parts:
        token = part.strip()
        while token and not (token[0].isalpha() or token[0] in '_$'):
            token = token[1:]
        head = token.split(':')[0].split('=')[0].split('?')[0].strip()
        head = head.split(',')[0].strip()
        names.append(head if re.fullmatch(r'[A-Za-z_$][\w$]*', head) else '')
    return tuple(names)


def build_ctor_index():
    """全仓 `src/main/ets` 的 `class -> constructor 参数名` 表（R5b④ 与 R6 按参数名放行）。"""
    index = {}
    for pattern in INDEX_GLOBS:
        for path in sorted(ROOT.glob(pattern)):
            rel = str(path.relative_to(ROOT))
            if any(part in rel for part in SKIP_PARTS):
                continue
            try:
                text = path.read_text(encoding='utf-8')
            except OSError:
                continue
            heads = [(m.start(), m.group(1)) for m in CLASS_HEAD_RE.finditer(text)]
            if not heads:
                continue
            for m in CTOR_HEAD_RE.finditer(text):
                cls = None
                for pos, name in heads:
                    if pos < m.start():
                        cls = name
                    else:
                        break
                if cls is None or cls in index:
                    continue
                index[cls] = split_params(m.group(1))
    return index


def ctor_param_at(callers, ctor_index):
    """字面量所在的最内层 `new Foo(` 对应的参数名；类或位置查不到回 None。"""
    if not callers:
        return None
    name, _member, is_ctor, arg_index = callers[-1]
    if not is_ctor or name is None:
        return None
    params = ctor_index.get(name)
    if params is None or arg_index >= len(params):
        return None
    return params[arg_index] or None


def key_carrier_stem(name: str) -> str:
    """`toastMessageKey` -> `message`、`PROXY_LABEL_KEY` -> `label`：取载体名的词根。"""
    base = name[:-len(KEY_CARRIER_SUFFIX)]
    if base.endswith('_'):
        return base[:-1].split('_')[-1].lower()
    if not base:
        return ''
    m = re.search(r'[A-Z][A-Za-z0-9]*$', base)
    return (m.group(0) if m is not None else base).lower()


def assign_lhs(line: str, start: int):
    """R5b③：这一行若是赋值且字面量落在 `=` 右边，回左侧名字。"""
    m = ASSIGN_RE.match(line) or PLAIN_ASSIGN_RE.match(line)
    if m is None or m.end() > start:
        return None
    return m.group(1)


def key_carrier_exemption(callers, field, ctor_index) -> bool:
    """R4/R5b 共用的免标记豁免：查词典的实参位，或被 key 载体（调用/字段/构造参数）接走。"""
    names = [c[0] for c in callers if c[0]]
    # 豁免 ①：t()/getString()/formatByKey() 的实参 —— 这就是在查词典，正是要的形状。
    if any(name in KEY_CALL_NAMES for name in names):
        return True
    # 豁免 ②：`*Key` 约定的调用/字段/构造参数 —— 它收的是 key，不是串。
    if any(name.endswith(KEY_CARRIER_SUFFIX) for name in names):
        return True
    if field is not None and field.endswith(KEY_CARRIER_SUFFIX):
        return True
    param = ctor_param_at(callers, ctor_index)
    return param is not None and param.lower().endswith('key')


def display_slot_reason(hit, stripped_line, fn, dicts, ctor_index):
    """R4/R4'：字面量所处文案槽位的写法；不属于文案槽位则回 None（本规则不管它）。"""
    callers, field = hit.callers, hit.field
    if key_carrier_exemption(callers, field, ctor_index):
        return None
    for name, member, _ctor, _idx in callers:
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


def data_slot_reason(hit, stripped_line, fn, dicts, ctor_index):
    """R5b：数据层里字面量的「上屏位置」写法；不在射程内回 None。

    四个位置：① `return` 的直接操作数；② 显示出口 `showToast(`/`showHintToast(` 的实参；
    ③（104）赋值右侧；④（104）构造器实参。①③ 都要求字面量外层没有任何调用，
    `return new Row('Proxy error', …)` 那种属④，不冒充命中①。
    ④ 需要参数名才能判「这个位置收的是不是 key」：**参数表查不到就不报**（构造器定义在
    索引范围外的模块时如此），宁可留射程外也不误伤。
    除 R4 的两类豁免外再加一类，沿用同一套「传 key 不传串」约定的另一半：**函数名**以 `Key`
    结尾时（settings 那一整批 `privacyModeLabelKey` 纯函数）返回值按定义就是 key。
    """
    if key_carrier_exemption(hit.callers, hit.field, ctor_index):
        return None
    for name, _member, _ctor, _idx in hit.callers:
        if name in DATA_DISPLAY_SINKS:
            return f'{name}('
    if hit.callers:
        name, _member, is_ctor, _idx = hit.callers[-1]
        if is_ctor and name is not None and ctor_param_at(hit.callers, ctor_index) is not None:
            return f'new {name}( 的 {ctor_param_at(hit.callers, ctor_index)}'
        return None
    if stripped_line.startswith('return ') or stripped_line.startswith('return('):
        if fn is not None and fn.endswith(KEY_CARRIER_SUFFIX):
            return None
        return 'return'
    lhs = assign_lhs(hit.line, hit.start)
    if lhs is not None and not lhs.lower().endswith('key'):
        return f'{lhs} ='
    return None


def code_lines_with_fn(path):
    """逐行产出代码行，并带上「最近见过的函数名」，供 R5b 认 `*Key` 约定。

    只做行内正则推进，不是作用域分析：本仓 model/coordinator 的函数都是 `export function xxx(` 平铺，
    嵌套函数会沿用外层名，误豁免需要函数名正好以 Key 结尾，方向上安全。
    """
    fn = None
    for idx, line, stripped in code_lines(path):
        m = FUNCTION_RE.search(line)
        if m is not None:
            fn = m.group(1)
        yield idx, line, stripped, fn


def looks_like_copy(value: str, known) -> bool:
    """R4'（104 收紧）的形状判据：含空格、或首字母大写、或命中词典 —— 三者任一成立就算文案。

    为什么不「禁一切英文字面量」：英文单词同时是技术 token（`'zh'`、`'mtproto'`、
    `'app.media.ic_help'`），而 token 在本仓的写法特征很稳定 —— 小写、不带空格、不在词典里。
    `${…}` 插值段先剥掉再判，于是 `@${username}`、`${n} ms` 不误伤；剥完不足两字符
    （头像兜底的 `'A'`）也不算文案。
    """
    if CJK_RE.search(value):
        return False
    bare = PLACEHOLDER_RE.sub('', value)
    if len(bare) < 2 or not re.search(r'[A-Za-z]', bare):
        return False
    return bare[0].isupper() or ' ' in bare.strip() or value in known


def scan_slots(files, dicts, ctor_index, reason_for, wants, fix_hint):
    """R4/R4' 与 R5b 的公共骨架：符合 `wants` 的字面量出现在「文案位置」即违规。"""
    problems = []
    allowed = []
    known = dicts['EN'] | dicts['ZH']
    for rel, path in files:
        for idx, line, stripped, fn in code_lines_with_fn(path):
            for hit in scan_line_literals(line):
                if not hit.value or not wants(hit.value, known):
                    continue
                reason = reason_for(hit, stripped, fn, dicts, ctor_index)
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
                problems.append(f'{rel}:{idx + 1}: 文案位置 {reason} 里写死了 '
                                f'{hit.value}（{fix_hint}，确需保留请标 // i18n-allow <原因>）')
    return problems, allowed


def scan_display_slots(files, dicts, ctor_index):
    """R4'：看着像文案的英文字面量不许直接写进视图层文案槽位（`// i18n-allow 原因` 可豁免）。"""
    return scan_slots(
        files, dicts, ctor_index,
        display_slot_reason,
        lambda value, known: looks_like_copy(value, known),
        '改走 this.t(...) 或把参数改名成 *Key')


def scan_data_layer(files, dicts, ctor_index):
    """R5b：数据层里 return / Toast 实参 / 赋值右侧 / 构造器实参不许写死词典已知的英文。"""
    return scan_slots(
        files, dicts, ctor_index,
        data_slot_reason,
        lambda value, known: value in known,
        '改走 Lang.getInstance().getString(...) 或把参数改名成 *Key')


def r6_carrier_name(callers, field, ctor_index):
    """R6 的载体名：构造参数 / 字段 / 被调名里第一个「带文案词根」的 `*Key`；没有回 None。"""
    candidates = [ctor_param_at(callers, ctor_index), field]
    candidates += [c[0] for c in callers if c[0]]
    for name in candidates:
        if name is None or not name.endswith(KEY_CARRIER_SUFFIX):
            continue
        if key_carrier_stem(name) in KEY_CARRIER_STEMS:
            return name
    return None


def scan_key_carriers(files, dicts, ctor_index):
    """R6：被「文案语义的 `*Key`」接走的字面量必须双词典命中。

    R4/R5b 给「传 key 不传串」开了豁免，豁免本身就是洞：key 拼错或缺项时 `Lang` 原样回吐，
    屏幕上就是一串标识（SET-103 的 `'Sticker set: %s'` 事故）。R2 只盯 `t()` 的实参，
    管不到这些还没接进 `t()` 的载体，所以在这里补一道。
    """
    problems = []
    checked = set()
    for rel, path in files:
        for idx, line, stripped in code_lines(path):
            if ALLOW_RE.search(line):
                continue
            for hit in scan_line_literals(line):
                carrier = r6_carrier_name(hit.callers, hit.field, ctor_index)
                if carrier is None or not hit.value or CJK_RE.search(hit.value):
                    continue
                checked.add(hit.value)
                missing = [n for n in ('EN', 'ZH') if hit.value not in dicts[n]]
                if missing:
                    problems.append(f'{rel}:{idx + 1}: {carrier} 收到的 {hit.value!r} '
                                    f'缺 {" 与 ".join(missing)} 词条'
                                    f'（key 载体收的必须是词典里成在的 key）')
    return problems, checked


# R7：`@Builder` 的按值文案参数。
BUILDER_DEF_RE = re.compile(r'^\s*(?:@Builder\s+)?([A-Za-z_$][\w$]*)\s*\(([^)]*)\)\s*\{?\s*$')
BUILDER_CALL_RE = re.compile(r'this\.([A-Za-z_$][\w$]*)\s*\(([^;]*?)\)\s*;?\s*$')
# 已解析串的三种写法：视图层 t()、Lang.getString()、Lang.formatByKey()。
RESOLVED_CALL_RE = re.compile(r'(?:\bthis\.|\bLang\.getInstance\(\)|\blang\.)?\b(?:t|getString|formatByKey)\s*\(')
KEY_PARAM_RE = re.compile(r'(\w+Key)\s*:\s*string')
PLAIN_STRING_PARAM_RE = re.compile(r'(\w+)\s*:\s*string\b')


def scan_builder_copy_params(files):
    """R7：不许把已解析串（`this.t(...)` / `getString(...)`）传进 `@Builder` 的文案参数位。

    ArkUI 对 `@Builder` 的**按值参数**只在宿主 build 时求值一次并拷贝，语言位变了它也不重算 ——
    第五十四轮设备取证实测：同一屏里 `Text(this.t(key))` 的行翻成中文，`SectionTitle(this.t(key))`
    的分节标题仍是英文。唯一稳的写法是「传 key，builder 体内自己 `this.t(key)`」
    （`NotificationScopeRowKey` / `FieldLabelKey` / `PickerSectionHeaderViewKey` 就是这个先例）。

    射程：只认 `@Builder` 方法里**不收 `*Key`** 的 `string` 形参（labelKey/valueKey 那类是
    正确形状，`value: string` 这类收的是数据值，本规则只看调用点有没有现取现传）。
    """
    problems = []
    for rel, path in files:
        lines = path.read_text(encoding='utf-8').splitlines()
        # builder 名 -> 它的按值文案参数名（没有按值文案参数则不入表）
        copy_params = {}
        for i, line in enumerate(lines):
            if line.strip() != '@Builder':
                continue
            for j in range(i + 1, min(i + 4, len(lines))):
                m = BUILDER_DEF_RE.match(lines[j])
                if m is None:
                    continue
                name, raw = m.group(1), m.group(2)
                # 去掉 *Key 形参后剩下的 string 形参才是按值文案位
                left = KEY_PARAM_RE.sub('', raw)
                plain = [n for n in PLAIN_STRING_PARAM_RE.findall(left)]
                if plain:
                    copy_params[name] = plain
                break
        if not copy_params:
            continue
        for idx, line, stripped in code_lines(path):
            if ALLOW_RE.search(line):
                continue
            m = BUILDER_CALL_RE.search(stripped)
            if m is None or m.group(1) not in copy_params:
                continue
            args = m.group(2)
            if not RESOLVED_CALL_RE.search(args):
                continue
            problems.append(
                f'{rel}:{idx + 1}: this.{m.group(1)}({args[:60]}) 的按值参数 '
                f'{" / ".join(copy_params[m.group(1)])} 收到了现取的已解析串 —— @Builder 按值参数'
                f'只求值一次，应用内换语言不会重算；改成传 key（形参改名 *Key，builder 体内 '
                f'this.t(key)），或直接内联进 build')
    return problems


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
    data = data_files()
    date_files = date_form_files()
    dicts = load_dicts()
    ctor_index = build_ctor_index()

    literal_problems, allowed_literal = scan_literals(files, '视图层')
    slot_problems, allowed_slot = scan_display_slots(files, dicts, ctor_index)
    data_literal_problems, allowed_data_literal = scan_literals(data, '数据层')
    data_slot_problems, allowed_data_slot = scan_data_layer(data, dicts, ctor_index)
    # R2 覆盖两层：coordinator/model 里的 getString('X') 同样必须双词典命中。
    key_problems, checked = scan_keys(files + data, dicts)
    # R6：R4/R5b 的「传 key 不传串」豁免本身就是洞，收进去的 key 必须成在。
    carrier_problems, carrier_checked = scan_key_carriers(files + data, dicts, ctor_index)
    # R7：@Builder 按值文案参数只求值一次，收已解析串就是换语言不刷新的洞。
    builder_problems = scan_builder_copy_params(files)
    parity_problems = scan_parity(dicts)
    # R8：日期形态不是文案，词典四条规则都管不住 —— 单独收在一个白名单文件里。
    date_form_problems = scan_date_forms(date_files, dicts)

    allowed = allowed_literal + allowed_slot + allowed_data_literal + allowed_data_slot
    failed = bool(literal_problems or slot_problems or data_literal_problems
                  or data_slot_problems or key_problems or carrier_problems
                  or builder_problems or parity_problems or date_form_problems)
    if not args.quiet or failed:
        for msg in literal_problems:
            print(f'[i18n] LITERAL {msg}')
        for msg in slot_problems:
            print(f'[i18n] ENGLISH-SLOT {msg}')
        for msg in data_literal_problems:
            print(f'[i18n] DATA-LITERAL {msg}')
        for msg in data_slot_problems:
            print(f'[i18n] DATA-ENGLISH {msg}')
        for msg in key_problems:
            print(f'[i18n] MISSING-KEY {msg}')
        for msg in carrier_problems:
            print(f'[i18n] KEY-CARRIER {msg}')
        for msg in builder_problems:
            print(f'[i18n] BUILDER-VALUE {msg}')
        for msg in parity_problems:
            print(f'[i18n] PARITY {msg}')
        for msg in date_form_problems:
            print(f'[i18n] DATE-FORM {msg}')
        if not args.quiet:
            print(f'[i18n] 视图层文件 {len(files)} 个 / 数据层文件 {len(data)} 个，'
                  f'日期形态射程 {len(date_files)} 个文件，'
                  f'字面量 key 调用点覆盖 {len(checked)} 个，'
                  f'key 载体字面量覆盖 {len(carrier_checked)} 个，'
                  f'词典 EN {len(dicts["EN"])} / ZH {len(dicts["ZH"])} 条，'
                  f'就地豁免 {len(allowed)} 处'
                  f'（写死中文 {len(allowed_literal) + len(allowed_data_literal)} / '
                  f'写死英文 {len(allowed_slot) + len(allowed_data_slot)}）')
    if failed:
        print(f'[i18n] FAILED: 写死中文 {len(literal_problems) + len(data_literal_problems)} / '
              f'写死英文 {len(slot_problems) + len(data_slot_problems)} / '
              f'缺词条 {len(key_problems)} / key 载体缺项 {len(carrier_problems)} / '
              f'builder 按值传串 {len(builder_problems)} / '
              f'日期形态出格 {len(date_form_problems)} / '
              f'词典不对称 {len(parity_problems)}', file=sys.stderr)
        return 1
    print('[i18n] OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
