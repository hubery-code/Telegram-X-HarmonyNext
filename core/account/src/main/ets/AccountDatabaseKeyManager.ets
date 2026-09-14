/**
 * core/account — AccountDatabaseKeyManager：账号数据库加密密钥管理器（DATA-001，P0-DATA-001）。
 *
 * 负责每个 AccountScope 的 TDLib SQLite 数据库加密密钥（256 位 / 32 字节）全生命周期：
 * 1. 首次创建：调用 SecureRandomPort 生成 32 字节高熵随机字节，保存在 SecureKeyStorePort；
 * 2. 杀进程重启恢复：从 SecureKeyStorePort 查询既有密钥并加载；
 * 3. 多账号隔离：密钥别名按 accountKey 严格隔离（db_key_<accountKey>）；
 * 4. 登出注销：调用 SecureKeyStorePort.remove 彻底销毁硬件中的数据库密钥；
 * 5. 协议转换：提供 base64Encode 将二进制密钥编码为 TDLib 官方 JSON 协议所需的 Base64 串。
 *
 * 遵循依赖倒置，零 @kit.* / ArkUI 依赖。
 */

import { AppError, AppErrors, Result, base64Encode, err, ok } from '@tgx/core-common';
import { SecureKeyStorePort, SecureRandomPort } from '@tgx/platform-ports';

export const DB_KEY_BYTES_LENGTH: number = 32;
export const DB_KEY_ALIAS_PREFIX: string = 'db_key_';

export interface AccountDatabaseKeyManagerDeps {
  readonly accountKey: string;
  readonly keyStore: SecureKeyStorePort;
  readonly secureRandom: SecureRandomPort;
}

export class AccountDatabaseKeyManager {
  private readonly accountKey: string;
  private readonly alias: string;
  private readonly keyStore: SecureKeyStorePort;
  private readonly secureRandom: SecureRandomPort;

  constructor(deps: AccountDatabaseKeyManagerDeps) {
    this.accountKey = deps.accountKey;
    this.alias = `${DB_KEY_ALIAS_PREFIX}${deps.accountKey}`;
    this.keyStore = deps.keyStore;
    this.secureRandom = deps.secureRandom;
  }

  get keyAlias(): string {
    return this.alias;
  }

  /**
   * 检查当前账号是否已在安全存储中存有数据库密钥。
   */
  async hasKey(): Promise<Result<boolean, AppError>> {
    const res: Result<Uint8Array | null, AppError> = await this.keyStore.get(this.alias);
    return res.fold(
      (data: Uint8Array | null) => ok(data !== null && data.length > 0),
      (error: AppError) => err(error)
    );
  }

  /**
   * 读取既有密钥；若不存在返回 ok(null)。
   */
  async getExistingKey(): Promise<Result<Uint8Array | null, AppError>> {
    const res: Result<Uint8Array | null, AppError> = await this.keyStore.get(this.alias);
    if (res.ok === false) {
      return err(res.error);
    }
    const val: Uint8Array | null = res.value;
    if (val !== null && val.length !== DB_KEY_BYTES_LENGTH) {
      return err(AppErrors.storage(
        'corrupted',
        `retrieved database encryption key length ${val.length} != ${DB_KEY_BYTES_LENGTH}`,
        false
      ));
    }
    return ok(val);
  }

  /**
   * 获取或自动创建高熵数据库密钥：
   * - 存在即返回（重启恢复）；
   * - 不存在则由 secureRandom 生成 32 字节并存入 keyStore（首次创建）。
   */
  async getOrCreateKey(): Promise<Result<Uint8Array, AppError>> {
    const existing: Result<Uint8Array | null, AppError> = await this.getExistingKey();
    if (existing.ok === false) {
      return err(existing.error);
    }
    if (existing.value !== null) {
      return ok(existing.value);
    }

    // 不存在，生成新高熵密钥
    const generated: Result<Uint8Array, AppError> = await this.secureRandom.generateRandom(DB_KEY_BYTES_LENGTH);
    if (generated.ok === false) {
      return err(generated.error);
    }
    const newKey: Uint8Array = generated.value;

    const saved: Result<void, AppError> = await this.keyStore.put(this.alias, newKey);
    if (saved.ok === false) {
      return err(saved.error);
    }

    return ok(newKey);
  }

  /**
   * 获取 Base64 编码的数据库密钥（用于传入 TDLib setTdlibParameters 或 setDatabaseEncryptionKey）。
   */
  async getDatabaseEncryptionKeyBase64(): Promise<Result<string, AppError>> {
    const keyRes: Result<Uint8Array, AppError> = await this.getOrCreateKey();
    if (keyRes.ok === false) {
      return err(keyRes.error);
    }
    return ok(base64Encode(keyRes.value));
  }

  /**
   * 覆盖存入新密钥（用于在线重加密迁移成功后保存）。
   */
  async overrideKey(keyBytes: Uint8Array): Promise<Result<void, AppError>> {
    if (keyBytes.length !== DB_KEY_BYTES_LENGTH) {
      return err(AppErrors.parameter(
        'invalid',
        'keyBytes',
        `key length must be ${DB_KEY_BYTES_LENGTH}, got ${keyBytes.length}`
      ));
    }
    return await this.keyStore.put(this.alias, keyBytes);
  }

  /**
   * 彻底销毁安全存储中的数据库密钥（账号登出/注销）。
   */
  async destroyKey(): Promise<Result<void, AppError>> {
    return await this.keyStore.remove(this.alias);
  }
}
