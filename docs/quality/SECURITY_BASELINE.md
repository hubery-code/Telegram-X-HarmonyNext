# Security Baseline（安全与隐私基线）

> 来源：计划 §14.4 / §16 严重度定义。P0 安全项不允许豁免。

## 数据红线（任何环境：git / 日志 / 截图 / 证据）

- 不得出现：`api_hash`、验证码、手机号、session token、私钥、真实聊天正文。
- Telegram `api_id/api_hash` 由用户通过安全渠道提供，**不进入仓库**（见 `.gitignore` 与 GOV-007）。
- 测试一律使用隔离测试账号；证据产出前按本基线自查。

## 日志与脱敏

- 日志按**字段白名单**输出；禁止先完整记录再正则脱敏。
- TDLib database key、token、代理凭据不得进入 Preferences/JSON 明文。
- 密钥材料优先 HUKS/Asset Store（ADR-008，G2 前决议）。

## 权限

- 按需申请；拒绝后无关能力仍可用（P0 功能不得因权限拒绝整体不可用）。
- 通讯录、麦克风、相机、相册等权限的工作包必须包含「拒绝路径」测试（TEST_MATRIX.md）。

## CI 安全门禁（GOV-006 扩展）

- 每次 CI：secret scan、SAST、SBOM、漏洞与许可证扫描。
- 高危漏洞阻断发布；P0/P1 安全问题不允许豁免。
- 每个大版本更新威胁模型与数据流图（SEC-001 及其后续）。

## 事件响应

- 任何密钥/聊天内容泄漏到证据 = 立即 P0：吊销并清理（计划 §18 风险登记册「密钥/聊天内容泄漏」）。
- 泄漏处理记录进风险登记册与对应 work item 的回滚章节。

## 当前状态（Phase 0）

- 秘密管理已落地：`.gitignore` 排除签名材料/`local.properties`/`oh_modules` 等；构建无需任何秘密（未配置 signingConfigs，产物为 unsigned hap）。
- 威胁模型 v0 = SEC-001（Backlog，依赖 GOV-004）。
