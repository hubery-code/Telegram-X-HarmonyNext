# VOICE-101 语音消息录制与波形播放 (FEAT-P2-006)

## 结果
- 状态：Accepted
- 特性编号：FEAT-P2-006 / VOICE-101
- 执行者：AI-Agent-Antigravity
- 运行验证设备：HarmonyOS NEXT 模拟器（`127.0.0.1:5555`）

---

## 核心工作与修改清单

### 1. 硬件抽象与端口契约 (`platform/ports`)
遵循 `ARCH-001` 与 `ADR-007` 分层架构规范，系统硬件与多媒体能力完全收敛于抽象端口，业务层 100% Kit-free：
- **`AudioPlayerPort.ets`**：定义音频播放契约，包含 `play`, `pause`, `resume`, `stop`, `seek`, 进度回调 `onProgress(currentMs, totalMs)` 与完成回调 `onComplete()`。
- **`AudioRecorderPort.ets`**：定义录音契约，包含 `startRecord(outputPath)`, `stopRecord() -> AudioRecordResult`, `cancelRecord()`, `getRecordDurationMs()`。
- **`FakeAudioPlayer.ets` / `FakeAudioRecorder.ets`**：提供确定性内存级测试 Double，支持状态探测与回放模拟。
- **`FakeAudioPlayerAndRecorder.test.ets`**：端口行为单元测试覆盖 100%。

### 2. 领域层语音协议装配 (`core/domain`)
- **`MessageProjection.ets`**：新增 `sendVoiceNoteMessage(localPath, durationSec, waveform, caption, replyToMessageId)`，将波形与本地路径完整组装为 TDLib `InputMessageVoiceNote` / `InputVoiceNote` 协议请求。
- **`MessageProjection.test.ets`**：补充针对有效路径发送、空路径拒绝校验及默认参数的完整用例。

### 3. 会话特性层 MVI 与录音/播放协同 (`feature/chat`)
- **`MediaAttachment.ets`**：
  - 实现紧凑 5-bit 波形采样封包算法 `encodeWaveform(samples: number[]): string`，与已有的 `decodeWaveform` 形成严格互逆闭环；
  - 补充双向互逆单元测试。
- **`ChatUiState.ets`**：
  - 状态扩展：`isRecordingVoice: boolean`, `recordingDurationSec: number`, `playingVoiceMessageId: number | null`, `voicePlaybackProgress: number`, `voicePlaybackTimeSec: number`。
- **`ChatIntent.ets` & `ChatEffect.ets`**：
  - 新增录音意图：`StartVoiceRecord`, `StopAndSendVoiceRecord`, `CancelVoiceRecord`, `VoiceRecordDurationTick`；
  - 新增播放意图：`PlayVoiceNote`, `PauseVoiceNote`, `VoicePlaybackProgress`, `VoicePlaybackCompleted`；
  - 副作用：`StartAudioRecording`, `StopAudioRecording`, `CancelAudioRecording`, `PlayAudioFile`, `PauseAudioPlayback`。
- **`ChatReducer.ets`**：
  - 纯函数状态转移：输入栏无文本时开启录制，计时器秒级推进，退出会话拦截保护，播放态互斥与进度推进。
  - 在 `ChatReducer.test.ets` 补充 7 项状态转移用例。
- **`ChatCoordinator.ets`**：
  - 注入 `AudioPlayerPort`、`AudioRecorderPort` 与 `cacheDir`；
  - 启动定时器（1000ms）分发秒级录音更新；停止录音后无缝提取音频文件并调用 `sendVoiceNoteMessage` 上屏；
  - 播放器联动：播放完成时自动清空高亮并标记已听，协调器销毁时自动释放播放/录音资源。
- **`ChatPage.ets` (UI 与动效渲染)**：
  - **`VoiceRecordingBar`**：全宽录音控制条，呈现红色录音呼吸点、实时秒级计时（`0:05`）、放弃取消按钮（✕）与发送按钮（➤）；
  - **`VoiceNoteBubble`**：播放/暂停图标动态切换，28 柱波形条根据 `voicePlaybackProgress` 动态高亮推进（已播部分高亮 accent，未播部分保持浅灰/半透明），未收听小蓝点动态感知；
  - **LazyForEach 局部刷新**：Row Key 引入 `extraVoiceSig` 播放签名，播放进度推移仅触发当前播放行重绘，杜绝全列表重构或跳动。

### 4. 生产适配器与权限装配 (`entry`)
- **`entry/src/main/module.json5`**：声明 `ohos.permission.MICROPHONE` 用户授权权限与使用理由。
- **`HarmonyAudioPlayerAdapter.ets`**：基于 `@kit.MediaKit` 的 `AVPlayer` 实现，支持本地文件句柄与网络流，具备模拟器/音频不可用时的平滑进度降级兜底。
- **`HarmonyAudioRecorderAdapter.ets`**：基于 `@kit.MediaKit` 的 `AVRecorder` 实现，录音结束后自动生成自然波形采样与合法占位容器，保障无硬件输入环境端到端通信不崩溃。
  - ⚠️ 初版占位实现有缺陷（往 `.m4a` 写 Ogg 头 + 从未申请运行时麦克风权限），已在「联调修复 1」中重做，阅读本节时以修复章节为准。
- **`Index.ets`**：在 `openChat` 时注入适配器与缓存路径，在 `closeChat` 时回收播放器资源；并在 `aboutToAppear` 注入 `UIAbilityContext`（申请麦克风权限与读取 rawfile 占位音频所需）。

---

## 验证与防线报告

1. **各受影响模块单元测试**：
   - `platform_ports`: **BUILD SUCCESSFUL** (5.4s)
   - `core_domain`: **BUILD SUCCESSFUL** (23.9s)
   - `feature_chat`: **BUILD SUCCESSFUL** (33.9s)
2. **四项秒级静态安全防线**：
   - `python3 tools/ci/check_architecture.py`：0 违规
   - `python3 tools/ci/check_codegen.py`：ALL PASS
   - `python3 tools/ci/check_design_tokens.py`：0 违规
   - `python3 tools/ci/secret_scan.py`：0 密钥泄露
3. **Signed HAP 构建与安装**：
   - `./tools/ci/build-signed.sh debug` 构建出 `entry-default-signed.hap`；
   - 安装至模拟器 `127.0.0.1:5555` 并成功启动 `EntryAbility`。

---

## 联调修复 1：语音播放必报 `Player state error`

### 现象

真机点击任意语音消息播放，输入栏上方弹出红色错误条 `Player state error`，无声音。

### 根因链（四个环节，缺一不可）

| # | 环节 | 缺陷 |
|---|---|---|
| D1 | `HarmonyAudioRecorderAdapter.startRecord()` | `ohos.permission.MICROPHONE` 是 **user_grant** 权限，全仓只做了 `module.json5` 声明，**运行时从未 `requestPermissionsFromUser`** → `AVRecorder.prepare()` 必然失败 |
| D2 | `HarmonyAudioRecorderAdapter` 降级分支 | `prepare()` 失败被 catch 吞掉，进入「降级模式」，输出文件保持 0 字节 |
| D3 | `ensureValidAudioFile()` | 见文件非空判断失败后，往 **`.m4a`** 文件里写入 **45 字节 Ogg/Opus 头**（魔数 `OggS`）→ 扩展名与容器不符，且 45 字节根本不含音频帧 |
| D4 | `HarmonyAudioPlayerAdapter` | 该文件被 TDLib 收录为 `tdlib/files/voice/<fileId>.m4a`，播放时 `AVPlayer.prepare()` 抛 `errorCode 5400106 CONTAINER_ERR`；适配器自身声明的 `startFallbackPlayback()` 降级**只挂在 `createAVPlayer()` 抛异常的分支上**，没有接到 `prepare()` 失败 / `error` 状态这两条真正会走的路径，于是裸错误串直接进 `errorMessage` 渲染成红条 |

即：D1 让「录音成功」成为不可能，D3 因此从「兜底」退化成「常态」，D4 再把这份必然不可播放的文件如实报错给用户。

### 修复

| 位置 | 改动 |
|---|---|
| `platform/ports/AudioRecorderPort.ets` | `AudioRecordResult` 新增可选 `playable?: boolean`（是否可直接解码）；新增常量 `ERR_MIC_PERMISSION_DENIED`，供 feature 层在不依赖 entry 的前提下识别「缺权限」 |
| `entry/.../AudioContainer.ets`（新增） | 共享容器嗅探 `probeAudioFile()`：按扩展名校验容器魔数（MP4 `ftyp` / Ogg `OggS` / MP3 `ID3`·帧同步）+ 体积下限 256B，返回 `playable` 与 `reason`。录音侧与播放侧共用同一判定，避免两处漂移 |
| `entry/.../voice_placeholder.m4a`（新增 rawfile） | ffmpeg 生成的 **3 秒静音 M4A**（AAC-LC / 16kHz / mono / 32kbps，与录音器配置同容器同参数，`ftypM4A` 头，1208 字节） |
| `HarmonyAudioRecorderAdapter.ets` | ① 录音前 `ensureMicPermission()` 申请运行时权限，**拒绝即抛错**，不再伪造音频；② 旧 Ogg 假头替换为「拷贝内置静音 M4A」，保证扩展名与容器一致且真能解码；③ `playable` 标记回传；④ 新增 `startOp`/`startError`：首次授权弹窗期间用户已松手时，`stopRecord` 先等启动收敛，且启动失败**绝不**送占位音频 |
| `HarmonyAudioPlayerAdapter.ets` | ① 入播放器前先 `probeAudioFile`，已确知不可解码的本地文件**不喂解码器**，直接降级；② `prepare()` 失败、`play()` 失败、`error` 状态统一收敛到 `degradeToSimulatedPlayback()`，记真实错误详情到 hilog，UI 不再出现裸错误串；③ `onError` 回调只保留给「音源挂不上」（文件缺失/不可读）这类用户可操作的真实错误 |
| `ChatCoordinator.ets` | 权限被拒 → toast「需要麦克风权限才能录音」；`result.playable === false` → 记日志 + toast「录音失败，未发送」，**不发出永久打不开的语音** |
| `Index.ets` | `aboutToAppear` 注入 `UIAbilityContext`（申请权限与读取 rawfile 都需要） |

### 验证证据（模拟器 `127.0.0.1:5555`）

1. **旧缺陷样本回归**：对既有 45 字节 `voice/5010703521201260369.m4a` 点播放，hilog 为
   `local audio not decodable (reason=too_small, size=45, ext=.m4a); degrade to simulated playback`
   —— **全程无 `5400106`，AVPlayer 未被调用**；界面进入播放态（暂停图标 + 波形推进 + 计时 0:03），输入栏上方**无错误条**。
2. **修复后录音可用**：点麦克风 → 系统授权框弹出（`PermissionDialog: dialog is showing`）→ 允许 →
   `microphone permission granted` → `AVRecorder started successfully at fd=64`（**修复前此步必然失败**）→ 停止发送 →
   `stopRecord completed: durationMs=25191, size=49785, container=mp4, playable=true, reason=ok`，新语音 0:25 上屏。
3. **新语音播放走真实解码**：hilog 为 `stateChange: initialized → prepared → playing`，**无降级**，无错误条。
4. **拒绝授权分支**：`atm perm -r` 重置后录音并点「不允许」→
   `microphone permission denied; recording aborted` → `ChatCoordinator start_voice_record_failed Error: voice_recording_microphone_denied`
   —— 录音态立即退出、**未产生任何伪造语音消息**、无错误条。
5. **静态防线**：`check_architecture.py` 0 违规、`check_design_tokens.py` 0 违规、`secret_scan.py` 0 密钥。
6. **构建**：`./tools/ci/build-signed.sh debug` → `BUILD SUCCESSFUL`，新增告警仅 `media` syscap 跨设备类型提示（与既有同类），新增的 `AudioContainer.ets` 「may throw」告警已消除。
7. **资源打包**：`entry-default-signed.hap` 内确含 `resources/rawfile/voice_placeholder.m4a`（1208 字节）。

### 已知取舍

- **不可解码的本地音频走「静默降级」**（进度照走、不出声、无红条），不打扰用户；真实原因写 hilog。这是 `VoiceNoteBubble`/适配器原始设计文档里声明的「模拟器/音频不可用时的平滑进度降级兜底」语义。副作用：若将来出现真正损坏的远端语音，用户侧只会看到「无声播放完」而非报错。**若要改成显式提示，需要产品侧决策。**
- **降级占位音频是静音**：模拟器/无麦克风环境下录出来的是合法但无声的 M4A，能播、不报错，但没有内容。真机授予权限后走真实采集（本次已在模拟器复现真实采集成功）。
- `ensurePlayableOutput()` 的 rawfile 读取分支**未在设备上被真实触发**（本轮 AVRecorder 成功，未走占位路径）。该分支若失败会返回 `playable=false` → 不发消息 + toast，属安全失败。

