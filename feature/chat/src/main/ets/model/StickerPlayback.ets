/**
 * feature/chat — 动效贴纸的播放态记账（TGS-102）。纯逻辑，不碰 Kit。
 *
 * 要解决的问题：会话里的一条贴纸**发出去那张不动**。根因不是解码，是行重建 ——
 * `messageRowKey` 里带了 `sendState` / `isRead` / 媒体进度（MSG-104 的教训：不带就不重绘），
 * 而发消息恰好会连着改这几样，于是 `AnimatedSticker` 在几十到几百毫秒里被反复销毁重建
 * （设备实测：一个实例创建 110ms 后就被 destroy，日志 `playing 0 times`）。
 * 组件重建 = 画布换一个新的 `CanvasRenderingContext2D`，lottie 实例绑在旧上下文上，
 * 只能重建；而重建默认**从第 0 帧重来** —— 每 150ms 重建一次就永远停在开头，
 * 观感就是「这张贴纸是静止的」。
 *
 * 所以这里记的是**播放头**而不是实例：每次重建按消息 id 查回上一次播到哪一帧，
 * 从那一帧继续。不试图让行不重建（那是把 MSG-104 修回去），也不指望 lottie 换容器
 * （它的 `loadAnimation` 只有「新建」，没有 re-target）。
 *
 * 三条刻意的取舍：
 * 1. **记账不进 `UiState`**：播放头每帧都在变，进了状态就会参与行签名 → 自己触发重建 →
 *    无限循环。它是视图事实，不是应用事实。
 * 2. **新鲜度窗口**：一条记录只在「最后一次推进后的 `RESUME_WINDOW_MS` 内」被采信。
 *    发消息的重建全都挤在几百毫秒里，窗口内必然命中；而滑走再滑回来已经过了窗口，
 *    于是**重新播一遍** —— 与 Android「贴纸重新入镜会再演一次」一致。
 *    没有这一层，一条播完的贴纸会永远停在末帧。
 * 3. **身份用 `messageId` 而不是 fileId**：动效贴纸的整档在 TDLib 里是**贴纸包共享**的
 *    同一个 File，同一个包同一张贴纸的多条消息 fileId 相同，按它记账会变成「第二条起都不播」。
 *    代价是发消息时临时 id 换真实 id 会重头演 —— 那正是窗口内为数不多的一次全新挂载，
 *    用户要的是「发出去这张演一遍」，不是「从半帧接着演」。
 */

/** 一次挂载该怎么演。 */
export type StickerPlayMode = 'first' | 'resume' | 'finished';

/** 超过这个时长没有新推进，记录就不再采信（重新入镜按首演处理）。 */
export const RESUME_WINDOW_MS: number = 1500;

/** 记账条数上限：只保留最近挂载过的那些气泡，超出按最旧的先淘汰。 */
export const PLAYBACK_LEDGER_LIMIT: number = 128;

/** 一条贴纸气泡的播放记录。 */
export class StickerPlayRecord {
  /** 最后一次推进到的帧号（lottie `enterFrame` 的 `currentTime`，浮点）。 */
  frame: number;
  /** 是否已经演完一遍（`loop: false` 下的 `complete`）。 */
  finished: boolean;
  /** 最后一次推进的时刻，用于新鲜度判定。 */
  lastTouchAt: number;

  constructor(frame: number, finished: boolean, lastTouchAt: number) {
    this.frame = frame;
    this.finished = finished;
    this.lastTouchAt = lastTouchAt;
  }
}

/** 挂载决策：怎么演 + 从哪一帧起（`first` 时 frame 恒为 0）。 */
export class StickerPlayPlan {
  readonly mode: StickerPlayMode;
  readonly frame: number;

  constructor(mode: StickerPlayMode, frame: number = 0) {
    this.mode = mode;
    this.frame = frame;
  }
}

/**
 * 纯决策：有记录且在窗口内才谈得上续播/停末帧，否则首演。
 * 拆成函数是为了让「窗口」这条规则可测 —— 时钟由调用方给，不读 `Date.now`。
 */
export function stickerPlayPlan(
  record: StickerPlayRecord | null,
  now: number,
  windowMs: number = RESUME_WINDOW_MS
): StickerPlayPlan {
  if (record === null || now - record.lastTouchAt > windowMs) {
    return new StickerPlayPlan('first');
  }
  if (record.finished) {
    return new StickerPlayPlan('finished', record.frame);
  }
  return new StickerPlayPlan('resume', record.frame);
}

/**
 * 进程内的播放态账本，key 是 `messageId` 的字符串形式。
 *
 * 空 key（拿不到消息 id 的桩渲染）一律当首演且不写账：宁多播一次，不可错认成别人的进度。
 * 淘汰顺序按「最近推进」，所以另存一条 key 顺序链 —— Map 的迭代顺序在 ArkTS 里
 * 不是这里愿意押的东西，显式数组一眼看得清。
 */
export class StickerPlaybackLedger {
  private readonly records: Map<string, StickerPlayRecord> = new Map<string, StickerPlayRecord>();
  private readonly order: string[] = [];
  private readonly limit: number;

  constructor(limit: number = PLAYBACK_LEDGER_LIMIT) {
    this.limit = limit;
  }

  get(key: string | null): StickerPlayRecord | null {
    if (key === null || key.length === 0) {
      return null;
    }
    const found: StickerPlayRecord | undefined = this.records.get(key);
    return found === undefined ? null : found;
  }

  plan(key: string | null, now: number): StickerPlayPlan {
    return stickerPlayPlan(this.get(key), now);
  }

  /** 记录推进到的帧；已演完的记录只刷新时刻，不被帧回调往回拽。 */
  noteFrame(key: string | null, frame: number, now: number): void {
    if (key === null || key.length === 0) {
      return;
    }
    const previous: StickerPlayRecord | undefined = this.records.get(key);
    if (previous === undefined) {
      this.evictIfNeeded();
      this.records.set(key, new StickerPlayRecord(frame, false, now));
      this.order.push(key);
      return;
    }
    if (!previous.finished) {
      previous.frame = frame;
    }
    previous.lastTouchAt = now;
    this.touchTail(key);
  }

  noteFinished(key: string | null, frame: number, now: number): void {
    if (key === null || key.length === 0) {
      return;
    }
    const previous: StickerPlayRecord | undefined = this.records.get(key);
    if (previous === undefined) {
      this.evictIfNeeded();
      this.records.set(key, new StickerPlayRecord(frame, true, now));
      this.order.push(key);
      return;
    }
    previous.finished = true;
    // `complete` 时读到的 currentFrame 才是真正停下的位置，比最后一次 enterFrame 更准
    previous.frame = frame;
    previous.lastTouchAt = now;
    this.touchTail(key);
  }

  size(): number {
    return this.records.size;
  }

  clear(): void {
    this.records.clear();
    this.order.splice(0, this.order.length);
  }

  private touchTail(key: string): void {
    const at: number = this.order.indexOf(key);
    if (at >= 0) {
      this.order.splice(at, 1);
    }
    this.order.push(key);
  }

  private evictIfNeeded(): void {
    while (this.records.size >= this.limit && this.order.length > 0) {
      const oldest: string | undefined = this.order.shift();
      if (oldest === undefined) {
        return;
      }
      this.records.delete(oldest);
    }
  }
}

/**
 * 全会话共享的那一本账。
 * 组件每次挂载查一次、每帧写一次；会话切换不清（跨会话的同一条消息重进还该续上，
 * 而窗口过期会自动把它降回首演）。
 */
export const stickerPlaybackLedger: StickerPlaybackLedger = new StickerPlaybackLedger();
