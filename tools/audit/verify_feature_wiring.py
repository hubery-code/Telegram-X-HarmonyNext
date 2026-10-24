"""确证脚本：对每个「已 Accepted」能力，检查它是否**真正接通**（不是只有模型/枚举）。

三级判据（由强到弱）：
  L3 已接通：存在 `scope.request('xxx'` / `encodeXxx(` 的**发送点**，且存在 UI 消费点
  L2 半接通：只有 encode 或只有 UI
  L1 仅模型：只有 DTO/模型/枚举，没有任何请求发送或 UI

用法：python tools/audit/verify_feature_wiring.py
"""
import io
import glob
import os
import re
import sys

ROOTS = []
for pat in ('feature/*/src/main/ets/**/*.ets',
            'core/*/src/main/ets/**/*.ets',
            'platform/*/src/main/ets/**/*.ets',
            'entry/src/main/ets/**/*.ets'):
    for p in glob.glob(pat, recursive=True):
        norm = p.replace('\\', '/')
        if 'td_api_generated' in norm:
            continue
        ROOTS.append(p)


def load_all():
    texts = {}
    for p in ROOTS:
        try:
            texts[p.replace('\\', '/')] = io.open(p, encoding='utf-8', errors='ignore').read()
        except OSError:
            pass
    return texts


# 每项：tdlib 请求名（用来找发送点）、UI 侧关键字
FEATURES = {
    # --- 消息发送族 ---
    'send text':        ('sendMessage', ['SendText', 'sendText', 'OnSendText']),
    'send photo':       ('sendMessage', ['sendPhoto', 'inputMessagePhoto']),
    'send video':       ('sendMessage', ['sendVideo', 'inputMessageVideo']),
    'send document':    ('sendMessage', ['sendDocument', 'inputMessageDocument']),
    'send voice':       ('sendMessage', ['sendVoice', 'inputMessageVoiceNote']),
    'send video note':  ('sendMessage', ['inputMessageVideoNote', 'VideoNoteBubble']),
    'send contact':     ('sendMessage', ['inputMessageContact', 'ContactBubble']),
    'send location':    ('sendMessage', ['inputMessageLocation', 'LocationBubble']),
    'send poll':        ('sendMessage', ['sendPollMessage', 'PollBubble']),
    'send sticker':     ('sendMessage', ['inputMessageSticker', 'StickerBubble']),
    'send animation':   ('sendMessage', ['inputMessageAnimation', 'AnimationBubble']),

    # --- 消息操作族 ---
    'edit message':     ('editMessageText', ['EditMessageText', 'EditMessage']),
    'delete message':   ('deleteMessages', ['DeleteMessages', 'DeleteMessage']),
    'forward':          ('forwardMessages', ['ForwardMessages', 'ForwardSelection']),
    'reply':            ('sendMessage', ['replyTo', 'ReplyTo']),
    # 本仓用的是 TDLib 较新的 addMessageReaction / removeMessageReaction（不是旧的
    # sendMessageReaction），首版判据写成旧名，把这条整链路误报成 ui-only。
    'reaction':         ('addMessageReaction', ['AddMessageReaction', 'ReactionChip']),
    'poll answer':      ('setPollAnswer', ['SetPollAnswer', 'setPollAnswer']),

    # --- 会话族 ---
    'open chat':        ('openChat', ['OpenChat', 'openChat']),
    'chat history':     ('getChatHistory', ['GetChatHistory', 'getChatHistory']),
    'view messages':    ('viewMessages', ['ViewMessages', 'viewMessages']),
    'pin message':      ('pinChatMessage', ['PinChatMessage', 'pinChatMessage']),
    'chat folders':     ('getChatFolders', ['GetChatFolders', 'getChatFolders']),

    # --- 设置与账号族 ---
    'notification settings': ('setChatNotificationSettings', ['SetChatNotificationSettings']),
    'block user':       ('setMessageSenderBlockList', ['SetMessageSenderBlockList']),
    'secret chat':      ('createNewSecretChat', ['CreateNewSecretChat']),
    'logout':           ('logOut', ['LogOut', 'logOut']),
    # 本仓的「清理缓存」走 TDLib 的 optimizeStorage（按文件类型+大小上限清理），
    # 不是 clearCache（后者只有 bot 可用）。首版判据写 clearCache，把它误报成 ui-only。
    'clear cache':      ('optimizeStorage', ['OptimizeStorage', 'optimizeStorage']),
    'storage stats':    ('getStorageStatistics', ['GetStorageStatistics']),

    # --- 媒体族 ---
    'download file':    ('downloadFile', ['DownloadFile', 'downloadFile']),
    'cancel file':      ('cancelDownloadFile', ['CancelDownload', 'cancelDownload']),
}

# 「本地替代实现」：本仓刻意不用 TDLib 的某个请求，而是自己实现等价能力。
# 这类**不是缺口**，但如果不标出来，机械判据会把它们报成 MODEL-ONLY，
# 于是下一轮又会去「补」一个本来就不该存在的东西。
LOCAL_SUBSTITUTES = {
    'chat folders': '本仓用本地硬编码的 5 个分类 Tab（ChatListPage 的 ChatFolderTab），'
                    '刻意不接 TDLib 的 getChatFolders —— 这是产品口径，不是缺口',
    'upload file':  '本仓上传走 sendMessage + inputMessagePhoto/Video/Document'
                    '（TDLib 语义是「本地路径 → 内部自动上传」），不单独调 uploadFile',
}


def find_request_sites(texts, request_name):
    """找 `scope.request('xxx'` 或 `request("xxx"` 的发送点。"""
    pat = re.compile(r"""request\s*\(\s*['"]""" + re.escape(request_name) + r"""['"]""")
    return [p for p, t in texts.items() if pat.search(t)]


def find_ui_sites(texts, keys):
    """UI 消费点：页面/组件/模型/协调器里出现了这个能力的关键字。

    为什么把 coordinator 也算进来：本仓的 MVI 里，是 coordinator 把 Effect 翻译成
    UI 可读的 UiState，很多能力的「消费」就在这里（例如 `reactionChips` 由
    ChatCoordinator 组装、ChatPage 只渲染）。只扫 pages/components 会漏成
    「req-only」的假象 —— 首版就因此把 send photo / video / document / voice
    全判成 L2，而它们其实在 ChatPage 里有完整的 `MediaBubble` / `AudioBubble`。
    """
    hits = []
    for p, t in texts.items():
        if any(seg in p for seg in ('/pages/', '/components/', '/model/', '/coordinator/')):
            if any(k in t for k in keys):
                hits.append(p)
    return hits


def main():
    texts = load_all()
    print('scanned (non-generated):', len(texts))
    print()
    print('%-26s %-6s %-6s %s' % ('feature', 'req', 'ui', 'verdict'))
    print('-' * 78)
    weak = []
    for name in FEATURES:
        req_name, ui_keys = FEATURES[name]
        req_sites = find_request_sites(texts, req_name)
        ui_sites = find_ui_sites(texts, ui_keys)
        if req_sites and ui_sites:
            verdict = 'L3 WIRED'
        elif req_sites:
            verdict = 'L2 req-only'
        elif ui_sites:
            verdict = 'L2 ui-only'
        elif name in LOCAL_SUBSTITUTES:
            # 本仓刻意不接这个请求，用本地实现替代 —— 不是缺口。
            verdict = 'N/A local-substitute'
        else:
            verdict = 'L1 MODEL-ONLY'
            weak.append(name)
        print('%-26s %-6d %-6d %s' % (name, len(req_sites), len(ui_sites), verdict))
    print()
    if weak:
        print('仅模型层、未见请求发送也未见 UI 消费（真实缺口候选）：')
        for w in weak:
            print('  -', w)
    else:
        print('没有 MODEL-ONLY 项：每个登记的能力都有发送点或 UI 消费点。')
    print()
    if LOCAL_SUBSTITUTES:
        print('本地替代实现（不是缺口，别再当缺口去补）：')
        for k, why in LOCAL_SUBSTITUTES.items():
            print(f'  - {k}: {why}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
