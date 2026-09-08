# core/design_system（UI-001）

设计 token / theme 库：语义色彩（深浅两套）、排版、间距、圆角、动画，Theme 结构与 token 解析入口，fontScale 适配。**纯 ArkTS**：不依赖任何 Kit（无 ArkUI import）、不依赖 entry、无 IO，可在本地单测中完整验证。

模块名 `core_design_system`，包名 `@tgx/core-design-system`。

## 对外 API（`src/main/ets/Index.ets` 全量导出）

| 类别 | 内容 |
|---|---|
| 色彩 | `ColorTokens`（interface extends Record）、`LightColors` / `DarkColors`、`COLOR_TOKEN_NAMES`、`isColorTokenValue()` |
| 排版 | `TextStyle`、`TypographyTokens`、`DefaultTypography`、`FontWeights`、`TYPOGRAPHY_TOKEN_NAMES` |
| 间距 / 圆角 / 动画 | `SpacingTokens` / `RadiusTokens` / `MotionTokens` 及 `Default*` 常量、`*_TOKEN_NAMES` |
| 字体缩放 | `clampFontScale()`、`scaleTextStyle()`、`scaleTypography()`、`FONT_SCALE_MIN/MAX`、`MIN_READABLE_FONT_SIZE` |
| Theme | `Theme`、`ThemeMode`、`createTheme(mode, fontScale?)`、`LightTheme`、`DarkTheme`、`scaledTypography(theme)`、`scaledTextStyle(theme, name)`、`resolveToken(theme, dottedName)`、`tokenNames(namespace)` |

## Token 命名规范

- **语义名，禁止裸色值**：组件只引用 `colors.background`、`colors.textPrimary` 这类语义 token；色值只允许出现在 `Colors.ets` 的 `LightColors`/`DarkColors` 两个表里。
- **命名空间 + 小驼峰**：`colors.backgroundSecondary`、`spacing.screenInset`、`motion.durationNormal`、`radius.lg`、`typography.body`。
- **色值格式**：`'#AARRGGBB'`（与 ArkUI ResourceColor 一致），用 `isColorTokenValue()` 校验。
- **数值单位**：间距/圆角为 vp，动画时长为 ms，字体为 vp；曲线存三次贝塞尔控制点 `{x1,y1,x2,y2}`（纯数据，ArkUI 边界用 `curves.cubicBezier(...)` 展开）。
- **token 集合以 `*_TOKEN_NAMES` 数组为准**：容器是 `interface X extends Record<string, T>`（ArkTS 字面量限制 + 可遍历的双重要求），新增 token 时三个位置必须同步：interface 字段、`Default*` 常量、`TOKEN_NAMES`。单测会用 `Object.keys` 反查 NAMES 与表完全一致。

## 如何加新 token（以新增语义色 `warning` 为例）

1. `Colors.ets`：`ColorTokens` interface 加 `warning: string;`，`LightColors` 与 `DarkColors` **各**补一个值（必须两套都补，深浅色映射完整性由单测强制）。
2. `COLOR_TOKEN_NAMES` 追加 `'warning'`。
3. 若该 token 有可读性要求（如文字/图标色），在 `Colors.test.ets` 里补对比度断言（WCAG：正文 4.5，大字号/装饰 3.0）。
4. 跑 `./hvigorw test --mode module -p module=core_design_system@default -p product=default --no-daemon`。
5. 间距/圆角/动画/排版同理，对应文件 + 对应 NAMES 数组 + `Tokens.test.ets` 存在性断言。

## 使用方式

```ts
import { createTheme, resolveToken, scaledTextStyle } from '@tgx/core-design-system';

const theme = createTheme('dark', 1.3);          // fontScale 自动 clamp 到 [0.85, 2.0]
const bg: string = theme.colors.background;
const body = scaledTextStyle(theme, 'body');     // 已按 fontScale 缩放 + 可读下限保护
const gap = resolveToken(theme, 'spacing.md');   // 12；未知名返回 undefined
```

- `resolveToken` 的 `typography.*` 返回 `'字号/行高/字重'` 字符串（已缩放）；其余 namespace 返回原始值。
- 字体缩放下限 `MIN_READABLE_FONT_SIZE = 11`：再小的字阶放大后也不会低于该值；行高始终 ≥ 字号。

## 与 ArkUI 组件接入（后续，entry 不在本模块边界内）

1. **平台侧喂 scale**：entry/platform 层从系统（configuration 更新 / `display`）拿到用户字体缩放，调用 `createTheme(mode, scale)` 缓存为 App 级主题，随深浅色/字号变化重建。
2. **组件侧**：ArkUI 组件里直接用 token 值，例如 `.backgroundColor(theme.colors.surface)`、`.borderRadius(theme.radius.lg)`、`.animation({ duration: theme.motion.durationNormal, curve: curves.cubicBezier(theme.motion.curveStandard.x1, ...) })`、`.fontSize(body.fontSize).lineHeight(body.lineHeight).fontWeight(body.fontWeight)`。
3. 建议 entry 提供 `ThemeContext`/LocalStorage 注入主题，组件不自己 `createTheme`。
4. 大字体验收（UI-001 验收项之一）：用 `createTheme(mode, 2.0)` 渲染 sample 页面检查截断/重叠。

## 测试

`./hvigorw test --mode module -p module=core_design_system@default -p product=default --no-daemon` —— 25 用例（Colors 7 / FontScale 7 / Tokens 5 / Theme 6），覆盖：深浅色映射完整且互不相同、WCAG 对比度（正文 4.5 / 次级 3.0 / 气泡与 accent 上文字 3.0）、fontScale 边界 0.85/1.0/1.15/1.3/2.0 与 clamp、最小可读字号、间距/圆角/动画 token 存在性与有序性、`resolveToken` 五命名空间与未知名返回 undefined。

## 交接说明

- 深浅色色板取自 Android 参考工程的语义概念（深底浅字 / 浅底深字、accent 深浅色不同、气泡双色），非逐值拷贝。
- 深色 `textOnAccent` 为黑色：深色 accent 较亮（#30A3F0），白字对比度仅 2.75 不达 WCAG 3.0，黑字约 7.6。
- 下一步（非本工作包）：UI-002 typed navigation 之后，entry 装配 sample 页做深浅色 + 大字体真机截图验收。
