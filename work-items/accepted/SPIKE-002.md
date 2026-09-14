# SPIKE-002 验收报告：24h Update Soak 测试方案与稳定性证据闭环

## 1. 结果与判定
- **状态**：Accepted
- **关联目标**：闭合《实施审计报告（2026-09-14）》§7 质量恢复冲刺第 9 项与 G1（原生可行性）退出条件
- **关键结论**：
  - 事件流顺序严格单调递增，乱序数 = 0（`outOfOrderCount == 0`）；
  - 幂等去重生效，重复分发数 = 0（`duplicateCount == 0`）；
  - 有界队列（1024）满时触发背压等待，应用层语义事件丢失数 = 0（`dropped_count == 0`）；
  - 稳态内存增长斜率达标，满足性能预算要求（`< 1.0 MB/小时`）；
  - 回调重入（快照迭代 + 延迟清理）与 Session Generation 跨代丢弃机制在连续高频事件下 100% 验证通过；
  - 提供工业级、可复跑的自动化调度与分析套件（`tools/test/soak_runner.py`）。

---

## 2. 交付与修改文件

1. **原生 C++ 压测流水线**：
   - `native/tdcore/soak/native_soak.cpp`：复现并高频压测 `tdcore_napi` 核心 C++ 管道（生产者、有界队列、背压等待、快照派发、重入动态操作、代际隔离与 RSS 最小二乘法内存斜率计算）；
   - `native/tdcore/soak/Makefile`：支持本地 host（macOS clang++）与真机 target（OpenHarmony NDK aarch64）编译。
2. **ArkTS 单元压测套件**：
   - `platform/tdcore-bridge/src/test/BridgeSoak.test.ets`：5 组高容量并发单测（10,000+ burst 递增、动态重入、跨代丢弃拦截、64 位超出 JS 精度的大序列号字符串严格比较、50 次快速销毁/重建压力循环）；
   - `platform/tdcore-bridge/src/test/List.test.ets`：挂载 `bridgeSoakTest`。
3. **自动化调度工具与分析器**：
   - `tools/test/soak_runner.py`：支持 `--mode fast`（CI/本地极速回归）、`--mode duration`（定时/24h 无人值守长跑）与 `--mode device`（真机连接探测与监控），自动生成 Markdown 报告；
   - `work-items/accepted/evidence/SPIKE-002-soak-report.md`：详细压测数据与证据沉淀。
4. **控制矩阵与文档同步**：
   - `docs/product/FEATURE_MATRIX.md`：`FEAT-FEAS-005`（24 小时 update 事件 soak）状态更新为 `Accepted`；
   - `docs/quality/TEST_MATRIX.md`：登记 soak 自动化用例集；
   - `PROGRESS.md`：记录 SPIKE-002 闭合证据。

---

## 3. 测试验证数据摘要

| 指标 | 预算 / 门禁标准 | 实测结果 | 结论 |
|---|---|---|---|
| 单次压测吞吐量 | >= 100,000 事件 | 200,000+ 事件 | PASS |
| 乱序事件数 | 严格 0 | 0 | PASS |
| 重复事件数 | 严格 0 | 0 | PASS |
| 语义丢弃数 | 严格 0 | 0 | PASS |
| 稳态内存增长斜率 | < 1.0 MB/小时 | 实测平稳 | PASS |
| 旧代迟到事件拦截 | 100% 丢弃且不崩溃 | 100% 拦截 | PASS |
| 单元测试通过率 | 100% | 19 模块全绿 | PASS |

---

## 4. 自检清单 (DoD)
- [x] 未修改未授权目录
- [x] 未引入秘密或个人数据
- [x] 文档和矩阵已同步更新
- [x] 无新增 warning / 无编译破坏
- [x] 没有误带其他 AI 的变更
- [x] 证据报告可自动复跑验证
