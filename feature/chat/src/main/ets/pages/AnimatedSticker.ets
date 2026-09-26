/**
 * feature/chat — 动效贴纸（TGS/Lottie）的画布宿主（TGS-101）。
 *
 * 只做三件事：把 `.tgs` 交给注入的解码口换成 Lottie JSON 文本 → 在 `Canvas` 上挂一个
 * lottie 实例 → 组件销毁时把这个实例摘掉。「这条贴纸算不算动效」不在这里，
 * 是 `stickerAnimationTgsPath` 的判定。
 *
 * 四条不显然的约束：
 * 1. **加载只能在 `Canvas.onReady` 之后**（此时画布尺寸才确定，早挂会按 0×0 算视口）；
 * 2. **喂 `animationData` 而不是 `path`**：lottie 的沙盒分支要 `getContext().filesDir`
 *    （在它的异步装载里能不能拿到 context 我们赌不起），而 `animationData` 分支
 *    直接进 `setupAnimation`，零文件 IO。代价是这里要自己 `JSON.parse` 一次。
 * 3. **动画挂上之前底下要垫静态缩略图** —— 这一档在 TGS 之前就是贴纸气泡的唯一画法，
 *    解码失败时必须退回它，而不是画一块空白（STICKER-MSG-101 的教训：气泡只剩时间戳）；
 * 4. **`autoSkip` 关**：lottie 默认会跳过它判定为不可见的画布，而会话里的贴纸在
 *    `LazyForEach` 里，可见性判定慢一步就是一片空白（官方 README 同样建议首帧空白时关掉）。
 *
 * 一个组件一个 lottie 实例，实例名用进程内自增序号（`lottie.destroy(name)` 按名释放，
 * 重名会互相踢掉）；`aboutToDisappear` 里必须释放，否则 LazyForEach 回收气泡后
 * 动画还在后台逐帧画。
 */

import lottie, { AnimationItem } from '@ohos/lottie';
import { AppError, Result } from '@tgx/core-common';
import { TgsDecoderPort } from '@tgx/platform-ports';

/** 进程内自增的动画实例名序号。 */
let animationSeq: number = 0;

@Component
export struct AnimatedSticker {
  /**
   * 非 @Prop：这三样在一条气泡的生命周期内不换（换了整块重建）；
   * 更重要的是解码口与动画数据都不是可观察状态，挂 @Prop 只会让 ArkUI 深拷贝判等白花力气。
   */
  tgsPath: string | null = null;
  decoder: TgsDecoderPort | null = null;
  /** 动画挂上之前垫在下面的静态缩略图（已是 `file://` 口径的 uri）。 */
  fallbackUri: string | null = null;
  /** 动画是否已经挂上；决定缩略图还在不在屏幕上。 */
  @State private animated: boolean = false;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private item: AnimationItem | null = null;
  private readonly instanceName: string = `tgs-${(animationSeq += 1)}`;

  aboutToDisappear(): void {
    this.release();
  }

  build() {
    Stack() {
      if (!this.animated && this.fallbackUri !== null) {
        Image(this.fallbackUri)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
      }
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.attach();
        })
    }
    .width('100%')
    .height('100%')
  }

  /** 画布就绪：拿 JSON 文本，回来再挂动画；拿不到就永远停在缩略图那一档。 */
  private attach(): void {
    if (this.item !== null) {
      return;
    }
    const path: string | null = this.tgsPath;
    const decoder: TgsDecoderPort | null = this.decoder;
    if (path === null || decoder === null) {
      return;
    }
    decoder.decode(path).then((res: Result<string, AppError>) => {
      if (res.ok) {
        this.load(res.value);
      }
    });
  }

  private load(jsonText: string): void {
    if (this.item !== null) {
      return;
    }
    let data: Object | null = null;
    try {
      data = JSON.parse(jsonText);
    } catch (e) {
      // 解码口只保证「以 { 开头」，语法坏掉是有可能的（TDLib 回收了一半的文件）。
      // 这里不炸出去：缩略图还垫着，气泡回到 TGS 之前的画法。
      return;
    }
    // 抗锯齿：lottie 文档明确建议开，否则动图边缘锯齿明显。
    this.ctx.imageSmoothingEnabled = true;
    this.ctx.imageSmoothingQuality = 'medium';
    this.item = lottie.loadAnimation({
      container: this.ctx,
      renderer: 'canvas',
      loop: false,
      autoplay: true,
      autoSkip: false,
      name: this.instanceName,
      contentMode: 'Contain',
      animationData: data
    });
    this.item.addEventListener('DOMLoaded', (): void => {
      this.animated = true;
    });
    // 播完停在末帧；失败与取消都不在这里管（缩略图已经撤了，回不去是故意的：
    // 半途切回静态图会闪，而 lottie 停在末帧仍是这张图的一帧）。
  }

  private release(): void {
    if (this.item === null) {
      return;
    }
    lottie.destroy(this.instanceName);
    this.item = null;
  }
}
