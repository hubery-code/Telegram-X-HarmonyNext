# BRG-003/004 Evidence — receive 线程 + TSFN + 有界队列/背压

Date: 2026-09-08. Device target: VYG-AL00 / hdc 6XE0225A27023538,
HarmonyOS 6.1 (API 24).

> 历史证据（BRG-001/002，2026-09-08 19:34 PASS）：截图
> `tdx_verify_device.jpeg`，页面显示 `TDLib 版本: 1.8.67`、
> `execute 结果: {"@type":"textEntities",...}`、
> `createClient/send: clientId=1`；hap 42,423,710 B。详见 git 历史或
> 主会话记录，本节不重复展开。

## 构建与 CI

- `./tools/ci/ci.sh` → **ALL STEPS PASSED**（toolchain gate、secret scan、
  lint/typecheck、unit test、debug + release assembleHap）。
- hap：`entry/build/default/outputs/default/entry-default-signed.hap`
  = 38,466,863 B。
- 原生侧：`native/tdcore/napibridge/src/tdcore_napi.cpp` 新增
  `subscribeUpdates` / `unsubscribe` / `getMetrics`（napi 模块
  `tdcore_napi`，BRG-001/002 接口保持不变）。
- ArkTS 侧：`entry/src/main/ets/tdbridge/TdBridge.ts`（临时封装，
  sequence 字符串 → bigint）；`entry/src/main/ets/pages/Index.ets`
  订阅验证（aboutToAppear 自动执行 + 按钮手动触发 + 指标/退订按钮）。

## 事件管线（§5.4）

td_receive 线程(100ms 轮询) → per-client 单调 sequence → 有界队列
(1024, 满则阻塞 receive 线程并计 overflowWaitCount, 语义事件绝不丢弃) →
TSFN 空唤醒 → ArkTS 线程批量出队、逐事件扇出到各订阅 sink。

## 真机验证

<!-- DEVICE-RESULT -->

**STATUS: pending — 构建与 CI 全部完成时设备未连接（hdc [Empty]），
hap 已就绪；设备出现后即执行下列命令并回填本节。**

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
$HDC install -r entry/build/default/outputs/default/entry-default-signed.hap
$HDC shell aa start -a EntryAbility -b org.telegram.x.harmony
sleep 6
$HDC shell snapshot_display -f /data/local/tmp/tdx_brg003.jpeg
$HDC file recv /data/local/tmp/tdx_brg003.jpeg .
# 销毁安全: 多次 force-stop + 冷启动
$HDC shell aa force-stop org.telegram.x.harmony
$HDC shell aa start -a EntryAbility -b org.telegram.x.harmony
sleep 6
$HDC shell snapshot_display -f /data/local/tmp/tdx_brg003_restart.jpeg
$HDC file recv /data/local/tmp/tdx_brg003_restart.jpeg .
```

预期页面（人工核对项）：

- `收到请求响应: clientId=N sequence=K @type=option`（getOption version
  的异步响应，证明 receive 线程 + TSFN + 保序全链路通）
- 最近事件列表含 `updateAuthorizationState`（首个 send 触发 Td actor
  创建）和 `option` 响应，sequence 连续
- 指标行：`dropped=0 subs=1 running=true`；退订后
  `subs=0 running=false`
