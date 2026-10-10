/**
 * feature/profile — 共享内容分区（PROFILE-103 UI，CHATPROF-SHARED 抽为组件，SHARED-AUDIO 扩音乐/语音）。
 *
 * 用户资料页与群/频道资料页共用同一片「媒体 / 文件 / 链接 / 音乐 / 语音（+ 共同群组）」
 * 网格与列表：两处各写一份的话，空态文案、缩略图占位、加载更多这三处一定会开始分叉。
 * 组件只吃一份 SharedContentViewData + 四个回调，不读任何页面的 UiState。
 *
 * 群组 Tab 是私聊资料页专属（数据来自 getGroupsInCommon）；群/频道资料页传
 * showGroupsTab: false，Tab 栏只剩五项。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { Lang, SupportedLanguage } from '@tgx/core-common';
import { getAvatarColorIndex } from '@tgx/core-domain';
import { fileUri } from '@kit.CoreFileKit';
import { SharedAudioItem, SharedFileItem, SharedGroupItem, SharedLinkItem, SharedMediaItem } from '../contract/SharedContentItems';
import { avatarColorOf, avatarLetterOf, SharedDateSpan, splitSharedDateSpans } from '../model/SharedContentFormat';
import {
  SHARED_TAB_AUDIO,
  SHARED_TAB_FILES,
  SHARED_TAB_GROUPS,
  SHARED_TAB_LINKS,
  SHARED_TAB_MEDIA,
  SHARED_TAB_VOICE
} from '../model/SharedContentSearch';

/** 本地沙箱绝对路径 → 可渲染 uri（与 feature/chat、feature/chat_list 的同名助手一致）。 */
export function sandboxFileUri(path: string | null): string {
  if (path === null || path.length === 0) {
    return '';
  }
  if (path.startsWith('file://')) {
    return path;
  }
  const normalized: string = path.startsWith('/') ? path : '/' + path;
  try {
    return fileUri.getUriFromPath(normalized);
  } catch (_e) {
    return 'file://org.telegram.x.harmony' + normalized;
  }
}

export interface SharedContentViewDataOptions {
  readonly activeTab?: number;
  readonly loading?: boolean;
  readonly loadingMore?: boolean;
  readonly hasMore?: boolean;
  readonly loadFailed?: boolean;
  readonly media?: SharedMediaItem[];
  readonly files?: SharedFileItem[];
  readonly links?: SharedLinkItem[];
  readonly audios?: SharedAudioItem[];
  readonly voices?: SharedAudioItem[];
  readonly groups?: SharedGroupItem[];
  /** 正在播放的音频 fileId；0 = 未在播。行图标与点按切换都读它。 */
  readonly playingFileId?: number;
  readonly showGroupsTab?: boolean;
}

/** 共享内容分区的视图数据：由调用方从各自 UiState 映射，组件不认识具体页面的契约。 */
export class SharedContentViewData {
  readonly activeTab: number;
  readonly loading: boolean;
  readonly loadingMore: boolean;
  readonly hasMore: boolean;
  readonly loadFailed: boolean;
  readonly media: SharedMediaItem[];
  readonly files: SharedFileItem[];
  readonly links: SharedLinkItem[];
  readonly audios: SharedAudioItem[];
  readonly voices: SharedAudioItem[];
  readonly groups: SharedGroupItem[];
  readonly playingFileId: number;
  readonly showGroupsTab: boolean;

  constructor(options: SharedContentViewDataOptions) {
    this.activeTab = options.activeTab ?? 0;
    this.loading = options.loading ?? false;
    this.loadingMore = options.loadingMore ?? false;
    this.hasMore = options.hasMore ?? true;
    this.loadFailed = options.loadFailed ?? false;
    this.media = options.media ?? [];
    this.files = options.files ?? [];
    this.links = options.links ?? [];
    this.audios = options.audios ?? [];
    this.voices = options.voices ?? [];
    this.groups = options.groups ?? [];
    this.playingFileId = options.playingFileId ?? 0;
    this.showGroupsTab = options.showGroupsTab ?? true;
  }

  /** 当前 Tab 是否有内容；决定底部「加载更多」是否出现（空列表不该挂一个死按钮）。 */
  hasItems(): boolean {
    if (this.activeTab === SHARED_TAB_MEDIA) {
      return this.media.length > 0;
    }
    if (this.activeTab === SHARED_TAB_FILES) {
      return this.files.length > 0;
    }
    if (this.activeTab === SHARED_TAB_LINKS) {
      return this.links.length > 0;
    }
    if (this.activeTab === SHARED_TAB_AUDIO) {
      return this.audios.length > 0;
    }
    if (this.activeTab === SHARED_TAB_VOICE) {
      return this.voices.length > 0;
    }
    return this.groups.length > 0;
  }
}

/** 共享内容 Tab 描述（编号 + 图标 + 文案）。 */
interface SharedTabSpec {
  tab: number;
  icon: Resource;
  /** 存的是 Lang key，不是文案：页签文字要随语言在渲染时取。 */
  labelKey: string;
}

/**
 * Tab 顺序照 Android `ProfileController.getFiltersOrder()`（照片视频 → 文件 → 链接 →
 * 音乐 → 语音），「共同群组」是私聊资料页专属所以固定最后。编号与
 * model/SharedContentSearch 的 SHARED_TAB_* 一致，缺一项就会点错 Tab。
 */
const SHARED_TABS: SharedTabSpec[] = [
  { tab: SHARED_TAB_MEDIA, icon: $r('app.media.ic_photo'), labelKey: 'Media' },
  { tab: SHARED_TAB_FILES, icon: $r('app.media.ic_file'), labelKey: 'Files' },
  { tab: SHARED_TAB_LINKS, icon: $r('app.media.ic_link'), labelKey: 'Links' },
  { tab: SHARED_TAB_AUDIO, icon: $r('app.media.ic_music'), labelKey: 'Music' },
  { tab: SHARED_TAB_VOICE, icon: $r('app.media.ic_mic'), labelKey: 'Voice' },
  { tab: SHARED_TAB_GROUPS, icon: $r('app.media.ic_group'), labelKey: 'Groups' }
];

@Component
export struct SharedContentSection {
  @StorageProp('activeTheme') T: Theme = LightTheme;

  /**
   * I18N-HOTSWITCH-101：语言 tick。
   *
   * 装配层（entry/Index）订阅 Lang，把**有效语言**（'en' | 'zh'，不是偏好 'system'）镜像进
   * AppStorage('activeLanguage')；本页把它接成自己的可观察属性，于是 t() 读到的永远是
   * 当前语言，而**换语言会重渲染本页**——不再是「等下一次取数才有新字」（103/104 设备记录的头号
   * 盲区）。键缺席时 @StorageProp 用本行默认值自举，且挂载时自动取 AppStorage 现值，所以首帧
   * 就是对的，不需要再写一次手工同步。类型收在 string 而不是 SupportedLanguage：装饰器成员
   * 的字面量联合类型没有保证，而 t() 里反正要过一次收敛。
   */
  @StorageProp('activeLanguage') effectiveLanguage: string = 'en';
  @Prop view: SharedContentViewData = new SharedContentViewData({});
  onSelectTab: (tab: number) => void = (): void => {};
  onLoadMore: () => void = (): void => {};
  onOpenGroup: (chatId: number) => void = (): void => {};
  /** 点音乐/语音行：同一行再点一次是暂停，切换行由 reducer 负责换轨。 */
  onToggleAudio: (fileId: number) => void = (): void => {};

  private t(key: string, ...args: (string | number)[]): string {
    const langCode: SupportedLanguage = this.effectiveLanguage === 'zh' ? 'zh' : 'en';
    return Lang.getInstance().formatByKey(key, langCode, args);
  }

  private tabs(): SharedTabSpec[] {
    if (this.view.showGroupsTab) {
      return SHARED_TABS;
    }
    return SHARED_TABS.filter((spec: SharedTabSpec): boolean => spec.tab !== SHARED_TAB_GROUPS);
  }

  /**
   * 日期分段（CHATPROF-DATE）。四个内容 Tab 分段 —— 共同群组 Tab 不分，
   * 对齐 Android `SharedChatsController.needDateSectionSplitting() = false`。
   * 每次渲染现算：条目是逐页 append 进来的，段边界会随翻页移动，缓存反而容易漏更。
   */
  /**
   * I18N-HOTSWITCH-101：分组头是 span.header 里的已解析串，只有让 build 读到语言位
   * 才会随应用内换语言重算，所以各 *Spans() 都显式带上本组件的响应式语言。
   */
  private languageCode(): SupportedLanguage {
    return this.effectiveLanguage === 'zh' ? 'zh' : 'en';
  }

  private mediaSpans(): SharedDateSpan[] {
    const dates: number[] = this.view.media.map((item: SharedMediaItem): number => item.date);
    return splitSharedDateSpans(dates, Date.now(), this.languageCode());
  }

  private fileSpans(): SharedDateSpan[] {
    const dates: number[] = this.view.files.map((item: SharedFileItem): number => item.date);
    return splitSharedDateSpans(dates, Date.now(), this.languageCode());
  }

  private linkSpans(): SharedDateSpan[] {
    const dates: number[] = this.view.links.map((item: SharedLinkItem): number => item.date);
    return splitSharedDateSpans(dates, Date.now(), this.languageCode());
  }

  private audioSpans(): SharedDateSpan[] {
    const dates: number[] = this.view.audios.map((item: SharedAudioItem): number => item.date);
    return splitSharedDateSpans(dates, Date.now(), this.languageCode());
  }

  private voiceSpans(): SharedDateSpan[] {
    const dates: number[] = this.view.voices.map((item: SharedAudioItem): number => item.date);
    return splitSharedDateSpans(dates, Date.now(), this.languageCode());
  }

  /** 分组头（对齐 TGX `ListItem.TYPE_HEADER`：左对齐小字、次要色，非吸顶）。 */
  @Builder
  SectionHeader(text: string) {
    Text(text)
      .fontSize(this.T.typography.footnote.fontSize)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.T.colors.textSecondary)
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({
        left: this.T.spacing.screenInset,
        right: this.T.spacing.screenInset,
        top: this.T.spacing.sm,
        bottom: this.T.spacing.xs
      })
  }

  /** 链接 Tab 的外层容器已经带 screenInset，这里再带一次会双倍缩进。 */
  @Builder
  SectionHeaderFlush(text: string) {
    Text(text)
      .fontSize(this.T.typography.footnote.fontSize)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.T.colors.textSecondary)
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.xs })
  }

  /** 共享内容 Tab 栏（选中 accent + 下划线）。 */
  @Builder
  TabBar() {
    Row() {
      ForEach(this.tabs(), (spec: SharedTabSpec) => {
        Column({ space: this.T.spacing.xs }) {
          Image(spec.icon)
            .width(20)
            .height(20)
            .fillColor(this.view.activeTab === spec.tab
              ? this.T.colors.accent
              : this.T.colors.textSecondary)
          Text(this.t(spec.labelKey))
            .fontSize(this.T.typography.footnote.fontSize)
            .fontColor(this.view.activeTab === spec.tab
              ? this.T.colors.accent
              : this.T.colors.textSecondary)
          Blank()
            .width(24)
            .height(2)
            .backgroundColor(this.view.activeTab === spec.tab
              ? this.T.colors.accent
              : this.T.colors.background)
        }
        .layoutWeight(1)
        .onClick(() => {
          this.onSelectTab(spec.tab);
        })
      }, (spec: SharedTabSpec) => `${spec.tab}`)
    }
    .width('100%')
    .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.sm })
  }

  /** 内容区空态（对齐 TGX 文案）。 */
  @Builder
  EmptyKey(titleKey: string, subtitleKey: string) {
    Column() {
      Text(this.t(titleKey))
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.textPrimary)
        .textAlign(TextAlign.Center)
      Text(this.t(subtitleKey))
        .fontSize(this.T.typography.footnote.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ top: this.T.spacing.xs })
    }
    .accessibilityGroup(true)
    .width('100%')
    .padding({ top: this.T.spacing.lg, bottom: this.T.spacing.lg, left: this.T.spacing.lg, right: this.T.spacing.lg })
    .alignItems(HorizontalAlign.Center)
  }

  /** 拉取失败与「确实没有内容」分开显示，否则请求挂了页面照样报「暂无」。 */
  @Builder
  LoadFailed() {
    Column() {
      Text(this.t('Failed to load'))
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.textPrimary)
        .textAlign(TextAlign.Center)
      Text(this.t('Tap the tab above to retry.'))
        .fontSize(this.T.typography.footnote.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ top: this.T.spacing.xs })
    }
    .accessibilityGroup(true)
    .width('100%')
    .padding({ top: this.T.spacing.lg, bottom: this.T.spacing.lg, left: this.T.spacing.lg, right: this.T.spacing.lg })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  MediaTile(item: SharedMediaItem) {
    Column() {
      if (item.localPath !== null && item.localPath.length > 0) {
        Image(sandboxFileUri(item.localPath))
          .width('100%')
          .aspectRatio(1)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Image(item.isPhoto ? $r('app.media.ic_photo') : $r('app.media.ic_video'))
            .width(24)
            .height(24)
            .fillColor(this.T.colors.textSecondary)
        }
        .width('100%')
        .aspectRatio(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.T.colors.surfaceVariant)
      }
    }
    .width('33.33%')
    .padding(this.T.spacing.hairline)
  }

  @Builder
  MediaGrid() {
    if (this.view.media.length === 0) {
      if (this.view.loadFailed) {
        this.LoadFailed()
      } else {
        this.EmptyKey('No Media Yet', 'Share photos and videos in this chat and access them on all your devices.')
      }
    } else {
      // 一段一个宫格：分组头要独占一行，所以不能全塞进同一个 wrap Flex。
      Column() {
        ForEach(this.mediaSpans(), (span: SharedDateSpan) => {
          Column() {
            if (span.header.length > 0) {
              this.SectionHeader(span.header)
            }
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.view.media.slice(span.start, span.end), (item: SharedMediaItem, index: number) => {
                this.MediaTile(item)
              }, (item: SharedMediaItem, index: number) => `${span.start}_${index}_${item.fileId}`)
            }
            .width('100%')
          }
          .width('100%')
        }, (span: SharedDateSpan) => `${span.start}_${span.header}`)
      }
      .width('100%')
    }
  }

  @Builder
  FileRow(item: SharedFileItem) {
    Row() {
      Image($r('app.media.ic_file'))
        .width(28)
        .height(28)
        .fillColor(this.T.colors.accent)
      Column() {
        Text(item.fileName)
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.fileSizeText.length > 0 && item.dateText.length > 0
          ? `${item.fileSizeText} · ${item.dateText}`
          : (item.fileSizeText.length > 0 ? item.fileSizeText : item.dateText))
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .margin({ top: this.T.spacing.hairline })
      }
      .accessibilityGroup(true)
      .margin({ left: this.T.spacing.sm })
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.sm,
      bottom: this.T.spacing.sm
    })
  }

  @Builder
  FileList() {
    if (this.view.files.length === 0) {
      if (this.view.loadFailed) {
        this.LoadFailed()
      } else {
        this.EmptyKey('No Files Yet', 'Share files in this chat and access them on all your devices.')
      }
    } else {
      Column() {
        ForEach(this.fileSpans(), (span: SharedDateSpan) => {
          Column() {
            if (span.header.length > 0) {
              this.SectionHeader(span.header)
            }
            ForEach(this.view.files.slice(span.start, span.end), (item: SharedFileItem, index: number) => {
              this.FileRow(item)
            }, (item: SharedFileItem, index: number) => `${span.start}_${index}`)
          }
          .width('100%')
        }, (span: SharedDateSpan) => `${span.start}_${span.header}`)
      }
      .width('100%')
    }
  }

  @Builder
  LinkCard(item: SharedLinkItem) {
    Column() {
      if (item.siteName.length > 0) {
        Text(item.siteName)
          .fontSize(this.T.typography.body.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      if (item.description.length > 0) {
        Text(item.description)
          .fontSize(this.T.typography.subheadline.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: item.siteName.length > 0 ? this.T.spacing.hairline : 0 })
      }
      Text(item.url)
        .fontSize(this.T.typography.footnote.fontSize)
        .fontColor(this.T.colors.link)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: this.T.spacing.xs })
    }
    .width('100%')
    .padding(this.T.spacing.md)
    .backgroundColor(this.T.colors.surfaceVariant)
    .borderRadius(this.T.radius.md)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  LinkList() {
    if (this.view.links.length === 0) {
      if (this.view.loadFailed) {
        this.LoadFailed()
      } else {
        this.EmptyKey('No Links Yet', 'Share links in this chat and access them on all your devices.')
      }
    } else {
      Column() {
        ForEach(this.linkSpans(), (span: SharedDateSpan) => {
          Column({ space: this.T.spacing.sm }) {
            if (span.header.length > 0) {
              this.SectionHeaderFlush(span.header)
            }
            ForEach(this.view.links.slice(span.start, span.end), (item: SharedLinkItem, index: number) => {
              this.LinkCard(item)
            }, (item: SharedLinkItem, index: number) => `${span.start}_${index}`)
          }
          .width('100%')
        }, (span: SharedDateSpan) => `${span.start}_${span.header}`)
      }
      .width('100%')
      .padding({
        left: this.T.spacing.screenInset,
        right: this.T.spacing.screenInset,
        top: this.T.spacing.sm,
        bottom: this.T.spacing.sm
      })
    }
  }

  private isPlaying(fileId: number): boolean {
    return fileId !== 0 && this.view.playingFileId === fileId;
  }

  /**
   * 音乐 / 语音行（SHARED-AUDIO）：左侧圆形播放按钮 + 标题 + 副标题，
   * 对齐 Android `AudioCell`/`MusicCell`。未落盘时图标照常显示，点按由 coordinator
   * 先触发下载、落盘后续播（播放态由 reducer 乐观置位，这里不判 localPath）。
   */
  @Builder
  AudioRow(item: SharedAudioItem) {
    Row() {
      Column() {
        Image(this.isPlaying(item.fileId) ? $r('app.media.ic_pause') : $r('app.media.ic_play'))
          .width(18)
          .height(18)
          .fillColor(this.isPlaying(item.fileId) ? this.T.colors.textOnAccent : this.T.colors.accent)
      }
      .width(36)
      .height(36)
      .borderRadius(this.T.radius.full)
      .backgroundColor(this.isPlaying(item.fileId) ? this.T.colors.accent : this.T.colors.surfaceVariant)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      Column() {
        Text(item.title.length > 0 ? item.title : this.t('Voice message'))
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.subtitle)
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: this.T.spacing.hairline })
      }
      .accessibilityGroup(true)
      .margin({ left: this.T.spacing.sm })
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.sm,
      bottom: this.T.spacing.sm
    })
    .onClick(() => {
      this.onToggleAudio(item.fileId);
    })
  }

  @Builder
  AudioList() {
    if (this.view.audios.length === 0) {
      if (this.view.loadFailed) {
        this.LoadFailed()
      } else {
        this.EmptyKey('No Music Yet', 'Share audio files in this chat and access them on all your devices.')
      }
    } else {
      Column() {
        ForEach(this.audioSpans(), (span: SharedDateSpan) => {
          Column() {
            if (span.header.length > 0) {
              this.SectionHeader(span.header)
            }
            ForEach(this.view.audios.slice(span.start, span.end), (item: SharedAudioItem, index: number) => {
              this.AudioRow(item)
            }, (item: SharedAudioItem, index: number) => `${span.start}_${index}_${item.fileId}`)
          }
          .width('100%')
        }, (span: SharedDateSpan) => `${span.start}_${span.header}`)
      }
      .width('100%')
    }
  }

  @Builder
  VoiceList() {
    if (this.view.voices.length === 0) {
      if (this.view.loadFailed) {
        this.LoadFailed()
      } else {
        this.EmptyKey('No Voice Messages Yet', 'Share voice messages in this chat and access them on all your devices.')
      }
    } else {
      Column() {
        ForEach(this.voiceSpans(), (span: SharedDateSpan) => {
          Column() {
            if (span.header.length > 0) {
              this.SectionHeader(span.header)
            }
            ForEach(this.view.voices.slice(span.start, span.end), (item: SharedAudioItem, index: number) => {
              this.AudioRow(item)
            }, (item: SharedAudioItem, index: number) => `${span.start}_${index}_${item.fileId}`)
          }
          .width('100%')
        }, (span: SharedDateSpan) => `${span.start}_${span.header}`)
      }
      .width('100%')
    }
  }

  /** 共同群组列表（仅私聊资料页；点按交给装配层导航）。 */
  @Builder
  GroupList() {
    if (this.view.groups.length === 0) {
      if (this.view.loadFailed) {
        this.LoadFailed()
      } else {
        this.EmptyKey('No Common Groups', 'Groups you have in common with this user will appear here.')
      }
    } else {
      Column() {
        ForEach(this.view.groups.slice(), (item: SharedGroupItem, index: number) => {
          Row() {
            Text(avatarLetterOf(item.title))
              .accessibilityLevel('no')
              .width(40)
              .height(40)
              .borderRadius(this.T.radius.full)
              .backgroundColor(avatarColorOf(getAvatarColorIndex(item.chatId)))
              .fontColor(this.T.colors.textOnAccent)
              .fontSize(16)
              .textAlign(TextAlign.Center)
            Column() {
              Text(item.title)
                .fontSize(this.T.typography.body.fontSize)
                .fontColor(this.T.colors.textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (item.subtitle.length > 0) {
                Text(item.subtitle)
                  .fontSize(this.T.typography.subheadline.fontSize)
                  .fontColor(this.T.colors.textSecondary)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: this.T.spacing.hairline })
              }
            }
            .margin({ left: this.T.spacing.sm })
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.sm,
            bottom: this.T.spacing.sm
          })
          .onClick(() => {
            this.onOpenGroup(item.chatId);
          })
        }, (item: SharedGroupItem, index: number) => `${item.chatId}_${index}`)
      }
      .width('100%')
    }
  }

  @Builder
  Content() {
    if (this.view.activeTab === SHARED_TAB_MEDIA) {
      this.MediaGrid()
    } else if (this.view.activeTab === SHARED_TAB_FILES) {
      this.FileList()
    } else if (this.view.activeTab === SHARED_TAB_LINKS) {
      this.LinkList()
    } else if (this.view.activeTab === SHARED_TAB_AUDIO) {
      this.AudioList()
    } else if (this.view.activeTab === SHARED_TAB_VOICE) {
      this.VoiceList()
    } else {
      this.GroupList()
    }
  }

  build() {
    Column() {
      this.TabBar()

      if (this.view.loading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(this.T.colors.accent)
        }
        .width('100%')
        .padding({ top: this.T.spacing.lg, bottom: this.T.spacing.lg })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        this.Content()

        if (this.view.hasItems()) {
          if (this.view.loadingMore) {
            Row({ space: this.T.spacing.xs }) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color(this.T.colors.accent)
              Text(this.t('Loading more…'))
                .fontSize(this.T.typography.footnote.fontSize)
                .fontColor(this.T.colors.textSecondary)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: this.T.spacing.md, bottom: this.T.spacing.md })
          } else if (this.view.hasMore) {
            Row() {
              Text(this.t('Load More'))
                .fontSize(this.T.typography.subheadline.fontSize)
                .fontColor(this.T.colors.accent)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.md })
            .onClick(() => {
              this.onLoadMore();
            })
          }
        }
      }
    }
    .width('100%')
  }
}
