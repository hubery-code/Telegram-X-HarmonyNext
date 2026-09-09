# codec fixtures（GEN-003）

TDLib JSON 样本 fixture，用于 `core_td_api_generated` codec 的 round-trip 单测
（`src/test/FixtureRoundTrip.test.ets`）。

## 来源标注

**本目录全部 fixture 均为 `synthetic`（合成）**，无任何真实用户数据：

- TDLib 官方仓库（`native/tdcore/third_party/td/`）的测试与示例
  （`td/test/*.cpp`、`example/python/tdjson_example.py` 等）均为代码内构造对象，
  **不存在可直接引用的静态 JSON 数据文件**；因此无 `official` 来源 fixture。
- 所有 fixture 的字段名/类型/嵌套结构派生自单一 schema 源
  `native/tdcore/third_party/td/td/generate/scheme/td_api.tl`（经 GEN-001/002），
  事件流形状（如 updateAuthorizationState 状态机顺序、error/ok 响应、@extra 关联）
  参照 TDLib 官方示例程序与文档语义。
- 个别可选对象字段（如 `minithumbnail`/`thumbnail`/`link_preview`）取 `null`；
  非空字段全部给出（codec encode 恒输出全字段，fixture 必须全字段以保证
  round-trip 键集一致）。

## 脱敏规则

- 无真实手机号：统一 `+42420004242`（`42xxx` 假号段）。
- 无真实用户/聊天/消息 id：一律 `42xxx` 假 id（user `4242001`-`4242005`、
  chat `424242`-`424246`、message `4242000000000x`）。
- 邮箱统一脱敏模式 `4***@example.com`；URL/token 均为 `example.com` / `AQAAAAA42fake` 等假值。
- int64 大数用无精度语义的字符串值（`9223372036854775807`、`-9223372036854775808`、
  `9007199254740993` > 2^53），覆盖大数与 vector<int64>。
- 字符串内容均为 "synthetic"/"fake"/示例文本，不含任何真实数据。

## 清单（22 个）

| 文件 | 类别 | 覆盖点 |
|---|---|---|
| `auth_01..13_*.json` | 授权状态机（13 个全状态） | waitTdlibParameters / waitPhoneNumber / waitPremiumPurchase / waitEmailAddress / waitEmailCode（含 emailAddressAuthenticationCodeInfo + emailAddressResetState）/ waitCode（含 authenticationCodeInfo + AuthenticationCodeType 联合）/ waitOtherDeviceConfirmation / waitRegistration（termsOfService）/ waitPassword / ready / loggingOut / closing / closed |
| `msg_01_text_with_entities.json` | updateNewMessage | messageText + formattedText.entities 对象 vector 嵌套（textEntityTypeBold / textEntityTypeTextUrl） |
| `msg_02_photo_spoiler.json` | updateNewMessage | messagePhoto：photo→photoSize→file/localFile/remoteFile 深嵌套、vector<int32> progressive_sizes、has_spoiler |
| `msg_03_sticker.json` | updateNewMessage | messageSticker：sticker→stickerFullTypeRegular、int64 id/set_id 字符串 |
| `msg_04_unsupported.json` | updateNewMessage | messageUnsupported 空构造器 |
| `resp_01_error_with_extra.json` | 响应 | error（code/message）+ `@extra` 关联标签 |
| `resp_02_ok_with_extra.json` | 响应 | ok + `@extra` 关联标签 |
| `vector_01_int64_ids.json` | update | updateInstalledStickerSets：vector<int64> 含 2^53 与 int64 极值 |
| `unknown_01_top_level.json` | 前向兼容 | 未知顶层 `@type` → TdUnknownObject，raw 无损回传 |
| `unknown_02_nested_content.json` | 前向兼容 | updateNewMessage 内未知消息内容类型 → 嵌套 TdUnknownObject raw 回传 |

所有 message fixture 的 `media_album_id`（int64 max）与 `chat_instance`（大负数）
同时承担 int64 大数覆盖。

## 如何新增 fixture

1. 在 `json/` 下新增 `<类别>_NN_<名称>.json`：合法 TDLib JSON（顶层含字符串
   `@type`），**全字段**（否则 round-trip 键集比对会失败），int64 一律字符串形式，
   遵守上面的脱敏规则，并更新本 README 清单。
2. 同步生成测试内嵌数据（单测运行期不能读文件，fixture 以字符串内嵌）：

   ```bash
   python3 core/td_api_generated/fixtures/sync_fixtures.py
   ```

   该脚本校验每个 fixture 是含 `@type` 的合法 JSON，并确定性重写
   `../src/test/gen/FixtureData.ets`（生成物，勿手改）。
3. 若新增的是未知类型 fixture，把名字加入 `FixtureRoundTrip.test.ets` 的
   `UNKNOWN_FIXTURES` 列表；类别计数断言（summary 用例）按需要更新。
4. 跑 `./hvigorw test --mode module -p module=core_td_api_generated@default -p product=default --no-daemon`。

## 测试语义

每个 fixture 注册一个独立用例：`JSON.parse` → `decodeTdObject` → `encodeTdObject`
→ `canonicalJson`（递归键排序）语义等价比对 → 二次 decode/encode 稳定。
未知 `@type` 的 fixture 额外断言走 `TdUnknownObject` 且 raw 无损回传。
