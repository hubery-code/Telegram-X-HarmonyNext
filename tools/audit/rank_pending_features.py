"""按 TDLib DTO 体量 + 现有脚手架，给「未实现功能」做难度排序。

判据两条：
  1. 相关 DTO 数量（生成代码里名字命中数）—— 代表协议面有多宽；
  2. 本仓现有的脚手架（模型/意图/页面/端口）—— 代表已经走了多远。

只数 DTO 不够：DTO 多不等于活多（可能只需几个），但 DTO 数以百计
说明它是一整个子系统，而「小项」不该是子系统。
"""
import glob
import io
import re

GEN = glob.glob('core/td_api_generated/src/main/ets/**/*.ets', recursive=True)

FEATURES = {
    'Gifts (礼物)':       r'\w*Gift\w*',
    'Stories':            r'\w*Stor(y|ies)\w*',
    'Forum (论坛话题)':    r'\w*(Forum|Topic)\w*',
    'InstantView':        r'\w*InstantView\w*',
    'WebApp (网页应用)':   r'\w*WebApp\w*',
    'VideoEdit (视频编辑)': r'\w*(VideoEdit|VideoProcess)\w*',
    'Calls (VoIP)':       r'\w*(Call|Voip)\w*',
    'Location (地图)':     r'\w*(Location|Venue|Map)\w*',
}


def count_dtos(pattern):
    rx = re.compile(r'export class (' + pattern + r')')
    names = set()
    for p in GEN:
        try:
            t = io.open(p, encoding='utf-8', errors='ignore').read()
        except OSError:
            continue
        for m in rx.finditer(t):
            names.add(m.group(1))
    return names


def scaffold_hits(keys):
    """本仓非生成代码里，这个能力有多少处实现痕迹。"""
    n = 0
    for pat in ('feature/*/src/main/ets/**/*.ets', 'core/*/src/main/ets/**/*.ets',
                'platform/*/src/main/ets/**/*.ets', 'entry/src/main/ets/**/*.ets'):
        for p in glob.glob(pat, recursive=True):
            norm = p.replace('\\', '/')
            if 'td_api_generated' in norm:
                continue
            try:
                t = io.open(p, encoding='utf-8', errors='ignore').read()
            except OSError:
                continue
            for k in keys:
                if k in t:
                    n += 1
                    break
    return n


PLAN = [
    ('Stories', ['StoryPage', "'getStories'", "'sendStory'"]),
    ('Gifts (礼物)', ['GiftPage', "'sendGift'", "'getAvailableGifts'"]),
    ('Forum (论坛话题)', ['ForumTopic', "'getForumTopics'"]),
    ('InstantView', ['InstantViewPage', "'getWebPageInstantView'"]),
    ('WebApp (网页应用)', ['WebAppPage', "'openWebApp'"]),
    ('VideoEdit (视频编辑)', ['VideoEdit', "'editVideo'"]),
    ('Calls (VoIP)', ['CallPage', "'setCall'"]),
    ('Location (地图)', ['MapView', "'getLocation'"]),
]

print('%-22s %-8s %-10s' % ('feature', 'DTOs', 'scaffold'))
print('-' * 44)
rows = []
for name, keys in PLAN:
    dtos = count_dtos(FEATURES[name])
    sc = scaffold_hits(keys)
    rows.append((len(dtos), name, sc))
    print('%-22s %-8d %-10d' % (name, len(dtos), sc))

print()
print('按 DTO 体量从少到多（= 协议面从窄到宽）：')
for dtos, name, sc in sorted(rows):
    print('  %-22s DTO=%-4d 现有脚手架=%d' % (name, dtos, sc))
