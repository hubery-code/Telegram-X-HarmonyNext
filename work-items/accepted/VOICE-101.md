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
- **`Index.ets`**：在 `openChat` 时注入适配器与缓存路径，在 `closeChat` 时回收播放器资源。

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
