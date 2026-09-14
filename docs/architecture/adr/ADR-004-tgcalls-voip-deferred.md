# ADR-004 音视频通话 (tgcalls/VoIP) 状态裁决 (CALL-001)

- 状态：Accepted（2026-09-14，GOV-008 / CALL-001）
- 决策者：迁移项目组与架构负责人
- 关联问题：P1-GOV-001, FEAT-FEAS-007, 审计报告 §7 第 10 项

## Context

Telegram X Android 端通话使用 `tgcalls`（基于 WebRTC 定制）并配合 JNI 与底层音频输入输出（`AudioRecordJNI`, `AudioTrackJNI`）。
在 HarmonyOS NEXT 上适配双向音视频通话需要：
1. 移植庞大的 WebRTC/tgcalls C++ 协议栈到 OpenHarmony NDK（涉及 OpenSL ES / OHAudio 替代、H.264/AV1 硬件编解码对接）；
2. 接入 Call Service Kit 与系统电话状态路由；
3. 通话架构相对独立，与文字/媒体消息流的耦合度极低。

## Decision

1. **正式将 FEAT-FEAS-007 (tgcalls 音视频通话) 状态标记为 `Deferred`**；
2. 通话模块保持独立演进流，严禁在具备完整的 C++ NDK 真机 PoC 之前承诺发布日期；
3. 通话功能不作为 MVP-Core 的阻断项，推迟至 Post-MVP（G4 / Beta 阶段）单独立项攻关。

## Consequences

- 剥离通话复杂度，防止庞大的 WebRTC 编译脚本与多媒体流管道拖慢文字/媒体主工程构建；
- MVP-Core 的 Release 产物体积与安全审计范围大幅收窄，交付更加聚焦稳定。
