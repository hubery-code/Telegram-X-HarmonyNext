/**
 * feature/contact — 联系人页（CONTACT-101）。
 *
 * 界面组成（对齐 Android ContactsController 的信息面，MVP 裁剪）：
 * - 顶栏：‹ 返回（prop onBack）+ 'Contacts' 标题 + 搜索输入框（onChange → QueryChanged）；
 * - 内容：isLoading 转圈 / errorMessage 错误态 / 空态 'No contacts' / 过滤后分组 List
 *   （字母标题行 sticky + 行：彩色字母底圆头像或 Image(toSandboxUri) + displayName +
 *   副标题「电话号码 → @username → 在线状态」三级优先，见 subtitleOf）；
 *   分组数据取 `uiState.sections`
 *   （reducer 里由 model/ContactsSections 算出，与排序同一套规则）；
 * - 右侧 A–Z 索引条：字母来自真实存在的分组，点一个字母滚到该段，按住上下拖连续换段
 *   并在左侧浮出当前段字母气泡，当前段随滚动/拖拽高亮；只有一个分组时不出现；
 * - 行 onClick → dispatch ContactTapped(item.userId)。
 *
 * 行点击双回调接线约定（对齐 SearchPage 的协调器/降级双路径，二者默认均为 no-op）：
 * - 推荐（装配层已建 coordinator）：只接 onDispatch（→ coordinator.dispatch →
 *   reducer 出 OpenUserProfile 效应 → coordinator.options.onOpenUserProfile 导航），
 *   页面 onOpenUserProfile 保持 no-op；
 * - 纯页面降级（无 coordinator）：接 onOpenUserProfile 直接导航，onDispatch 保持 no-op。
 * 两个回调同时接真实实现会双开用户资料页，装配层务必二选一。
 *
 * 全部颜色/间距/字号走 design tokens（core-design-system）。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { A11y, a11y } from '@tgx/core-common';
import { fileUri } from '@kit.CoreFileKit';
import { ContactsItem, ContactsSection, ContactsUiState } from '../contract/ContactsUiState';
import {
  activeSectionIndex,
  indexBarVisible,
  indexScrubAt,
  IndexScrubHit,
  sectionScrollOffsets
} from '../model/ContactsSections';
import { ContactsIntent, QueryChanged, ContactTapped } from '../contract/ContactsIntent';


const BACK_ARROW_SIZE: number = 44;
const ROW_AVATAR_SIZE: number = 44;
const ROW_HEIGHT: number = 64;
const SECTION_HEADER_HEIGHT: number = 28;
/** 索引条：字母列宽与贴右边距（Android SectionedRecyclerView 的 thumb 也是贴边 9dp）。 */
const INDEX_BAR_WIDTH: number = 24;
const INDEX_BAR_MARGIN: number = 4;
const INDEX_LETTER_HEIGHT: number = 16;
/** 拖拽时跟随手指的当前段气泡边长。 */
const SCRUB_BUBBLE_SIZE: number = 56;

/** 本地沙箱绝对路径 → 可渲染 uri（与 feature/profile 的同名助手一致）。 */
function toSandboxUri(path: string | null): string {
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

/** Telegram 经典头像调色板（0..6），与 feature/profile 的 AVATAR_PALETTE 同色值。 */
const AVATAR_PALETTE: string[] = [
  '#FFCC5049', '#FFD67722', '#FF955CDB', '#FF40A920',
  '#FF309EBA', '#FF368AD1', '#FFC7508B'
];

@Component
export struct ContactsPage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @Prop uiState: ContactsUiState = ContactsUiState.initial();
  onDispatch: (intent: ContactsIntent) => void = (): void => {};
  onBack: () => void = (): void => {};
  onOpenUserProfile: (userId: number) => void = (): void => {};
  onAddContact: () => void = (): void => {};

  /**
   * 索引条当前高亮段。onDidScroll 每帧都会来，这里只在**真的换段**时写 @State，
   * 否则整页每帧重排（与资料页封面收起态同一套取舍）。
   */
  @State private activeIndex: number = 0;
  /**
   * 拖拽中的段落下标；-1 表示当前没有在拖索引条（气泡只在拖拽期间出现，
   * 抬手即隐藏 —— Android 的 `SectionedRecyclerView` thumb 气泡同行为）。
   */
  @State private scrubIndex: number = -1;
  /** 气泡中心在索引条自身坐标系里的位移（vp）。 */
  @State private scrubCenterY: number = 0;
  private scroller: Scroller = new Scroller();

  /**
   * 索引条自身高度：字母等高出列、无间距，所以高度纯算得出。
   * 刻意不用 `height('100%')` + `justifyContent(Center)`：那样条的可视内容居中但
   * 组件占满整栏，拖拽坐标还得先减去上下留白；固定成内容高度后由 `Stack` 的
   * `Alignment.End` 居中，`localY` 直接就是字母序里的位移。
   */
  private indexBarHeight(): number {
    return this.uiState.sections.length * INDEX_LETTER_HEIGHT;
  }

  /**
   * 各分组的滚动位移（vp）：行高/标题高固定，故纯算得出，不需要量真实布局。
   * `spacing.hairline` 是 List.divider 在每个分组边界上多占的 2vp，漏了会逐组累计偏差。
   */
  private sectionOffsets(): number[] {
    return sectionScrollOffsets(
      this.uiState.sections,
      SECTION_HEADER_HEIGHT,
      ROW_HEIGHT,
      this.T.spacing.hairline
    );
  }

  /** `animated=false`：拖拽中要即时跟手，逐帧补间动画会让列表永远落在手指后面。 */
  private scrollToSection(index: number, animated: boolean = true): void {
    const offsets: number[] = this.sectionOffsets();
    if (index < 0 || index >= offsets.length) {
      return;
    }
    this.activeIndex = index;
    this.scroller.scrollTo({
      xOffset: 0,
      yOffset: offsets[index],
      animation: animated ? { duration: this.T.motion.durationNormal } : false
    });
  }

  private syncActiveSection(): void {
    const next: number = activeSectionIndex(this.sectionOffsets(), this.scroller.currentOffset().yOffset);
    if (next !== this.activeIndex) {
      this.activeIndex = next;
    }
  }

  /** 拖拽中的段落下标（越界归 -1，即不出气泡）。 */
  private scrubSectionIndex(): number {
    if (this.scrubIndex < 0 || this.scrubIndex >= this.uiState.sections.length) {
      return -1;
    }
    return this.scrubIndex;
  }

  /** 气泡里的字母：不在拖拽态就是空串，页面据此决定画不画气泡。 */
  private scrubLetter(): string {
    const index: number = this.scrubSectionIndex();
    return index >= 0 ? this.uiState.sections[index].letter : '';
  }

  /**
   * 索引条拖拽：把手指的组件内纵坐标换成段落，立刻跳过去并抬起气泡。
   *
   * `fingerList[0].localY` 是**相对当前组件左上角**的 vp 坐标（见 ArkUI 手势公共接口
   * 的 FingerInfo 表），而本条的高度就是字母内容总高、由 `Stack` 居中，所以不必再
   * 换算上下留白。键盘/手柄触发时 `fingerList` 为空，直接跳过。
   */
  private handleScrub(event: GestureEvent): void {
    if (event.fingerList.length === 0) {
      return;
    }
    const hit: IndexScrubHit = indexScrubAt(
      this.indexBarHeight(),
      this.uiState.sections.length,
      event.fingerList[0].localY,
      INDEX_LETTER_HEIGHT
    );
    if (hit.index < 0) {
      return;
    }
    this.scrubIndex = hit.index;
    this.scrubCenterY = hit.centerY;
    if (hit.index !== this.activeIndex) {
      this.scrollToSection(hit.index, false);
    }
  }

  private endScrub(): void {
    this.scrubIndex = -1;
    this.scrubCenterY = 0;
  }

  private avatarColor(index: number): string {
    if (index < 0 || index >= AVATAR_PALETTE.length) {
      return AVATAR_PALETTE[0];
    }
    return AVATAR_PALETTE[index];
  }

  private handleQueryChange(value: string): void {
    this.onDispatch(new QueryChanged(value));
  }

  /** 见文件头「行点击双回调接线约定」：onDispatch 与 onOpenUserProfile 二选一接线。 */
  private handleContactTapped(userId: number): void {
    this.onDispatch(new ContactTapped(userId));
    this.onOpenUserProfile(userId);
  }

  /**
   * 行副标题优先级：**电话号码 → @username → 在线状态**。
   *
   * 对齐 Android `TGUser.updateStatus()`（`data/TGUser.java:312-333`）：`FLAG_CONTACT`
   * 命中时 `statusText = Strings.formatPhone(user.phoneNumber)`，其后的分支才是
   * `FLAG_USERNAME`（拼 `@xxx`）与最后兜底的 `getChatMemberSubtitle`（last seen）。
   * 本页数据源就是 `getContacts`，回包里的都是联系人，所以有号码就先显号码；
   * 没号码（只按 username 加过、或对方隐藏了号码）才回落到 @username / 状态。
   */
  private subtitleOf(item: ContactsItem): string {
    if (item.phoneNumber.length > 0) {
      return item.phoneNumber;
    }
    if (item.username.length > 0) {
      return `@${item.username}`;
    }
    return item.statusText;
  }

  @Builder
  Header() {
    Column() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(this.T.colors.accent)
          .margin({ left: this.T.spacing.xs, right: this.T.spacing.md })
        .accessibilityText(a11y(A11y.BACK))
          .onClick(() => {
            this.onBack();
          })

        Text('Contacts')
          .fontSize(this.T.typography.title.fontSize)
          .fontWeight(this.T.typography.title.fontWeight)
          .fontColor(this.T.colors.textPrimary)
          .layoutWeight(1)

        Image($r('app.media.ic_person_add'))
          .width(24)
          .height(24)
          .fillColor(this.T.colors.accent)
        .accessibilityText(a11y(A11y.ADD_CONTACT))
          .onClick(() => {
            this.onAddContact();
          })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm })

      Row() {
        Image($r('app.media.ic_search'))
          .width(18)
          .height(18)
          .fillColor(this.T.colors.textSecondary)
          .margin({ left: this.T.spacing.md, right: this.T.spacing.xs })

        TextInput({ placeholder: 'Search', text: this.uiState.query })
          .layoutWeight(1)
          .height(38)
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .backgroundColor(Color.Transparent)
          .padding({ left: 0, right: this.T.spacing.md })
          .onChange((value: string) => {
            this.handleQueryChange(value);
          })
      }
      .width('100%')
      .height(38)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.T.colors.backgroundSecondary)
      .borderRadius(this.T.radius.sm)
      .margin({ left: this.T.spacing.sm, right: this.T.spacing.sm })
    }
    .width('100%')
    .backgroundColor(this.T.colors.background)
    .padding({ bottom: this.T.spacing.sm })
  }

  @Builder
  SectionHeader(letter: string) {
    Row() {
      Text(letter)
        .fontSize(this.T.typography.footnote.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .height(SECTION_HEADER_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ left: this.T.spacing.screenInset, right: this.T.spacing.screenInset })
    .backgroundColor(this.T.colors.background)
  }

  /**
   * 右侧 A–Z 索引条：字母来自**真实存在**的分组（不是固定 26 格），点一个字母跳到
   * 该段，按住上下拖则连续换段（CONTACT-102）。Android 侧对应 `SectionedRecyclerView`
   * 贴边的比例 thumb + 当前段字母气泡。
   *
   * 高度取 `indexBarHeight()`（= 字母数 × 行高）而不是 `'100%'`：见该方法注释里的
   * 坐标换算取舍。`PanGesture` 只认纵向，`distance: 2` 让拖拽比默认 5vp 更早起势，
   * 但 2vp 以内仍算点按、走字母自己的 `onClick`。
   */
  @Builder
  IndexBar() {
    Column() {
      ForEach(this.uiState.sections.slice(), (section: ContactsSection, index: number) => {
        Text(section.letter)
          .width(INDEX_BAR_WIDTH)
          .height(INDEX_LETTER_HEIGHT)
          .fontSize(this.T.typography.caption.fontSize)
          .fontColor(index === this.activeIndex ? this.T.colors.accent : this.T.colors.textSecondary)
          .fontWeight(index === this.activeIndex ? FontWeight.Bold : FontWeight.Normal)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.scrollToSection(index);
          })
      }, (section: ContactsSection, index: number): string => `${section.letter}#${section.startIndex}`)
    }
    .width(INDEX_BAR_WIDTH)
    .height(this.indexBarHeight())
    .margin({ right: INDEX_BAR_MARGIN })
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 2 })
        .onActionStart((event: GestureEvent) => {
          this.handleScrub(event);
        })
        .onActionUpdate((event: GestureEvent) => {
          this.handleScrub(event);
        })
        .onActionEnd(() => {
          this.endScrub();
        })
        .onActionCancel(() => {
          this.endScrub();
        })
    )
  }

  /**
   * 索引条 + 拖拽气泡。气泡画在条的**左侧**（贴边一条只有 24vp，字母浮层放条上会
   * 盖住相邻字母），行高固定为索引条高度，所以气泡出现/消失不会让条上下跳动。
   */
  @Builder
  IndexBarWithScrub() {
    Row() {
      if (this.scrubLetter().length > 0) {
        Text(this.scrubLetter())
          .width(SCRUB_BUBBLE_SIZE)
          .height(SCRUB_BUBBLE_SIZE)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.accent)
          .fontColor(this.T.colors.textOnAccent)
          .fontSize(this.T.typography.title.fontSize)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .margin({
            top: this.scrubCenterY > SCRUB_BUBBLE_SIZE / 2
              ? this.scrubCenterY - SCRUB_BUBBLE_SIZE / 2
              : 0,
            right: this.T.spacing.sm
          })
      }

      this.IndexBar()
    }
    .height(this.indexBarHeight())
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  ContactRow(item: ContactsItem) {
    Row() {
      if (item.avatarPath !== null && item.avatarPath.length > 0) {
        Image(toSandboxUri(item.avatarPath))
          .width(ROW_AVATAR_SIZE)
          .height(ROW_AVATAR_SIZE)
          .borderRadius(this.T.radius.full)
          .objectFit(ImageFit.Cover)
      } else {
        Text(item.avatarLetters.length > 0 ? item.avatarLetters : '?')
          .width(ROW_AVATAR_SIZE)
          .height(ROW_AVATAR_SIZE)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.avatarColor(item.colorIndex))
          .fontColor(this.T.colors.textOnAccent)
          .fontSize(this.T.typography.subheadline.fontSize)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
      }

      Column() {
        Text(item.displayName.length > 0 ? item.displayName : 'Unknown')
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 副标题：电话号码 → @username → 在线状态（见 subtitleOf）
        if (this.subtitleOf(item).length > 0) {
          Text(this.subtitleOf(item))
            .fontSize(this.T.typography.footnote.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: this.T.spacing.md })
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ left: this.T.spacing.screenInset, right: this.T.spacing.screenInset })
    .onClick(() => {
      this.handleContactTapped(item.userId);
    })
  }

  build() {
    Column() {
      this.Header()

      if (this.uiState.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.T.colors.accent)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.uiState.errorMessage !== null) {
        Column() {
          Text(this.uiState.errorMessage)
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.uiState.items.length === 0) {
        Column() {
          Text('No contacts')
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textSecondary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        // End = 尾端纵向居中：List 占满整栏不受影响，只让索引条垂直居中贴右。
        Stack({ alignContent: Alignment.End }) {
          List({ scroller: this.scroller }) {
            ForEach(this.uiState.sections.slice(), (section: ContactsSection) => {
              ListItemGroup({ header: this.SectionHeader(section.letter) }) {
                ForEach(section.items.slice(), (item: ContactsItem) => {
                  ListItem() {
                    this.ContactRow(item)
                  }
                }, (item: ContactsItem): string => `${item.userId}`)
              }
              // key 带段起点：同一字母被分成两段时（列表极短或数据未排序）key 仍唯一，
              // 否则 ArkUI 复用同一 key 的节点会让两组内容互相覆盖。
            }, (section: ContactsSection): string => `${section.letter}#${section.startIndex}`)
          }
          .width('100%')
          .height('100%')
          .sticky(StickyStyle.Header)
          .divider({
            strokeWidth: this.T.spacing.hairline,
            color: this.T.colors.divider,
            startMargin: this.T.spacing.screenInset + ROW_AVATAR_SIZE + this.T.spacing.md
          })
          .scrollBar(BarState.Off)
          .onDidScroll(() => {
            this.syncActiveSection();
          })

          if (indexBarVisible(this.uiState.sections)) {
            this.IndexBarWithScrub()
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }
}
