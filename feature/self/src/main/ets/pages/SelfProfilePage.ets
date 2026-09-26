/**
 * feature/self — 我的资料页（SELF-101）。
 *
 * 对齐 TGX 自身资料页（ProfileController Args 为自身时的 editMode 分支）：
 * 绿色头部（居中大头像 + 展示名 + 在线状态）+ 右下角 ✎ 编辑 FAB +
 * 信息行（@username / 手机 / 个人简介 / 生日）+ 设置入口组
 * （设备 / 通知 / 数据和存储，点击直达设置页对应分区）。
 *
 * 全部颜色/间距/字号走 design tokens（core-design-system）。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { A11y, a11y } from '@tgx/core-common';
import { fileUri } from '@kit.CoreFileKit';
import { SelfProfileUiState } from '../contract/SelfProfileUiState';
import { SelfProfileIntent, EditTapped, SettingsSectionTapped } from '../contract/SelfProfileIntent';


/** 本地沙箱绝对路径 → 可渲染 uri（与 feature/profile 的同名助手一致，复制自该模块）。 */
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

/**
 * 设置入口组（SELF-101）：key 与 `settingsSection/{section}` 路由参数一致，
 * 点击经 reducer 出 OpenSettingsSection 效应。只列**已有落点**的项——
 * 「隐私和安全」是 SELF-102 补上的：TDLib getUserPrivacySettingRules /
 * setUserPrivacySettingRules 读写闭环已在 feature/settings 的 PrivacySubPage 落地。
 */
interface SettingsEntry {
  readonly key: string;
  readonly label: string;
  readonly icon: Resource;
}

const SETTINGS_ENTRIES: SettingsEntry[] = [
  { key: 'devices', label: '设备', icon: $r('app.media.ic_devices') },
  { key: 'notifications', label: '通知', icon: $r('app.media.ic_notifications') },
  { key: 'privacy', label: '隐私和安全', icon: $r('app.media.ic_lock') },
  { key: 'data_and_storage', label: '数据和存储', icon: $r('app.media.ic_storage') }
];

const BACK_ARROW_SIZE: number = 44;
const AVATAR_SIZE: number = 96;
const FAB_SIZE: number = 56;

@Component
export struct SelfProfilePage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @Prop uiState: SelfProfileUiState = SelfProfileUiState.initial();
  onDispatch: (intent: SelfProfileIntent) => void = (): void => {};
  onBack: () => void = (): void => {};

  private avatarColor(index: number): string {
    if (index < 0 || index >= AVATAR_PALETTE.length) {
      return AVATAR_PALETTE[0];
    }
    return AVATAR_PALETTE[index];
  }

  @Builder
  Header() {
    Column() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(this.T.colors.textOnAccent)
          .margin({ left: this.T.spacing.xs })
        .accessibilityText(a11y(A11y.BACK))
          .onClick(() => {
            this.onBack();
          })
        Blank()
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm })

      Column() {
        this.Avatar()

        Text(this.uiState.displayName.length > 0 ? this.uiState.displayName : '…')
          .fontSize(this.T.typography.largeTitle.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.textOnAccent)
          .margin({ top: this.T.spacing.md })
          .textAlign(TextAlign.Center)

        if (this.uiState.statusText.length > 0) {
          Text(this.uiState.statusText)
            .fontSize(this.T.typography.subheadline.fontSize)
            .fontColor(this.T.colors.textOnAccent)
            .margin({ top: this.T.spacing.xs })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ bottom: this.T.spacing.lg })
    }
    .width('100%')
    .backgroundColor(this.T.colors.accent)
  }

  @Builder
  Avatar() {
    if (this.uiState.avatarPath !== null && this.uiState.avatarPath.length > 0) {
      Image(toSandboxUri(this.uiState.avatarPath))
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(this.T.radius.full)
        .border({ width: 2, color: this.T.colors.textOnAccent })
        .objectFit(ImageFit.Cover)
    } else {
      Text(this.uiState.avatarLetters.length > 0 ? this.uiState.avatarLetters : '?')
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(this.T.radius.full)
        .border({ width: 2, color: this.T.colors.textOnAccent })
        .backgroundColor(this.avatarColor(this.uiState.avatarColorIndex))
        .fontColor(this.T.colors.textOnAccent)
        .fontSize(36)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
    }
  }

  @Builder
  InfoRow(icon: Resource, label: string, value: string) {
    Row() {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.T.colors.textSecondary)
        .margin({ right: this.T.spacing.md })

      Column() {
        Text(label)
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.textSecondary)
        Text(value)
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .margin({ top: this.T.spacing.hairline })
      }
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
  InfoSection() {
    Column() {
      if (this.uiState.username.length > 0) {
        this.InfoRow($r('app.media.ic_username'), '用户名', `@${this.uiState.username}`)
      }
      if (this.uiState.phone.length > 0) {
        this.InfoRow($r('app.media.ic_call'), '手机', this.uiState.phone)
      }
      this.InfoRow($r('app.media.ic_info'), '个人简介', this.uiState.bio.length > 0 ? this.uiState.bio : '<空>')
      if (this.uiState.birthdayText.length > 0) {
        this.InfoRow($r('app.media.ic_cake'), '生日', this.uiState.birthdayText)
      }
    }
    .width('100%')
    .backgroundColor(this.T.colors.background)
  }

  @Builder
  SettingsSection() {
    Column() {
      ForEach(SETTINGS_ENTRIES.slice(), (entry: SettingsEntry, index: number) => {
        Column() {
          Row() {
            Image(entry.icon)
              .width(22)
              .height(22)
              .fillColor(this.T.colors.textSecondary)
              .margin({ right: this.T.spacing.md })

            Text(entry.label)
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textPrimary)
              .layoutWeight(1)

            Image($r('app.media.ic_chevron_right'))
              .width(18)
              .height(18)
              .fillColor(this.T.colors.textSecondary)
              .margin({ left: this.T.spacing.sm })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.md,
            right: this.T.spacing.md,
            top: this.T.spacing.sm,
            bottom: this.T.spacing.sm
          })
          .onClick(() => {
            this.onDispatch(new SettingsSectionTapped(entry.key));
          })

          if (index < SETTINGS_ENTRIES.length - 1) {
            Divider()
              .color(this.T.colors.divider)
              .margin({ left: this.T.spacing.md })
          }
        }
        .width('100%')
      }, (entry: SettingsEntry) => entry.key)
    }
    .width('100%')
    .backgroundColor(this.T.colors.backgroundSecondary)
    .borderRadius(this.T.radius.md)
    .margin({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.md,
      bottom: this.T.spacing.md
    })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        this.Header()

        if (this.uiState.isLoading && this.uiState.displayName.length === 0) {
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
        } else if (this.uiState.errorMessage !== null && this.uiState.displayName.length === 0) {
          Column() {
            Text(this.uiState.errorMessage)
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Scroll() {
            Column() {
              this.InfoSection()
              this.SettingsSection()
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.T.colors.background)

      if (!this.uiState.isLoading && this.uiState.errorMessage === null) {
        Column() {
          Image($r('app.media.ic_edit'))
            .width(24)
            .height(24)
            .fillColor(this.T.colors.textOnAccent)
        }
        .width(FAB_SIZE)
        .height(FAB_SIZE)
        .borderRadius(this.T.radius.full)
        .backgroundColor(this.T.colors.accent)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .accessibilityText(a11y(A11y.EDIT))
        .onClick(() => {
          this.onDispatch(new EditTapped());
        })
        .margin({ right: this.T.spacing.screenInset, bottom: this.T.spacing.lg })
      }
    }
    .width('100%')
    .height('100%')
  }
}
