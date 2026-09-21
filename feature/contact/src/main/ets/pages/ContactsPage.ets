/**
 * feature/contact — 联系人页（CONTACT-101）。
 *
 * 界面组成（对齐 Android ContactsController 的信息面，MVP 裁剪）：
 * - 顶栏：‹ 返回（prop onBack）+ 'Contacts' 标题 + 搜索输入框（onChange → QueryChanged）；
 * - 内容：isLoading 转圈 / errorMessage 错误态 / 空态 'No contacts' / 过滤后分组 List
 *   （字母标题行 + 行：彩色字母底圆头像或 Image(toSandboxUri) + displayName +
 *   副标题 @username 优先、否则 statusText）；
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
import { fileUri } from '@kit.CoreFileKit';
import { ContactsItem, ContactsUiState } from '../contract/ContactsUiState';
import { ContactsIntent, QueryChanged, ContactTapped } from '../contract/ContactsIntent';


const BACK_ARROW_SIZE: number = 44;
const ROW_AVATAR_SIZE: number = 44;
const ROW_HEIGHT: number = 64;
const SECTION_HEADER_HEIGHT: number = 28;

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

/** 分组字母段：items 已按 displayName 排序，连续同字母归一段。 */
interface ContactsSection {
  letter: string;
  items: ContactsItem[];
}

function buildContactsSections(items: ContactsItem[]): ContactsSection[] {
  const sections: ContactsSection[] = [];
  for (let i: number = 0; i < items.length; i++) {
    const item: ContactsItem = items[i];
    const first: string = item.displayName.length > 0 ? item.displayName.charAt(0).toUpperCase() : '#';
    const letter: string = first >= 'A' && first <= 'Z' ? first : '#';
    const last: ContactsSection | null = sections.length > 0 ? sections[sections.length - 1] : null;
    if (last !== null && last.letter === letter) {
      last.items.push(item);
    } else {
      const section: ContactsSection = { letter: letter, items: [item] };
      sections.push(section);
    }
  }
  return sections;
}

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

  @Builder
  Header() {
    Column() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(this.T.colors.accent)
          .margin({ left: this.T.spacing.xs, right: this.T.spacing.md })
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

        if (item.username.length > 0) {
          Text(`@${item.username}`)
            .fontSize(this.T.typography.footnote.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else if (item.statusText.length > 0) {
          Text(item.statusText)
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
        List() {
          ForEach(buildContactsSections(this.uiState.items).slice(), (section: ContactsSection) => {
            ListItemGroup({ header: this.SectionHeader(section.letter) }) {
              ForEach(section.items.slice(), (item: ContactsItem) => {
                ListItem() {
                  this.ContactRow(item)
                }
              }, (item: ContactsItem): string => `${item.userId}`)
            }
          }, (section: ContactsSection): string => section.letter)
        }
        .width('100%')
        .layoutWeight(1)
        .sticky(StickyStyle.Header)
        .divider({
          strokeWidth: this.T.spacing.hairline,
          color: this.T.colors.divider,
          startMargin: this.T.spacing.screenInset + ROW_AVATAR_SIZE + this.T.spacing.md
        })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }
}
