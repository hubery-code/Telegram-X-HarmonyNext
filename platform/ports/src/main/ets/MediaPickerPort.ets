/**
 * platform/ports — 媒体选择器纯抽象端口（MEDIA-102 / MEDIA-105）。
 *
 * 遵循 ARCH-001 规范，业务 Coordinator 严禁直接依赖系统 PhotoViewPicker 或 CoreFileKit；
 * 同理**取视频帧、读媒体元数据**这类能力（AVImageGenerator / AVMetadataExtractor）也一律
 * 收在 entry 适配器里，端口只暴露结果，业务层拿到的是纯数据。
 * 提供相册图片、通用文件、相册视频三类选取抽象，屏蔽系统 Capability 细节与沙箱差异。
 */

export interface PickedMedia {
  uri: string;
  path?: string;
  name?: string;
  size?: number;
  mimeType?: string;
  /**
   * 视频时长（秒）。仅 pickVideo 尽力填写；取不到时保持 undefined。
   * 对应 TGX data/TD.java 组 InputVideo.duration 的来源。
   */
  duration?: number;
  /** 原始像素宽。仅 pickVideo 尽力填写（来自 AVMetadataExtractor.videoWidth）。 */
  width?: number;
  /** 原始像素高。仅 pickVideo 尽力填写（来自 AVMetadataExtractor.videoHeight）。 */
  height?: number;
  /**
   * 本地生成的缩略图**沙箱物理路径**（JPEG）。
   * 仅 pickVideo 尽力填写：适配器用 AVImageGenerator 抽首帧后转码落盘。
   * 生成失败（模拟器缺编解码器等）时保持 undefined —— 调用方以此为「无缩略图」信号，
   * 回退到 Video 组件首帧占位，不得因此阻断发送。
   */
  thumbnailPath?: string;
  /**
   * 缩略图自身像素宽/高（**不是**视频宽高）。
   * 对应 TDLib `inputThumbnail.width/height`——文档要求「通常不超过 320，未知填 0」。
   * 只有 thumbnailPath 存在时才有意义。
   */
  thumbnailWidth?: number;
  thumbnailHeight?: number;
}

export interface MediaPickerPort {
  /** 调起系统相册选取图片。maxSelectNumber 默认为 1。 */
  pickPhoto(maxSelectNumber?: number): Promise<PickedMedia[]>;

  /** 调起系统文档选择器选取文件。maxSelectNumber 默认为 1。 */
  pickFile(maxSelectNumber?: number): Promise<PickedMedia[]>;

  /** 调起系统相册选取视频。maxSelectNumber 默认为 1。 */
  pickVideo(maxSelectNumber?: number): Promise<PickedMedia[]>;
}
