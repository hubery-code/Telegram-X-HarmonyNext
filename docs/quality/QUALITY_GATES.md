# Quality Gates（G0–G8 摘要 + DoD 清单）

> 来源：计划 §8、§11。数值细节见 PERFORMANCE_BUDGET.md / SECURITY_BASELINE.md。

## Gate 摘要

| Gate | 阶段 | 退出条件（摘要，全文见计划 §8） |
|---|---|---|
| G0 | 范围与基线 | 工具链锁定；最低/目标 API 与设备矩阵批准；Feature/Parity Matrix 建立；Android 行为样本完成；隔离测试账号就绪；质量预算/威胁模型 v0/秘密管理批准；CI 能构建空壳 HAP。**（本工作包 GOV-001~003/007 覆盖其中工程侧条目）** |
| G1 | 原生可行性 | TDLib arm64 可复现构建 + native tests；真机登录/收发/库恢复；NAPI 24h 压测无乱序/丢失/泄漏；Push 闭环或明确 Blocked；tgcalls PoC 或 Deferred；native crash 可符号化。 |
| G2 | 架构骨架 | 模块依赖规则 CI 可检查；Node-API/gateway/EventRouter/AccountScope/platform ports 可运行；TDLib 全量类型生成 + schema hash 检查；Fake gateway/fixture replay/contract test 框架；设计系统/typed navigation/日志基线；PR 质量门禁启用。 |
| G3 | 最小垂直切片 | 真机：启动→登录→会话列表→聊天→收发文本→断网恢复→杀进程恢复；正常/空数据/错误/取消/重试/权限拒绝/库恢复均有证据。 |
| G4 | 核心聊天 MVP | P1 全 Accepted/Deferred；核心自动化 100% 无 P0/P1；Push/通知/文件/图片/视频/语音/多账号过真机矩阵；性能/内存/功耗/包体预算通过。 |
| G5/G6 | Beta | P2 完成；设备矩阵完成；8–24h 稳定性/弱网/低存储/权限撤销；7 天 beta 指标达标；安全/许可证/SBOM/隐私审查通过。 |
| G7/G8 | RC | 功能冻结；全量回归 + 升级/回滚演练；产物/symbols/source maps/SBOM/NOTICE 可追溯；无未处理 P0/P1；三方验收。 |

## Definition of Ready（下发工作包前）

- [ ] Work Item 按 §17.1 模板填写：目标/非目标/依赖/修改范围/设计约束/验收标准/必须测试/回滚。
- [ ] 涉及的功能在 FEATURE_MATRIX.md 有行，Android 参考路径已核实存在。
- [ ] 涉及行为差异的行在 PARITY_MATRIX.md 已到 `Baseline Captured`（P0/P1）。
- [ ] 契约（TDLib 方法、NAPI 边界、平台 API）已有草稿并标注版本。
- [ ] 授权目录明确；性能/内存预算已写进工作包。

## Definition of Done（工作包提交时）

- [ ] 验收标准全部勾选，证据按 §17.2/§17.3 模板绑定当前 commit。
- [ ] `./tools/ci/build.sh debug` 与 `release` 通过；新增测试全部通过。
- [ ] 未修改未授权目录；未引入秘密/个人数据（SECURITY_BASELINE.md）。
- [ ] 契约、Fake、测试三者一致；64 位 ID、并发、事件顺序、取消、超时、恢复已自查。
- [ ] 文档与矩阵已更新；无新增 warning；无误带其他 AI 的变更。
- [ ] 架构负责人 Check（计划 §16 十步）输出 APPROVE，或 BLOCK 问题已清零。
