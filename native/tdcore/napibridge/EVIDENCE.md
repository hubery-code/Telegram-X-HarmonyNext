# BRG-001/002 Evidence — tdcore_napi Node-API bridge

Date: 2026-09-08. Device target: Phone arm64-v8a, HarmonyOS 6.1 (API 24),
hdc target `<device-serial>`.

## 构建证据

- `./tools/ci/build.sh debug` → **BUILD SUCCESSFUL**（entry HAP，
  externalNativeOptions → entry/src/main/cpp → native/tdcore/napibridge）。
- hap：`entry/build/default/outputs/default/entry-default-signed.hap`，
  **42,423,710 B（~40.5 MiB）**。
- hap 内 native 库（unzip -l）：

  | 文件 | 大小 |
  |---|---|
  | libs/arm64-v8a/libtdjson.so | 32,000,736（hvigor DoNativeStrip 后） |
  | libs/arm64-v8a/libtdcore_napi.so | 368,960 |
  | libs/arm64-v8a/libcrypto.so(.3) | 3,477,248 |
  | libs/arm64-v8a/libssl.so(.3) | 595,824 |
  | libs/arm64-v8a/libc++_shared.so | 1,262,504（hvigor STL 默认附带，未被 NEEDED） |

- `llvm-readelf -d libtdcore_napi.so`（打包前 intermediates 副本）：

  ```
  NEEDED libace_napi.z.so   (系统 Node-API runtime)
  NEEDED libtdjson.so       (soname 已修正，非绝对路径)
  NEEDED libcrypto.so.3
  NEEDED libssl.so.3
  NEEDED libc.so
  SONAME libtdcore_napi.so
  ```

- ArkTS 编译仅一条 WARN：`module for 'libtdcore_napi.so' is not verified`
  （缺 .d.ts，功能正常，见 README 已知限制）。

## 真机验证

**STATUS: PASS（2026-09-08 19:34，设备 <device-serial> / VYG-AL00，
HarmonyOS 6.1 API 24）**

```bash
./tools/ci/build.sh debug                 # BUILD SUCCESSFUL
hdc install -r entry-default-signed.hap   # install bundle successfully
hdc shell aa start -a EntryAbility -b org.telegram.x.harmony
hdc shell snapshot_display -f /data/local/tmp/tdx_verify.jpeg
hdc file recv /data/local/tmp/tdx_verify.jpeg .
```

证据截图：`native/tdcore/napibridge/tdx_verify_device.jpeg`
（1280x2832，设备截屏，`/data/local/tmp/tdx_verify.jpeg` 回取）。

截屏原文（页面 onPageShow 自动执行结果，人工核对）：

```
Telegram X HarmonyOS
[TDLib 验证]
TDLib 版本: 1.8.67
execute 结果: {"@type":"textEntities","entities":[{"@type":"textEntity","offset":6,"length":9,"type":{"@type":"textEntityTypeMention"}}]}
createClient/send: clientId=1 (异步响应需 BRG-003 receive)
```

验收映射：

| 验收项 | 证据 |
|---|---|
| BRG-001 模块注册/版本 | ArkTS `import 'libtdcore_napi.so'` 成功加载，`getVersion()` 返回 `1.8.67` |
| BRG-002 create/send/execute | `execute` 同步返回 textEntities JSON；`createClient()` 返回 int32 clientId=1；`send` 无崩溃无副作用 |
| TDN-002 真机验收（应用内路径） | libtdjson.so 真机加载并成功执行同步请求（取代 hdc shell exec 方案） |
| hap 包体 | entry-default-signed.hap = 42,423,710 B（tdjson strip 后 32MB 入包） |
