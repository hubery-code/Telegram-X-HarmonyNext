/**
 * feature/chat — 贴纸包详情预览弹窗（STICKER-PREVIEW-101）。
 *
 * 对齐 Telegram X `StickerSetWrap` 设计：
 * - 半透明全屏蒙层（scrim）+ 底部圆角抽屉弹窗；
 * - 顶部小胶囊拖拽条 + 贴纸包标题、贴纸数及关闭按钮；
 * - 中间 5 列贴纸网格展示（支持点击贴纸直接发送）；
 * - 底部全宽大按钮：“添加 X 个贴纸” / “移除贴纸包”，带加载 Spinner。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { A11y, a11y, Lang, SupportedLanguage } from '@tgx/core-common';
import { StickerSetPreviewState, StickerSetItem } from '../model/StickerSetPreviewState';
import { stickerCellImagePath } from '../model/StickerBoard';


function toSandboxUri(path: string | null): string {
  if (!path || path.length === 0) {
    return '';
  }
  return path.startsWith('file://') ? path : `file://${path}`;
}

@Component
export struct StickerSetPreviewSheet {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
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
  @Prop preview: StickerSetPreviewState | null = null;
  onClose: () => void = () => {};
  onInstall: (setId: string) => void = () => {};
  onUninstall: (setId: string) => void = () => {};
  onSelectSticker: (item: StickerSetItem) => void = () => {};
  onRetry: (setId: string) => void = () => {};

  build() {
    if (this.preview !== null) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 背景半透明遮罩，点击外部收起
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.T.colors.scrim)
          .onClick(() => {
            this.onClose();
          })

        // 底部内容面板
        Column() {
          // 顶部拖拽手柄条
          Row()
            .width(36)
            .height(4)
            .borderRadius(this.T.radius.full)
            .backgroundColor(this.T.colors.divider)
            .margin({ top: this.T.spacing.sm, bottom: this.T.spacing.xs })

          // 头部：标题、贴纸数量、关闭按钮
          Row() {
            Column() {
              Text(this.preview.title.length > 0 ? this.preview.title : this.t('Sticker Set Details'))
                .fontSize(this.T.typography.headline.fontSize)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.T.colors.textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(this.formatSubtitle())
                .fontSize(this.T.typography.caption.fontSize)
                .fontColor(this.T.colors.textSecondary)
                .margin({ top: 2 })
            }
            .accessibilityGroup(true)
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 右侧关闭按钮
            Row() {
              Image($r('app.media.ic_close'))
                .width(20)
                .height(20)
                .fillColor(this.T.colors.textSecondary)
            }
            .width(36)
            .height(36)
            .borderRadius(this.T.radius.full)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor(this.T.colors.surfaceVariant)
            .accessibilityText(a11y(A11y.CLOSE))
            .onClick(() => {
              this.onClose();
            })
          }
          .width('100%')
          .padding({ left: this.T.spacing.md, right: this.T.spacing.md, top: this.T.spacing.xs, bottom: this.T.spacing.sm })

          Divider()
            .color(this.T.colors.divider)
            .strokeWidth(1)

          // 中间内容区：加载态 / 错误态 / 贴纸网格
          Column() {
            if (this.preview.isLoading && this.preview.stickers.length === 0) {
              Column() {
                LoadingProgress()
                  .width(36)
                  .height(36)
                  .color(this.T.colors.accent)
                Text(this.t('Loading sticker set…'))
                  .fontSize(this.T.typography.caption.fontSize)
                  .fontColor(this.T.colors.textSecondary)
                  .margin({ top: this.T.spacing.sm })
              }
              .width('100%')
              .height(220)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else if (this.preview.errorMessage !== null && this.preview.stickers.length === 0) {
              Column() {
                Text(this.t('Failed to load the sticker set. Please try again later.'))
                  .fontSize(this.T.typography.body.fontSize)
                  .fontColor(this.T.colors.destructive)
                Button(this.t('Retry'))
                  .fontSize(this.T.typography.caption.fontSize)
                  .backgroundColor(this.T.colors.accent)
                  .margin({ top: this.T.spacing.sm })
                  .onClick(() => {
                    if (this.preview !== null) {
                      this.onRetry(this.preview.setId);
                    }
                  })
              }
              .width('100%')
              .height(200)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else {
              Grid() {
                ForEach(this.preview.stickers, (item: StickerSetItem) => {
                  GridItem() {
                    Row() {
                      if (stickerCellImagePath(item) !== null) {
                        Image(toSandboxUri(stickerCellImagePath(item)))
                          .width(52)
                          .height(52)
                          .objectFit(ImageFit.Contain)
                      } else {
                        Text(item.emoji.length > 0 ? item.emoji : '⭐️')
                          .fontSize(32)
                      }
                    }
                    .width('100%')
                    .height(68)
                    .justifyContent(FlexAlign.Center)
                    .alignItems(VerticalAlign.Center)
                    .borderRadius(this.T.radius.md)
                    .accessibilityText(a11y(A11y.BOARD_CELL, item.emoji))
                    .onClick(() => {
                      this.onSelectSticker(item);
                    })
                  }
                }, (item: StickerSetItem) => `${item.id}_${stickerCellImagePath(item) ?? ''}`)
              }
              .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
              .rowsGap(this.T.spacing.xs)
              .columnsGap(this.T.spacing.xs)
              .padding({
                left: this.T.spacing.sm,
                right: this.T.spacing.sm,
                top: this.T.spacing.sm,
                bottom: this.T.spacing.sm
              })
              .layoutWeight(1)
              .scrollBar(BarState.Auto)
            }
          }
          .layoutWeight(1)
          .width('100%')

          Divider()
            .color(this.T.colors.divider)
            .strokeWidth(1)

          // 底部全宽大操作按钮
          Row() {
            Row() {
              if (this.preview.isChanging) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(this.preview.isInstalled ? this.T.colors.textPrimary : this.T.colors.textOnAccent)
                  .margin({ right: this.T.spacing.sm })
              }
              Text(this.formatButtonLabel())
                .fontSize(this.T.typography.body.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.preview.isInstalled ? this.T.colors.destructive : this.T.colors.textOnAccent)
            }
            .width('100%')
            .height(48)
            .borderRadius(this.T.radius.full)
            .backgroundColor(this.preview.isInstalled ? this.T.colors.surfaceVariant : this.T.colors.accent)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              if (this.preview === null || this.preview.isChanging) {
                return;
              }
              if (this.preview.isInstalled) {
                this.onUninstall(this.preview.setId);
              } else {
                this.onInstall(this.preview.setId);
              }
            })
          }
          .width('100%')
          .padding({
            left: this.T.spacing.md,
            right: this.T.spacing.md,
            top: this.T.spacing.sm,
            bottom: this.T.spacing.md
          })
        }
        .width('100%')
        .constraintSize({ maxHeight: '72%' })
        .backgroundColor(this.T.colors.surface)
        .borderRadius({
          topLeft: this.T.radius.lg,
          topRight: this.T.radius.lg
        })
      }
      .width('100%')
      .height('100%')
    }
  }

  private t(key: string, ...args: (string | number)[]): string {
    const langCode: SupportedLanguage = this.effectiveLanguage === 'zh' ? 'zh' : 'en';
    return Lang.getInstance().formatByKey(key, langCode, args);
  }

  private formatSubtitle(): string {
    if (this.preview === null) {
      return '';
    }
    if (this.preview.isLoading && this.preview.stickers.length === 0) {
      return this.t('Fetching info…');
    }
    const count: number = this.preview.stickers.length;
    const status: string = this.preview.isInstalled ? this.t('Installed') : this.t('Not installed');
    return count > 0 ? this.t('{0} stickers · {1}', count, status) : status;
  }

  private formatButtonLabel(): string {
    if (this.preview === null) {
      return '';
    }
    if (this.preview.isInstalled) {
      return this.t('Remove Sticker Set');
    }
    const count: number = this.preview.stickers.length;
    return count > 0 ? this.t('Add {0} stickers', count) : this.t('Add Sticker Set');
  }
}
