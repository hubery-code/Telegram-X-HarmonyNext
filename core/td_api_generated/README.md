# td_api_generated — TDLib 类型生成产物

本目录全部内容由生成器产出，**禁止手改**。

- 生成器：`tools/td_api_codegen/`（见其中 README）
- 输入：`native/tdcore/third_party/td/td/generate/scheme/td_api.tl`（单一输入源）
- 校验：`python3 tools/td_api_codegen/td_api_ir.py verify`（CI 入口）

| 文件 | 说明 |
|---|---|
| `schema.ir.json` | GEN-001 产出的 schema IR（GEN-002 ArkTS DTO/union 生成的直接输入） |

GEN-002 将在此基础上生成 ArkTS 类型（`types.ets` 等），同样整体提交、禁止手改。
