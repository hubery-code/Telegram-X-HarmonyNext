# ADR-006 HUKS 硬件密钥管理与 TDLib 数据库加密 (DATA-001)

- 状态：Accepted（2026-09-14，DATA-001）
- 决策者：迁移项目组与架构负责人
- 关联问题：P0-DATA-001, G1 阻断项

## Context

原实现中 `database_encryption_key` 为硬编码空字符串，未启用 TDLib 底层 SQLite 数据库加密，违反了端到端通信客户端的安全合规底线；且旧测试机上已存在未加密的旧数据库文件，强行启用新密钥会导致旧库 401 无法打开。

## Decision

1. **硬件级密钥隔离**：通过 `@kit.CryptoArchitectureKit`（HUKS）按 `accountKey` 别名存储 256 位高熵 AES 密钥；
2. **纯算法 Base64 编码**：在 `core/common` 实现零 Kit 依赖的 RFC 4648 Base64 编解码器，将 32 字节二进制密钥安全转换为 TDLib 所需的 Base64 字符串；
3. **在线平滑迁移机制**：在 `AuthCoordinator` 启动时携带新密钥发起握手，遇到 401 时自动探针回退空密钥握手；若证实为旧未加密库，通过 TDLib `setDatabaseEncryptionKey` API 在线重加密升级，实现用户零感知、数据零丢失。

## Consequences

- 满足金融级安全合规标准，彻底防护离线物理提库风险；
- 兼顾既有存量设备的平滑升级，无需强制清空用户聊天记录。
