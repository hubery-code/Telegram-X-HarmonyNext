# Telegram X → HarmonyOS NEXT 总体架构

> 单一事实源（计划 §4.1/§4.2）。任何模块拆分、依赖方向问题以本文为准。
> Android 参考实现：`/Users/mbjpeng-yu01/androidProjects/Telegram-X`（`org.thunderdog.challegram`）。

## 1. 总体分层

依赖只允许从上向下；反向通知只能通过接口或有序领域事件，不允许跨层持有对象。

```text
ArkUI View / Page
  └─ Feature ViewModel / Reducer          (feature/* HAR)
       └─ Use Cases                        (core/domain HAR)
            └─ Domain Repository / Platform Ports
                 ├─ Telegram Gateway       (core/td_gateway HAR)
                 │    └─ Generated TDLib DTO + Codec   (core/td_api_generated HAR)
                 │         └─ Node-API Bridge          (native/tdcore → libtdcore.so)
                 │              └─ TDLib C++ Core      (上游受控 fork，静态链接)
                 │                   ├─ Telegram Network
                 │                   └─ TDLib SQLite / Files
                 └─ Harmony Platform Adapters   (platform/* HAR → platform/api 接口)
                      └─ Push / Notification / Background / Media / Camera /
                         Security / Share / Contacts / Location / Calls (系统 Kit)
```

事件上行（TDLib → UI）统一经过 **Ordered Event Router**（core/td_gateway）：
Node-API 层只负责把 update 放入有界队列，排序、背压、回放和账号隔离在 td_gateway 内完成。

## 2. 模块依赖规则（强制，CI 可检查）

计划 §4.2 依赖图：

```text
entry HAP ──→ feature_* HAR ──→ core_domain HAR ──→ td_api_generated HAR
                  │                    └─→ td_gateway HAR ──→ tdcore native (HAR/.so)
                  ├─→ core_design HAR
                  └─→ platform_api HAR ←── platform_* HAR (实现)
entry HAP ──→ platform_* HAR (装配)
test_support HAR ──→ core_domain, platform_api
```

规则：

1. `feature_*` 之间不得直接依赖；跨功能协调经 application coordinator 或领域事件。
2. `core_domain` 不得 import ArkUI、Ability、Node-API 或任何具体 Kit。
3. `platform_api` 只有接口和稳定数据模型；具体实现放 `platform_*`。
4. 只有 `td_gateway` 可发送 TDLib request。
5. 只有 `tdcore` 可调用 Node-API / native TDLib。
6. `entry` 只负责装配、生命周期、路由根和 ExtensionAbility 注册，不承载业务规则。
7. （测试）测试 fake 必须实现与生产 adapter 相同的契约。

## 3. 关键进程 / 线程模型（Phase 1 起约束）

- TDLib 运行在独立 worker 线程（Actor 模型），UI 线程禁止同步等待 TDLib。
- Node-API 在 UI 线程的同步工作单次 ≤4 ms（性能预算 §14.2）。
- 有序事件：单序列、有界队列；update 丢失 / 乱序 / 跨账号 = P0 缺陷。

## 4. 仓库目录映射

见计划 §4.3；本仓库根目录即 HarmonyOS 工程根（`harmony/` 前缀已按用户决定取消）。
目录骨架已建（core/*、platform/*、feature/*、native/*、tools/*、test/*），注册进构建（hvigor modules）的时间点由对应工作包决定，禁止提前注册空模块。

## 5. 当前状态（Phase 0）

- 仅 `entry` 一个可构建模块（空壳 HAP，ArkUI 单页）。
- TDLib / Node-API / HAR 模块均未开始（G1/G2 工作包）。
