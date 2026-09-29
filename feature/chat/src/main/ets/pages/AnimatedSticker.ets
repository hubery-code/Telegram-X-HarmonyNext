/**
 * feature/chat — 动效贴纸（TGS/Lottie）的画布宿主（TGS-101 / TGS-102 / TGS-103）。
 *
 * 只做三件事：把 `.tgs` 交给注入的解码口换成 Lottie JSON 文本 → 在 `Canvas` 上挂一个
 * lottie 实例 → 组件销毁时把这个实例摘掉。「这条贴纸算不算动效」不在这里，
 * 是 `stickerAnimationTgsPath` 的判定。
 *
 * 五条不显然的约束：
 * 1. **加载只能在 `Canvas.onReady` 之后**（此时画布尺寸才确定，早挂会按 0×0 算视口）；
 * 2. **喂 `animationData` 而不是 `path`**：lottie 的沙盒分支要 `getContext().filesDir`
 *    （在它的异步装载里能不能拿到 context 我们赌不起），而 `animationData` 分支
 *    直接进 `setupAnimation`，零文件 IO。代价是这里要自己 `JSON.parse` 一次。
 * 3. **动画挂上之前底下要垫静态缩略图** —— 这一档在 TGS 之前就是贴纸气泡的唯一画法，
 *    解码失败时必须退回它，而不是画一块空白（STICKER-MSG-101 的教训：气泡只剩时间戳）；
 * 4. **`autoSkip` 关**：lottie 默认会跳过它判定为不可见的画布，而会话里的贴纸在
 *    `LazyForEach` 里，可见性判定慢一步就是一片空白（官方 README 同样建议首帧空白时关掉）。
 * 5. **挂载前先查播放账本**（TGS-102）：行重建会把实例连着画布一起换掉，
 *    从头演就等于「发消息那几百毫秒里永远停在开头」。账本给两种走法：
 *    首演 `autoplay: true`；续播 `autoplay: false` + `goToAndPlay(frame)`。
 *    帧号一律取账本里记着的实际推进值，不去猜 `totalFrames`（各档贴纸的 first/last 帧不保证是 0/N-1）。
 * 6. **循环播**（TGS-103）：对齐 Android 默认口径，贴纸不是一次性动画。于是也就没有
 *    「演完停在末帧」这一档 —— 账本里那条 `finished` 随之删除，`complete` 不再监听。
 *
 * 一个组件一个 lottie 实例，实例名用进程内自增序号（`lottie.destroy(name)` 按名释放，
 * 重名会互相踢掉）；`aboutToDisappear` 里必须释放，否则 LazyForEach 回收气泡后
 * 动画还在后台逐帧画。
 */

import lottie, { AnimationItem, BMEnterFrameEvent } from '@ohos/lottie';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppError, Result } from '@tgx/core-common';
import { TgsDecoderPort } from '@tgx/platform-ports';
import { stickerPlaybackLedger, StickerPlayPlan } from '../model/StickerPlayback';

const DOMAIN: number = 0x0000;
const TAG: string = 'AnimatedSticker';

/** 进程内自增的动画实例名序号。 */
let animationSeq: number = 0;

@Component
export struct AnimatedSticker {
  /**
   * 非 @Prop：这几样在一条气泡的生命周期内不换（换了整块重建）；
   * 更重要的是解码口与动画数据都不是可观察状态，挂 @Prop 只会让 ArkUI 深拷贝判等白花力气。
   */
  tgsPath: string | null = null;
  decoder: TgsDecoderPort | null = null;
  /** 动画挂上之前垫在下面的静态缩略图（已是 `file://` 口径的 uri）。 */
  fallbackUri: string | null = null;
  /** 播放账本的 key（消息 id 的字符串形式）；空则不记账、每次首演。 */
  playbackKey: string | null = null;
  /** 动画是否已经挂上；决定缩略图还在不在屏幕上。 */
  @State private animated: boolean = false;
  /** 第一圈的取证日志只落一次。 */
  private lapLogged: boolean = false;

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
        return;
      }
      hilog.warn(DOMAIN, TAG, 'tgs_decode_fail name=%{public}s', this.instanceName);
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
    const plan: StickerPlayPlan = stickerPlaybackLedger.plan(this.playbackKey, Date.now());
    // 一次挂载一条：设备取证就靠这行看「重建之后播放头有没有往前走」
    // （连续几条 plan=resume 且 frame 递增 = 续上了；反复 plan=first = 从头鬼打墙）。
    hilog.info(DOMAIN, TAG, 'tgs_mount key=%{public}s plan=%{public}s frame=%{public}s name=%{public}s',
      this.playbackKey === null ? '-' : this.playbackKey, plan.mode, `${plan.frame}`, this.instanceName);
    // 抗锯齿：lottie 文档明确建议开，否则动图边缘锯齿明显。
    this.ctx.imageSmoothingEnabled = true;
    this.ctx.imageSmoothingQuality = 'medium';
    this.item = lottie.loadAnimation({
      container: this.ctx,
      renderer: 'canvas',
      // TGS-103：循环播。这是 Android 的默认口径（`TGMessageSticker.java:121-130` 的
      // `setPlayOnce(...)` 在「不循环」设置项关闭且不是骰子/动效 emoji 时恒为 false）。
      // 之前这里写死 `false`，观感差在**贴纸演一遍就停在末帧不动**，而真机上的 Telegram X 一直在动。
      loop: true,
      // 首演交给 autoplay 起步；续播要先落位再走，交给 autoplay 会先闪一帧 0 号帧。
      autoplay: plan.mode === 'first',
      autoSkip: false,
      name: this.instanceName,
      contentMode: 'Contain',
      animationData: data
    });
    this.item.addEventListener('DOMLoaded', (): void => {
      // 缩略图交班给画布：落位必须先于撤图，否则续播会闪一下 0 号帧。
      this.seekToPlan(plan);
      this.animated = true;
    });
    this.item.addEventListener('enterFrame', (e: BMEnterFrameEvent): void => {
      stickerPlaybackLedger.noteFrame(this.playbackKey, e.currentTime, Date.now());
    });
    // 取证用：只在**第一圈**落一条。循环播的唯一外部可观察证据就是「走完了第一圈还在走第二圈」
    // —— 改前这里是 `complete`（一次就没了），而每圈都落会变成刷屏日志。
    this.item.addEventListener('loopComplete', (): void => {
      if (this.lapLogged) {
        return;
      }
      this.lapLogged = true;
      const item: AnimationItem | null = this.item;
      hilog.info(DOMAIN, TAG, 'tgs_lap key=%{public}s name=%{public}s frame=%{public}s',
        this.playbackKey === null ? '-' : this.playbackKey, this.instanceName,
        item === null ? '-' : `${item.currentFrame}`);
    });
  }

  /** 按账本给的位置落位；落不完也不影响动画本身（最差是从头演）。 */
  private seekToPlan(plan: StickerPlayPlan): void {
    const item: AnimationItem | null = this.item;
    if (item === null || plan.mode === 'first') {
      return;
    }
    item.goToAndPlay(plan.frame, true);
  }

  private release(): void {
    if (this.item === null) {
      return;
    }
    lottie.destroy(this.instanceName);
    this.item = null;
  }
}
