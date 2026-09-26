/**
 * platform/ports — PasscodeStorePort：应用锁 PIN 秘密值的托管契约（APPLOCK-101）。
 *
 * 为什么单独一条端口，而不是复用 `PreferencesPort` 或 `SecureKeyStorePort`：
 * - `PreferencesPort` 的口径是「只存小型、非敏感开关」，PIN 派生值不是开关；
 * - 裸的 `SecureKeyStorePort` 只认字节，而 PIN → 字节这一步（加盐摘要）是密码学，
 *   属于平台能力，不该散落到 entry 或 feature 里。
 * 所以这里只暴露「设 / 验 / 清 / 有没有」四个动作，实现自己决定怎么派生与存放，
 * **接口层不存在任何能把 PIN 或派生值读出来的方法**。
 *
 * 语义约定：
 * - `set` 是原子的：内部必须「写入后读回并验证同一个 PIN」，对不上就回滚成未设置态
 *   并回 err。这条自校验不是洁癖 —— 派生实现写坏的话，用户会在下一次冷启动
 *   被自己的密码锁死，而那已经是不可恢复的损失（本仓不允许卸载重装清数据，
 *   TDLib 会话要短信码）。
 * - `matches` 在秘密值不存在时回 `ok(false)`，不是 err：「没设过密码」是一个正常的否答。
 * - 任何方法的 `AppError` 都不得携带 PIN、盐或摘要；诊断只走 `cause` 里的系统错误码。
 */

import { Result, AppError } from '@tgx/core-common';

export interface PasscodeStorePort {
  /** 本机是否已托管 PIN 的秘密值。 */
  isSet(): Promise<Result<boolean, AppError>>;

  /** 写入 PIN 的秘密值（内含读回自校验，见文件头）。 */
  set(pin: string): Promise<Result<void, AppError>>;

  /** 校验一个 PIN 是否与已托管的秘密值一致。 */
  matches(pin: string): Promise<Result<boolean, AppError>>;

  /** 抹掉秘密值；未设置时视为成功（幂等）。 */
  wipe(): Promise<Result<void, AppError>>;
}
