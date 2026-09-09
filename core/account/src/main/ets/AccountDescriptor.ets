/**
 * core/account — 持久化账号描述符 + registry 清单编解码（CORE-003）。
 *
 * AccountDescriptor 是账号的持久化描述（§6.1：冷启动时 registry 按描述符批量恢复）。
 * 只存跨进程稳定的字段：accountKey（调用方分配的业务键）、accountId（稳定字符串）、
 * createdAtMillis、enabled（休眠账号恢复为 hibernating，不自动激活）。
 * 刻意不存 clientId：TDLib clientId 是进程内标识，冷启动必须经 createClient 重新分配。
 *
 * 清单文件：files/accounts/registry.json（经 AppFilesPort 读写，见 AccountManifest.ets）。
 * 编解码失败一律 err(storage/corrupted)（持久化数据损坏，fail-safe，绝不产出半解析状态）；
 * 原始内容不进错误 message（可能携带账号信息，见计划 §5.6 日志规则）。
 */

import { AppError, AppErrors, Result, err, ok } from '@tgx/core-common';
import { TdWireObject, TdWireValue, isWireObject, wireNumber, wireString } from '@tgx/td-gateway';

export interface AccountDescriptor {
  /** 业务键（如手机号字符串），调用方传入，registry 内唯一。 */
  readonly accountKey: string;
  /** 稳定账号标识（可注入生成器产出），跨进程存活。 */
  readonly accountId: string;
  /** 创建时间（epoch millis，注入 Clock 产出）。 */
  readonly createdAtMillis: number;
  /** true = 冷启动恢复时激活；false = 恢复为 hibernating（可再 activate）。 */
  readonly enabled: boolean;
}

/** 构造描述符（显式字段拷贝，ArkTS 不用对象 spread）。 */
export function createDescriptor(
  accountKey: string,
  accountId: string,
  createdAtMillis: number,
  enabled: boolean
): AccountDescriptor {
  return {
    accountKey: accountKey,
    accountId: accountId,
    createdAtMillis: createdAtMillis,
    enabled: enabled
  };
}

/** 描述符 → JSON 文本（确定性字段序）。 */
export function encodeAccountDescriptor(descriptor: AccountDescriptor): string {
  const wire: TdWireObject = {};
  wire['accountKey'] = descriptor.accountKey;
  wire['accountId'] = descriptor.accountId;
  wire['createdAtMillis'] = descriptor.createdAtMillis;
  wire['enabled'] = descriptor.enabled;
  return JSON.stringify(wire);
}

/** JSON 文本 → 描述符；任何形状问题都 err(storage/corrupted)。 */
export function decodeAccountDescriptor(json: string): Result<AccountDescriptor, AppError> {
  let parsed: Object;
  try {
    parsed = JSON.parse(json);
  } catch (e) {
    return corrupted(`json parse failed: ${String(e)}`);
  }
  if (!isWireObject(parsed as TdWireValue)) {
    return corrupted('descriptor is not an object');
  }
  return descriptorFromWire(parsed as TdWireObject);
}

/** 清单 → JSON 文本（包装一层版本字段，便于将来迁移）。 */
export function encodeAccountManifest(descriptors: AccountDescriptor[]): string {
  const list: TdWireValue[] = [];
  for (const descriptor of descriptors) {
    list.push(JSON.parse(encodeAccountDescriptor(descriptor)) as TdWireValue);
  }
  const wire: TdWireObject = {};
  wire['schemaVersion'] = 1;
  wire['accounts'] = list;
  return JSON.stringify(wire);
}

/** 清单 JSON → 描述符数组；任何一项损坏都整体 err(storage/corrupted)。 */
export function decodeAccountManifest(json: string): Result<AccountDescriptor[], AppError> {
  let parsed: Object;
  try {
    parsed = JSON.parse(json);
  } catch (e) {
    return corruptedList(`json parse failed: ${String(e)}`);
  }
  if (!isWireObject(parsed as TdWireValue)) {
    return corruptedList('manifest is not an object');
  }
  const wire: TdWireObject = parsed as TdWireObject;
  const version: number = wireNumber(wire['schemaVersion'], 0);
  if (version !== 1) {
    return corruptedList(`unsupported manifest schemaVersion: ${version}`);
  }
  const accounts: TdWireValue | undefined = wire['accounts'];
  if (accounts === undefined || accounts === null || !Array.isArray(accounts)) {
    return corruptedList('manifest accounts is not an array');
  }
  const out: AccountDescriptor[] = [];
  for (const item of accounts) {
    if (!isWireObject(item)) {
      return corruptedList('manifest entry is not an object');
    }
    const decoded: Result<AccountDescriptor, AppError> = descriptorFromWire(item as TdWireObject);
    if (decoded.ok === false) {
      return err<AccountDescriptor[], AppError>(decoded.error);
    }
    out.push(decoded.value);
  }
  return ok<AccountDescriptor[], AppError>(out);
}

function descriptorFromWire(wire: TdWireObject): Result<AccountDescriptor, AppError> {
  const accountKey: string = wireString(wire['accountKey']);
  if (accountKey.length === 0) {
    return corrupted('accountKey missing or empty');
  }
  const accountId: string = wireString(wire['accountId']);
  if (accountId.length === 0) {
    return corrupted('accountId missing or empty');
  }
  const createdAtMillis: number = wireNumber(wire['createdAtMillis'], -1);
  if (!Number.isFinite(createdAtMillis) || createdAtMillis < 0) {
    return corrupted('createdAtMillis missing or negative');
  }
  const enabledValue: TdWireValue | undefined = wire['enabled'];
  if (typeof enabledValue !== 'boolean') {
    return corrupted('enabled missing or not boolean');
  }
  return ok<AccountDescriptor, AppError>(createDescriptor(accountKey, accountId, createdAtMillis, enabledValue));
}

function corrupted(cause: string): Result<AccountDescriptor, AppError> {
  return err<AccountDescriptor, AppError>(
    AppErrors.storage('corrupted', 'account descriptor data is corrupted', false, undefined, cause)
  );
}

function corruptedList(cause: string): Result<AccountDescriptor[], AppError> {
  return err<AccountDescriptor[], AppError>(
    AppErrors.storage('corrupted', 'account manifest data is corrupted', false, undefined, cause)
  );
}
