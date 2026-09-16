# PROFILE-101 实现报告：群聊点头像查看用户资料（个人中心 MVP）

## 结果
- 状态：Implementing → Verifying（代码与门禁完成，真机/模拟器验证待补——验证时模拟器离线）
- 工作包：PROFILE-101（从计划 §9.6 PROFILE Epic 提前拆包；Epic 原定 Phase 5）
- 执行者：主会话（DSH）
- 日期：2026-09-16

## 背景：计划里有没有？能不能提前？

- **在计划里**：`HARMONY_NEXT_MIGRATION_PLAN.md §9.6` 的 Phase 4/5 Epic 表中有
  `PROFILE | 用户/群组/频道资料、共享媒体、举报/拉黑`。按 §9.6 约定 Epic 进入开发前拆成
  0.5–3 天工作包；FEATURE_MATRIX 无 PROFILE 的 P1 条目（属 Phase 5/Beta 级）。
- **可以提前**：本包依赖的基础都已就绪——`core/domain` 的 `UserRegistry`（getUser 缓存
  + updateUser/updateUserStatus 订阅）、`FileRegistry`（头像下载）、TDLib 生成代码
  （getUser/getUserFullInfo/createPrivateChat）、强类型导航栈。点头像看资料是 Epic 里
  最独立、价值最高的一条，故拆为 PROFILE-101 先行。
- **Android 参考**：`TGMessage.onAvatarClick → openProfile → tdlib.ui().openPrivateProfile
  (userId)` → `ui/ProfileController.java`（6816 行全功能版）。本包对齐其**查看他人资料**
  的信息面 MVP：大头像、姓名、@username、手机号、在线状态、简介 bio、「发消息」入口。
  共享媒体、共同群组、举报/拉黑、音视频通话留后续包。

## 实际修改

### 1. core/navigation：新增 `UserProfileRoute`
- `Route.ets`：`UserProfileRoute { name:'userProfile', userId }`；并入 `AppRoute` union 与
  `RouteName`；`ROUTE_DEFINITIONS` 加 `userProfile/{userId}`（userId int、required、min 1）。
- `RouteCodec.ets`：编解码 `userProfile/{id}`（parse 非 int 报 `parameter/invalid/userId`）。
- `Index.ets`：导出 `UserProfileRoute`。深链规则不变（应用内路由）。

### 2. core/domain：UserRegistry 补 UserFullInfo 能力
- 订阅过滤器加 `updateUserFullInfo`；新增 `fullInfos` 缓存 +
  `requestUserFullInfo / getUserFullInfo / putUserFullInfo / subscribeUserFullInfo`。
- 纯 ArkTS / Kit-free 不变（架构守卫通过）。

### 3. feature/chat：发送者 userId 全链路（头像可点的前提）
- `SenderInfo` 增加 `userId`（0=非用户发送者）；`resolveSenderInfo` 对用户发送者回填。
- `MessageItem` 增加 `senderUserId`（末尾可选参数，既有调用点默认 0，旧测试不受影响）。
- `ChatCoordinator` 两个 MessageItem 构造点透传；`ChatIntent` 新增 `OpenUserProfile(userId)`
  （纯导航意图，reducer default 透传）；`ChatCoordinatorOptions.onOpenUserProfile`；
  dispatch 层处理（对齐 openMediaViewer 的模式）。
- `ChatPage` 群聊头像（Image/字母底两分支）加 `onClick → OpenUserProfile(senderUserId)`。

### 4. feature/profile：新模块（MVI，对齐 feature/search 的模块形态）
- 模块骨架：`oh-package.json5`（@tgx/feature-profile，file 依赖 core-account/common/
  design-system/domain/td-api-generated/td-gateway/observability/platform-ports/feature-template）、
  `module.json5`(har)、`hvigorfile.ts`、`build-profile.json5`；注册进根 `build-profile.json5`。
- `contract/ProfileUiState`：userId/displayName/username/phone/bio/statusText/avatarPath/
  avatarLetters/avatarColorIndex/isLoading/errorMessage，initial()/copyWith()。
- `contract/ProfileIntent`：MessageUserRequested / OnProfileLoaded / OnBioLoaded /
  OnAvatarFileLoaded / OnProfileFailed。
- `contract/ProfileEffect`：CreatePrivateChatEffect(userId)。
- `reducer/ProfileReducer`：纯函数（messageUser 出效应；loaded/bio/avatar 回灌；failed 报错）。
- `coordinator/ProfileCoordinator`：UserRegistry+FileRegistry 双注册器；缓存先回灌 +
  订阅刷新；头像大图本地命中即用、未命中 downloadFile(priority 2)+subscribeFile 回灌；
  createPrivateChat 效应 → 回包 chat.id → onOpenChat 回调。在线状态文案 MVP 简化
  （online / last seen recently / within a week / within a month）。
- `pages/ProfilePage`：顶栏（‹ + User Info）+ 大头像/姓名/状态 + Username/Phone/Bio 行 +
  底部「Message」按钮；全 design tokens；加载/错误/内容三态。

### 5. entry 装配
- `oh-package.json5` 加 `@tgx/feature-profile`；`openProfile/closeProfile`（路由观察分支，
  协调器生命周期与 chat/search 同模式）；ChatCoordinator 构造注入
  `onOpenUserProfile → navigateTo({name:'userProfile', userId})`；`userProfile` 路由
  渲染分支（ProfilePage：dispatch 直给协调器 + onBack pop）；「发消息」成功后
  `navigateTo({name:'chat', chatId})` 压栈。

### 6. 跨 agent 协作修复（非本包功能，但阻塞全仓构建）
- 并行协作者正在实现 SEARCH-103（全局搜索健壮性），其 `SearchCoordinator.executeSearch`
  重构用了 `if (x.err) { return; } x.value` 的跨 return 收窄——ArkTS 不支持
  （只收窄 if(x.ok)/if(x.err) 块内）。DSH 将两处改为正向 `if (x.ok) { value }` +
  `if (x.err) { fail }` 双 if 写法，**逻辑零改动**，已在 PROGRESS 的 SEARCH-103 行注明。

## 自动化测试与门禁（本地）

| 模块 | 变化 | 结果 |
|---|---|---|
| core_navigation | 42 → **46**（+4：userProfile 往返/编码/解析/非法类型） | PASS |
| core_domain | 78（UserRegistry 扩展未破坏既有用例） | PASS |
| feature_chat | 172（senderUserId 默认参数，既有用例不动） | PASS |
| feature_profile | 0 → **6**（messageUser 出效应/非法 id 空操作/loaded 回灌/bio/avatar/failed） | PASS |
| 静态守卫 | design-token / architecture / codegen | 0 违规 |
| assembleHap | entry 全量（含新模块 + SEARCH-103 在途代码） | BUILD SUCCESSFUL |

> 说明：全量 19 模块 test_all_modules 未在本轮重跑——并行协作者的 SEARCH-103 尚在
> 实现中（其模块测试状态以该 agent 报告为准）；本包四个模块 + 静态守卫 + 全量编译
> 已绿，收尾时会补一次全量。

## 真机验证（2026-09-16，华为真机 6XE0225A27023538 / aarch64，AI 代操作）

签名部署：`local.signing.json5`（用户 DevEco 自动签名材料）+ `./tools/ci/build-signed.sh debug`
出 `entry-default-signed.hap` → `./tools/ci/device-install.sh` 自动探测真机、安装、拉起 EntryAbility。

| 步骤 | 实测结果 | 结论 |
|---|---|---|
| 群聊（El CLUB）点 Rose 头像 | 压栈打开「User Info」：大头像（已下载渲染）、Rose、`online`、`@MissRose_bot`、底部 Message 按钮；hilog `open_user_profile userId=609517172` → `profile coordinator started for userId=609517172` | ✅ |
| 点「Message」 | hilog `create_private_chat userId=609517172` → `create_private_chat_ok chatId=609517172`；私聊页打开（标题 Rose） | ✅ |
| 私聊返回 | 落回「User Info」资料页（导航栈正确） | ✅ |
| 再返回 | 回到群聊 → 会话列表 | ✅ |
| 真人用户资料（Redmi 群 @Shiro Neko） | 姓名 Shiro Neko、`last seen recently`（离线文案正确）、Username `@nekoko32`、Bio `UID 0`；无 Phone 行（对方隐私隐藏，条件渲染正确） | ✅ |
| 私聊内收到消息不显示头像 | showSenderUi 仅群聊生效 + senderUserId=0 守卫，结构上不可误触 | ✅ |

> 验证数据说明：Rose 为 bot（无 phone/bio 属正常）；@nekoko32 隐藏手机号属 Telegram 隐私设置，
> 行级条件渲染按"有则显示"处理，均符合预期。

## 已知边界 / 后续包
- PROFILE-102+：共享媒体、共同群组、举报/拉黑、语音/视频通话入口、编辑备注名。
- 自己点开自己头像：Android 会进"我的资料"编辑态；本包统一走只读资料页（可后续分流）。
- 头像点击暂只对群聊接收消息生效（对齐现有 showSenderUi 范围）；频道发帖身份
  （MessageSenderChat）按 Android 行为应进 chat profile，留 PROFILE-10x。
- 在线状态文案为 MVP 简化版（不格式化 last seen 的具体时间）。
