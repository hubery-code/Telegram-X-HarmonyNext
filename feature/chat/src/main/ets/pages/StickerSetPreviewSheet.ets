/**
 * feature/chat — 贴纸包详情预览弹窗（STICKER-PREVIEW-101）。
 *
 * 对齐 Telegram X `StickerSetWrap` 设计：
 * - 半透明全屏蒙层（scrim）+ 底部圆角抽屉弹窗；
 * - 顶部小胶囊拖拽条 + 贴纸包标题、贴纸数及关闭按钮；
 * - 中间 5 列贴纸网格展示（支持点击贴纸直接发送）；
 * - 底部全宽大按钮：“添加 X 个贴纸” / “移除贴纸包”，带加载 Spinner。
 */

import { LightTheme } from '@tgx/core-design-system';
import { StickerSetPreviewState, StickerSetItem } from '../model/StickerSetPreviewState';

const T = LightTheme;

function toSandboxUri(path: string | null): string {
  if (!path || path.length === 0) {
    return '';
  }
  return path.startsWith('file://') ? path : `file://${path}`;
}

@Component
export struct StickerSetPreviewSheet {
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
          .backgroundColor(T.colors.scrim)
          .onClick(() => {
            this.onClose();
          })

        // 底部内容面板
        Column() {
          // 顶部拖拽手柄条
          Row()
            .width(36)
            .height(4)
            .borderRadius(T.radius.full)
            .backgroundColor(T.colors.divider)
            .margin({ top: T.spacing.sm, bottom: T.spacing.xs })

          // 头部：标题、贴纸数量、关闭按钮
          Row() {
            Column() {
              Text(this.preview.title.length > 0 ? this.preview.title : '贴纸包详情')
                .fontSize(T.typography.headline.fontSize)
                .fontWeight(FontWeight.Bold)
                .fontColor(T.colors.textPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(this.formatSubtitle())
                .fontSize(T.typography.caption.fontSize)
                .fontColor(T.colors.textSecondary)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 右侧关闭按钮
            Row() {
              Image($r('app.media.ic_close'))
                .width(20)
                .height(20)
                .fillColor(T.colors.textSecondary)
            }
            .width(36)
            .height(36)
            .borderRadius(T.radius.full)
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .backgroundColor(T.colors.surfaceVariant)
            .onClick(() => {
              this.onClose();
            })
          }
          .width('100%')
          .padding({ left: T.spacing.md, right: T.spacing.md, top: T.spacing.xs, bottom: T.spacing.sm })

          Divider()
            .color(T.colors.divider)
            .strokeWidth(1)

          // 中间内容区：加载态 / 错误态 / 贴纸网格
          Column() {
            if (this.preview.isLoading && this.preview.stickers.length === 0) {
              Column() {
                LoadingProgress()
                  .width(36)
                  .height(36)
                  .color(T.colors.accent)
                Text('正在加载贴纸包...')
                  .fontSize(T.typography.caption.fontSize)
                  .fontColor(T.colors.textSecondary)
                  .margin({ top: T.spacing.sm })
              }
              .width('100%')
              .height(220)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            } else if (this.preview.errorMessage !== null && this.preview.stickers.length === 0) {
              Column() {
                Text(this.preview.errorMessage)
                  .fontSize(T.typography.body.fontSize)
                  .fontColor(T.colors.destructive)
                Button('重试')
                  .fontSize(T.typography.caption.fontSize)
                  .backgroundColor(T.colors.accent)
                  .margin({ top: T.spacing.sm })
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
                      if (item.localPath !== null && item.localPath.length > 0) {
                        Image(toSandboxUri(item.localPath))
                          .width(52)
                          .height(52)
                          .objectFit(ImageFit.Contain)
                      } else if (item.thumbnailPath !== null && item.thumbnailPath.length > 0) {
                        Image(toSandboxUri(item.thumbnailPath))
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
                    .borderRadius(T.radius.md)
                    .onClick(() => {
                      this.onSelectSticker(item);
                    })
                  }
                }, (item: StickerSetItem) => `${item.id}_${item.localPath ?? ''}`)
              }
              .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
              .rowsGap(T.spacing.xs)
              .columnsGap(T.spacing.xs)
              .padding({
                left: T.spacing.sm,
                right: T.spacing.sm,
                top: T.spacing.sm,
                bottom: T.spacing.sm
              })
              .layoutWeight(1)
              .scrollBar(BarState.Auto)
            }
          }
          .layoutWeight(1)
          .width('100%')

          Divider()
            .color(T.colors.divider)
            .strokeWidth(1)

          // 底部全宽大操作按钮
          Row() {
            Row() {
              if (this.preview.isChanging) {
                LoadingProgress()
                  .width(20)
                  .height(20)
                  .color(this.preview.isInstalled ? T.colors.textPrimary : T.colors.textOnAccent)
                  .margin({ right: T.spacing.sm })
              }
              Text(this.formatButtonLabel())
                .fontSize(T.typography.body.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.preview.isInstalled ? T.colors.destructive : T.colors.textOnAccent)
            }
            .width('100%')
            .height(48)
            .borderRadius(T.radius.full)
            .backgroundColor(this.preview.isInstalled ? T.colors.surfaceVariant : T.colors.accent)
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
            left: T.spacing.md,
            right: T.spacing.md,
            top: T.spacing.sm,
            bottom: T.spacing.md
          })
        }
        .width('100%')
        .constraintSize({ maxHeight: '72%' })
        .backgroundColor(T.colors.surface)
        .borderRadius({
          topLeft: T.radius.lg,
          topRight: T.radius.lg
        })
      }
      .width('100%')
      .height('100%')
    }
  }

  private formatSubtitle(): string {
    if (this.preview === null) {
      return '';
    }
    if (this.preview.isLoading && this.preview.stickers.length === 0) {
      return '正在获取信息...';
    }
    const count: number = this.preview.stickers.length;
    const status: string = this.preview.isInstalled ? '已安装' : '未安装';
    return count > 0 ? `${count} 个贴纸 · ${status}` : status;
  }

  private formatButtonLabel(): string {
    if (this.preview === null) {
      return '';
    }
    if (this.preview.isInstalled) {
      return '移除贴纸包';
    }
    const count: number = this.preview.stickers.length;
    return count > 0 ? `添加 ${count} 个贴纸` : '添加贴纸包';
  }
}
