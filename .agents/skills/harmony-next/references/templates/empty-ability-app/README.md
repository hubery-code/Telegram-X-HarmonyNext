# Empty Ability 最小测试工程模板

该目录是可直接复制的 HarmonyOS NEXT Stage 模型 `Empty Ability` 最小工程，用于 agent 在不打开 DevEco Studio 向导的情况下创建测试 fixture。

来源边界：

- 工程结构参考本机 DevEco Studio 模板：
  `/Applications/DevEco-Studio.app/Contents/plugins/openharmony/lib/templates/project/New Project`
- Ability 与页面结构参考本机 DevEco Studio 模板：
  `/Applications/DevEco-Studio.app/Contents/plugins/openharmony/lib/templates/ability/Empty Ability`
- 模板已去除本机签名材料、绝对路径、IDE 缓存和向导占位符。

默认参数：

| 字段 | 值 |
| --- | --- |
| bundleName | `com.example.emptyability` |
| moduleName | `entry` |
| abilityName | `EntryAbility` |
| Compatible SDK | `5.0.0(12)` |
| targetSdkVersion | `5.0.0(12)` |
| modelVersion | `5.0.0` |
| runtimeOS | `HarmonyOS` |
| deviceTypes | `phone`, `tablet`, `2in1` |

复制后至少修改：

1. `AppScope/app.json5` 的 `bundleName`。
2. `AppScope/resources/base/element/string.json` 的 `app_name`。
3. 如需真机构建签名，在目标工程内用 DevEco Studio 或本地签名配置生成 `signingConfigs`，不要把个人签名材料提交到模板。
4. 如需替换应用图标，覆盖 `AppScope/resources/base/media/app_icon.png` 即可。
5. `entry/src/main/module.json5` 的 Ability `icon` 和 `startWindowIcon` 默认复用同一资源。

结构说明：

- `entry/src/main/ets/pages/Index.ets` 只保留 `@Entry` 页面入口，并挂载 `SmokeCounter()`。
- `entry/src/main/ets/components/SmokeCounter.ets` 承载 smoke UI、状态和点击逻辑。
- 页面入口与 smoke 组件解耦后，目标项目可以替换路由页或复用组件，不需要把测试状态逻辑写死在 `entry` 页面里。

基本校验：

```bash
cd <copied-project>
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode module -p module=entry@default assembleHap
```

SDK 版本适配验证：

- 模板默认 SDK 为 `5.0.0(12)`；目标环境需要其他 SDK 时，在复制出的 fixture 内覆盖 `compatibleSdkVersion` 和 `targetSdkVersion`。
- HarmonyOS 6.0.2 / API 22 对应 `6.0.2(22)`。
- 构建时 `DEVECO_SDK_HOME` 指向 SDK 根目录，例如 `/Applications/DevEco-Studio.app/Contents/sdk`，不要指向 `sdk/default`。
- API 22 需要保留 app `icon`、Ability `icon`、`startWindowIcon` 和 `AppScope/resources/base/media/app_icon.png`。

```bash
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk \
  /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
  --mode module -p module=entry@default assembleHap
```

HDC / Emulator smoke：

```bash
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
TARGET="127.0.0.1:10100"
BUNDLE="com.example.emptyability"
ABILITY="EntryAbility"
HAP="$(find entry/build -name '*.hap' | head -1)"

"$HDC" -t "$TARGET" install "$HAP"
"$HDC" -t "$TARGET" shell aa start -b "$BUNDLE" -a "$ABILITY"
"$HDC" -t "$TARGET" shell uitest dumpLayout -p /dev/null -a
"$HDC" -t "$TARGET" shell uitest screenCap -p /dev/null
```

交互 smoke：

1. 从 `dumpLayout` 找到 `smoke-increment` 的 `bounds`。
2. 用 `uitest uiInput click <center-x> <center-y>` 点击按钮。
3. 重新 `dumpLayout`，断言 `tapCount=1` 和 `Harmony Smoke Tapped`。

不同 DevEco/Hvigor 版本的输出路径可能不同。若找不到 HAP，先执行：

```bash
find entry/build -name '*.hap' -print
```
