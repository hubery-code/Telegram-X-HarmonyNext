# Test Matrix（测试策略与用例骨架）

> 来源：计划 §12。测试金字塔：60–70% 单元（ArkTS 领域逻辑 / Reducer / C++）、
> 20–30% 集成（NAPI 契约 / 存储迁移 / platform adapter / TDLib fixture replay）、
> 5–10% 真机 UI/E2E。

## 必备测试能力（§12.2）

1. 纯逻辑测试：注入固定时钟、随机数、文件系统、网络。
2. TDLib 回放：脱敏 update fixture，覆盖重复/延迟/重连/账号切换（目录 `test/fixtures`）。
3. NAPI 契约：64 位 ID、Unicode、大对象、未知枚举、批量事件、并发取消、销毁竞态。
4. 差分测试：entity、未读数、排序、发送状态、日期格式 vs Android 参考（PARITY_MATRIX.md）。
5. UI 视觉：深浅色、中/英/RTL、字体缩放、固定设备截图基线（更新需说明）。
6. E2E：授权、收发、编辑、删除、媒体、搜索、离线恢复、Push 跳转、多账号。
7. 破坏性：杀进程、断网、弱网、低存储、权限撤销、时间变化、重启、升级中断。
8. RTC：音频焦点、蓝牙/听筒、锁屏、弱网、摄像头切换、系统电话抢占。

## 用例骨架（ID 规则：层级-域-序号）

| 测试 ID | 层级 | 场景 | 自动化 | 状态 |
|---|---|---|---|---|
| UT-001 | 单元 | ArkTS Reducer/格式化（占位，QA-001 扩展） | hypium 本地 | Skeleton |
| INT-001 | 集成 | TDLib arm64 构建 + native smoke | CI | Backlog |
| INT-002 | 集成 | NAPI 24h update 压测（乱序/丢失/泄漏=0） | CI + 真机 | Backlog |
| INT-003 | 集成 | TDLib fixture replay（重复/延迟/重连/切账号） | CI | Backlog |
| CT-001 | 契约 | NAPI 64 位 ID / Unicode / 大对象序列化 | CI | Backlog |
| CT-002 | 契约 | platform adapter fake ≡ 生产契约 | CI | Backlog |
| E2E-001~007 | E2E | P0 可行性场景（见 FEATURE_MATRIX.md P0 行） | 真机 | Backlog |
| E2E-010~070 | E2E | P1 MVP 场景（见 FEATURE_MATRIX.md P1 行） | 真机 | Backlog |
| DES-001 | 视觉 | 深浅色/RTL/大字体截图基线 | CI 截图 | Backlog |

## 覆盖率门槛（§12.3）

- 领域核心：行 ≥85%，分支 ≥75%。
- 桥接与存储：行 ≥80%，关键错误路径 100%。
- 平台 adapter：行 ≥70%，真机契约测试补足。
- UI 以交互/视觉/无障碍场景覆盖为准，不以行覆盖为目标。
- 总覆盖率下降 >1 个百分点阻断（除非有带失效日期的批准豁免）。

## 当前状态（Phase 0 / QA-001 部分）

- 本地测试骨架已建：`entry/src/ohosTest/`（TestAbility + OpenHarmonyTestRunner + `ListTest` hypium 用例）。
- 运行方式见 `docs/runbooks/test.md`。设备测试（Hypium on-device）需真机，待 DEVICE_MATRIX.md 输入后启用。
