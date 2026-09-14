/**
 * platform/ports — 媒体选择器纯抽象端口（MEDIA-102）。
 *
 * 遵循 ARCH-001 规范，业务 Coordinator 严禁直接依赖系统 PhotoViewPicker 或 CoreFileKit。
 * 提供相册图片选取与通用文件选取抽象，屏蔽系统 Capability 细节与沙箱差异。
 */

export interface PickedMedia {
  uri: string;
  path?: string;
  name?: string;
  size?: number;
  mimeType?: string;
}

export interface MediaPickerPort {
  /** 调起系统相册选取图片。maxSelectNumber 默认为 1。 */
  pickPhoto(maxSelectNumber?: number): Promise<PickedMedia[]>;

  /** 调起系统文档选择器选取文件。maxSelectNumber 默认为 1。 */
  pickFile(maxSelectNumber?: number): Promise<PickedMedia[]>;
}
