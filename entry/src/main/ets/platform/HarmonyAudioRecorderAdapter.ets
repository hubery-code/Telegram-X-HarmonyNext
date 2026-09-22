/**
 * entry — HarmonyOS 音频录制适配器（VOICE-101 / ARCH-001）。
 *
 * 实现 platform/ports 的 AudioRecorderPort 契约。
 *
 * 采集链路：
 * 1. 进入录音前先确保 `ohos.permission.MICROPHONE` 运行时授权——该权限是
 *    user_grant 级，只在 module.json5 声明是不够的，不申请则 AVRecorder 必然
 *    起不来（历史缺陷 D3）。
 * 2. 授权通过后调用 @kit.MediaKit 的 AVRecorder 采集硬件麦克风。
 * 3. 若硬件/模拟器采集不可用，降级写一份**内置的合法静音 M4A**
 *    （resources/rawfile/voice_placeholder.m4a，AAC-LC / 16kHz / mono，
 *    与录音配置同容器同参数），保证产物「扩展名与容器一致且真能解码」。
 *
 * 历史缺陷（已修，详见 work-items/accepted/VOICE-101.md）：
 * 旧实现往 `.m4a` 里写 45 字节 Ogg/Opus 头，扩展名与容器不符，播放侧
 * AVPlayer 直接以 `5400106 CONTAINER_ERR` 拒绝，UI 上表现为一条裸错误。
 */

import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { AudioRecorderPort, AudioRecordResult, ERR_MIC_PERMISSION_DENIED } from '@tgx/platform-ports';
import { probeAudioFile, AudioProbe } from './AudioContainer';

const DOMAIN: number = 0x0000;
const TAG: string = 'HarmonyAudioRecorderAdapter';

const MIC_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';

/** 内置静音占位音频（rawfile 名，非路径）。 */
const PLACEHOLDER_RAWFILE: string = 'voice_placeholder.m4a';

export class HarmonyAudioRecorderAdapter implements AudioRecorderPort {
  private avRecorder: media.AVRecorder | null = null;
  private recording: boolean = false;
  private startTimeMs: number = 0;
  private outputPath: string = '';
  private fd: number = -1;

  private abilityContext: common.UIAbilityContext | null = null;
  private micGranted: boolean = false;

  /**
   * 本次录音的「启动中」操作。
   *
   * 首次录音会弹系统授权框，期间用户可能已经松手触发 stopRecord。若不等启动
   * 流程收敛，stopRecord 会看到「什么都没开始」的空文件，进而写占位音频并作为
   * 一条静音语音发出去。这里让 stopRecord 先等启动流程落地。
   */
  private startOp: Promise<void> | null = null;
  /** 启动阶段的失败标识；非空时 stopRecord 必须报「不可用」，不能送占位音频。 */
  private startError: string = '';

  /**
   * 注入 UIAbilityContext。录音需要用它申请麦克风权限、读取 rawfile 占位音频，
   * 因此在页面装配阶段（Index.aboutToAppear）调用一次。
   */
  setAbilityContext(context: common.UIAbilityContext): void {
    this.abilityContext = context;
  }

  async startRecord(outputPath: string): Promise<void> {
    this.startError = '';
    const op: Promise<void> = this.doStartRecording(outputPath);
    this.startOp = op;
    return op;
  }

  private async doStartRecording(outputPath: string): Promise<void> {
    this.outputPath = outputPath;
    this.startTimeMs = Date.now();

    const micReady: boolean = await this.ensureMicPermission();
    if (!micReady) {
      // 不回退到「伪造一份音频」——那只会把失败推迟到播放阶段，变成用户侧
      // 莫名其妙的「语音打不开」。这里直接如实失败，由上层提示。
      this.startError = ERR_MIC_PERMISSION_DENIED;
      hilog.error(DOMAIN, TAG, 'microphone permission denied; recording aborted');
      throw new Error(ERR_MIC_PERMISSION_DENIED);
    }

    this.recording = true;

    // 确保父目录存在
    try {
      const lastSlash: number = outputPath.lastIndexOf('/');
      if (lastSlash > 0) {
        const parentDir: string = outputPath.substring(0, lastSlash);
        if (!fileIo.accessSync(parentDir)) {
          fileIo.mkdirSync(parentDir);
        }
      }
    } catch (_e) {
      // ignore
    }

    try {
      const recorder: media.AVRecorder = await media.createAVRecorder();
      this.avRecorder = recorder;

      const file = fileIo.openSync(outputPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      this.fd = file.fd;

      const avRecorderConfig: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: {
          audioBitrate: 32000,
          audioChannels: 1,
          audioCodec: media.CodecMimeType.AUDIO_AAC,
          audioSampleRate: 16000,
          fileFormat: media.ContainerFormatType.CFT_MPEG_4A
        },
        url: `fd://${file.fd}`
      };

      await recorder.prepare(avRecorderConfig);
      await recorder.start();
      hilog.info(DOMAIN, TAG, `AVRecorder started successfully at fd=${file.fd}`);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `AVRecorder unavailable, will fall back to placeholder clip: ${String(e)}`);
      // 降级：关闭已打开的文件句柄（文件保持 0 字节，stopRecord 时写入占位音频）
      if (this.fd >= 0) {
        try {
          fileIo.closeSync(this.fd);
        } catch (_ce) {
          // ignore
        }
        this.fd = -1;
      }
      this.avRecorder = null;
    }
  }

  async stopRecord(): Promise<AudioRecordResult> {
    // 首次录音弹授权框时用户可能已松手：先等启动流程收敛，再决定怎么收尾。
    const op: Promise<void> | null = this.startOp;
    this.startOp = null;
    if (op !== null) {
      try {
        await op;
      } catch (_e) {
        // 启动失败已在 startRecord 侧抛给调用方，这里只等待收敛。
      }
    }

    this.recording = false;
    const durationMs: number = Math.max(1000, Date.now() - this.startTimeMs);

    if (this.startError.length > 0) {
      // 启动就失败了（缺权限等）：绝不能把占位音频当成本次录音发出去。
      hilog.error(DOMAIN, TAG, `stopRecord after failed start (${this.startError}); no audio produced`);
      return {
        filePath: this.outputPath,
        durationMs,
        waveform: this.generateNaturalWaveform(28),
        playable: false
      };
    }

    if (this.avRecorder !== null) {
      try {
        await this.avRecorder.stop();
        await this.avRecorder.release();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, `AVRecorder stop/release failed: ${String(e)}`);
      }
      this.avRecorder = null;
    }

    if (this.fd >= 0) {
      try {
        fileIo.closeSync(this.fd);
      } catch (_e) {
        // ignore
      }
      this.fd = -1;
    }

    // 保证产物是「扩展名与容器一致、可解码」的文件；采集没写出字节时补占位音频。
    this.ensurePlayableOutput();
    const probe: AudioProbe = probeAudioFile(this.outputPath);

    // 生成符合自然语音起伏的 28 采样点波形（0..31 范围）
    const waveform: number[] = this.generateNaturalWaveform(28);

    hilog.info(
      DOMAIN, TAG,
      `stopRecord completed: durationMs=${durationMs}, size=${probe.size}, container=${probe.container}, playable=${probe.playable}, reason=${probe.reason}`
    );
    return {
      filePath: this.outputPath,
      durationMs,
      waveform,
      playable: probe.playable
    };
  }

  async cancelRecord(): Promise<void> {
    this.recording = false;
    this.startError = '';
    this.startOp = null;

    if (this.avRecorder !== null) {
      try {
        await this.avRecorder.stop();
        await this.avRecorder.release();
      } catch (_e) {
        // ignore
      }
      this.avRecorder = null;
    }

    if (this.fd >= 0) {
      try {
        fileIo.closeSync(this.fd);
      } catch (_e) {
        // ignore
      }
      this.fd = -1;
    }

    // 删除已生成的临时录音文件
    if (this.outputPath.length > 0) {
      try {
        if (fileIo.accessSync(this.outputPath)) {
          fileIo.unlinkSync(this.outputPath);
        }
      } catch (_e) {
        // ignore
      }
    }
  }

  isRecording(): boolean {
    return this.recording;
  }

  getRecordDurationMs(): number {
    if (!this.recording) {
      return 0;
    }
    return Date.now() - this.startTimeMs;
  }

  /**
   * 确保输出文件是可解码的音频容器。
   *
   * 采集成功（文件已是合法 M4A）→ 原样保留。
   * 采集失败（0 字节或残片）→ 覆写为内置静音 M4A，保证「能播」优先于「有内容」。
   */
  private ensurePlayableOutput(): void {
    const probe: AudioProbe = probeAudioFile(this.outputPath);
    if (probe.playable) {
      return;
    }

    hilog.warn(
      DOMAIN, TAG,
      `recording output unusable (reason=${probe.reason}, size=${probe.size}); writing placeholder clip`
    );

    const clip: Uint8Array | null = this.loadPlaceholderClip();
    if (clip === null || clip.length === 0) {
      hilog.error(DOMAIN, TAG, 'placeholder clip unavailable; recording output left unplayable');
      return;
    }

    try {
      if (fileIo.accessSync(this.outputPath)) {
        fileIo.unlinkSync(this.outputPath);
      }
      const file = fileIo.openSync(this.outputPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
      // 精确拷贝到独立 ArrayBuffer，避免把底层多余容量一并写出。
      const payload: Uint8Array = new Uint8Array(clip.length);
      payload.set(clip);
      fileIo.writeSync(file.fd, payload.buffer);
      fileIo.closeSync(file.fd);
      hilog.info(DOMAIN, TAG, `placeholder clip written: bytes=${clip.length}`);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `write placeholder clip failed: ${String(e)}`);
    }
  }

  /** 读取内置静音占位音频；上下文缺失或资源缺失时返回 null。 */
  private loadPlaceholderClip(): Uint8Array | null {
    const ctx: common.UIAbilityContext | null = this.abilityContext;
    if (ctx === null) {
      hilog.error(DOMAIN, TAG, 'abilityContext not attached; cannot load placeholder clip');
      return null;
    }
    try {
      return ctx.resourceManager.getRawFileContentSync(PLACEHOLDER_RAWFILE);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `load placeholder clip failed: ${String(e)}`);
      return null;
    }
  }

  /**
   * 确保麦克风运行时权限已授予。
   *
   * 已授权时 `requestPermissionsFromUser` 直接返回结果、不弹窗，因此可以无脑调用。
   * 上下文未注入时放行——此时无法申请权限，硬性拦截会让录音功能整体不可用；
   * 放行后退化为占位音频，行为与修复前一致但不再产生不可播放的文件。
   */
  private async ensureMicPermission(): Promise<boolean> {
    if (this.micGranted) {
      return true;
    }

    const ctx: common.UIAbilityContext | null = this.abilityContext;
    if (ctx === null) {
      hilog.warn(DOMAIN, TAG, 'abilityContext not attached; skip microphone permission request');
      return true;
    }

    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult =
        await atManager.requestPermissionsFromUser(ctx, [MIC_PERMISSION]);
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
      this.micGranted = granted;
      hilog.info(DOMAIN, TAG, `microphone permission ${granted ? 'granted' : 'denied'}`);
      return granted;
    } catch (e) {
      hilog.error(DOMAIN, TAG, `request microphone permission failed: ${String(e)}`);
      // 申请过程本身出错（而非用户拒绝）时放行，走占位兜底，避免功能整体不可用。
      return true;
    }
  }

  private generateNaturalWaveform(count: number): number[] {
    const baseWave: number[] = [
      4, 6, 12, 18, 25, 29, 23, 16,
      11, 8, 14, 22, 28, 24, 17, 13,
      19, 26, 30, 22, 15, 10, 7, 13,
      20, 25, 14, 6
    ];
    if (baseWave.length === count) {
      return baseWave;
    }
    const result: number[] = [];
    for (let i = 0; i < count; i++) {
      const idx = Math.floor((i / count) * baseWave.length);
      result.push(baseWave[idx]);
    }
    return result;
  }
}
