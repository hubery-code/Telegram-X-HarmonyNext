/**
 * feature/self — 我的资料页（SELF-101）。
 *
 * 对齐 TGX 自身资料页（ProfileController Args 为自身时的 editMode 分支）：
 * 绿色头部（居中大头像 + 展示名 + 在线状态）+ 右下角 ✎ 编辑 FAB +
 * 信息行（@username / 手机 / 个人简介 / 生日）+ 设置入口组
 * （设备 / 通知 / 数据和存储 / 隐私和安全，占位点击）。
 *
 * 全部颜色/间距/字号走 design tokens（core-design-system）。
 */

import { LightTheme } from '@tgx/core-design-system';
import { fileUri } from '@kit.CoreFileKit';
import { SelfProfileUiState } from '../contract/SelfProfileUiState';
import { SelfProfileIntent, EditTapped, SettingsSectionTapped } from '../contract/SelfProfileIntent';

const T = LightTheme;

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

/** 设置入口组（SELF-101 点击仅占位 dispatch，副标题对齐 TGX 截图）。 */
interface SettingsEntry {
  readonly key: string;
  readonly label: string;
  readonly subtitle: string;
}

const SETTINGS_ENTRIES: SettingsEntry[] = [
  { key: 'devices', label: '设备', subtitle: '—' },
  { key: 'notifications', label: '通知', subtitle: '开启' },
  { key: 'data_and_storage', label: '数据和存储', subtitle: '' },
  { key: 'privacy_and_security', label: '隐私和安全', subtitle: '' }
];

const BACK_ARROW_SIZE: number = 44;
const AVATAR_SIZE: number = 96;
const FAB_SIZE: number = 56;

@Component
export struct SelfProfilePage {
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
        Text('‹')
          .fontSize(T.typography.title.fontSize)
          .fontWeight(T.typography.title.fontWeight)
          .fontColor(T.colors.textOnAccent)
          .width(BACK_ARROW_SIZE)
          .height(BACK_ARROW_SIZE)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onBack();
          })
        Blank()
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .padding({ left: T.spacing.sm, right: T.spacing.sm })

      Column() {
        this.Avatar()

        Text(this.uiState.displayName.length > 0 ? this.uiState.displayName : '…')
          .fontSize(T.typography.largeTitle.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(T.colors.textOnAccent)
          .margin({ top: T.spacing.md })
          .textAlign(TextAlign.Center)

        if (this.uiState.statusText.length > 0) {
          Text(this.uiState.statusText)
            .fontSize(T.typography.subheadline.fontSize)
            .fontColor(T.colors.textOnAccent)
            .margin({ top: T.spacing.xs })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ bottom: T.spacing.lg })
    }
    .width('100%')
    .backgroundColor(T.colors.accent)
  }

  @Builder
  Avatar() {
    if (this.uiState.avatarPath !== null && this.uiState.avatarPath.length > 0) {
      Image(toSandboxUri(this.uiState.avatarPath))
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(T.radius.full)
        .border({ width: 2, color: T.colors.textOnAccent })
        .objectFit(ImageFit.Cover)
    } else {
      Text(this.uiState.avatarLetters.length > 0 ? this.uiState.avatarLetters : '?')
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(T.radius.full)
        .border({ width: 2, color: T.colors.textOnAccent })
        .backgroundColor(this.avatarColor(this.uiState.avatarColorIndex))
        .fontColor(T.colors.textOnAccent)
        .fontSize(36)
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
    }
  }

  @Builder
  InfoRow(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(T.typography.footnote.fontSize)
        .fontColor(T.colors.textSecondary)
      Text(value)
        .fontSize(T.typography.body.fontSize)
        .fontColor(T.colors.textPrimary)
        .margin({ top: T.spacing.hairline })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({
      left: T.spacing.screenInset,
      right: T.spacing.screenInset,
      top: T.spacing.sm,
      bottom: T.spacing.sm
    })
  }

  @Builder
  InfoSection() {
    Column() {
      if (this.uiState.username.length > 0) {
        this.InfoRow('用户名', `@${this.uiState.username}`)
      }
      if (this.uiState.phone.length > 0) {
        this.InfoRow('手机', this.uiState.phone)
      }
      this.InfoRow('个人简介', this.uiState.bio.length > 0 ? this.uiState.bio : '<空>')
      if (this.uiState.birthdayText.length > 0) {
        this.InfoRow('生日', this.uiState.birthdayText)
      }
    }
    .width('100%')
    .backgroundColor(T.colors.background)
  }

  @Builder
  SettingsSection() {
    Column() {
      ForEach(SETTINGS_ENTRIES.slice(), (entry: SettingsEntry, index: number) => {
        Column() {
          Row() {
            Text(entry.label)
              .fontSize(T.typography.body.fontSize)
              .fontColor(T.colors.textPrimary)
              .layoutWeight(1)

            if (entry.subtitle.length > 0) {
              Text(entry.subtitle)
                .fontSize(T.typography.subheadline.fontSize)
                .fontColor(T.colors.textSecondary)
            }

            Text('›')
              .fontSize(T.typography.title.fontSize)
              .fontColor(T.colors.textSecondary)
              .margin({ left: T.spacing.sm })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: T.spacing.md,
            right: T.spacing.md,
            top: T.spacing.sm,
            bottom: T.spacing.sm
          })
          .onClick(() => {
            this.onDispatch(new SettingsSectionTapped(entry.key));
          })

          if (index < SETTINGS_ENTRIES.length - 1) {
            Divider()
              .color(T.colors.divider)
              .margin({ left: T.spacing.md })
          }
        }
        .width('100%')
      }, (entry: SettingsEntry) => entry.key)
    }
    .width('100%')
    .backgroundColor(T.colors.backgroundSecondary)
    .borderRadius(T.radius.md)
    .margin({
      left: T.spacing.screenInset,
      right: T.spacing.screenInset,
      top: T.spacing.md,
      bottom: T.spacing.md
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
              .color(T.colors.accent)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.uiState.errorMessage !== null && this.uiState.displayName.length === 0) {
          Column() {
            Text(this.uiState.errorMessage)
              .fontSize(T.typography.body.fontSize)
              .fontColor(T.colors.textSecondary)
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
      .backgroundColor(T.colors.background)

      if (!this.uiState.isLoading && this.uiState.errorMessage === null) {
        Column() {
          Text('✎')
            .fontSize(24)
            .fontColor(T.colors.textOnAccent)
        }
        .width(FAB_SIZE)
        .height(FAB_SIZE)
        .borderRadius(T.radius.full)
        .backgroundColor(T.colors.accent)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.onDispatch(new EditTapped());
        })
        .margin({ right: T.spacing.screenInset, bottom: T.spacing.lg })
      }
    }
    .width('100%')
    .height('100%')
  }
}
