/**
 * entry — TDLib 内部日志落盘（TDLOG-BRIDGE-101）。
 *
 * 为什么不走「给 napi 桥装 `td_set_log_message_callback`」这条更显眼的路：
 * TDLib 的 `setLogStream` / `setLogVerbosityLevel` 在 schema 里标了
 * 「Can be called synchronously」（td_api.tl:16232-16249），也就是可以直接经
 * 现有同步 execute 口发出去。native 侧 `Execute` 用的正是全局无 client 的
 * `td_execute`（tdcore_napi.cpp:443），所以这条路零 native 改动、零 .so 重编、
 * 零新增跨线程回调。回调那条路要把 TDLib 原文逐条搬进 hilog，与本仓
 * 「TDLib 原文不进普通日志」的隐私口径直接冲突；文件这条路把原文留在应用
 * 沙盒里，取证时 `hdc file recv` 单取一份，取完删。
 *
 * 三条实测口径（都写进 PROGRESS 第四十八轮）：
 * 1. 开之前模拟器上 TDLib 内部日志在 hilog 里是**零条**（7929 行全量抓取，
 *    只有本仓自己的 `A00000/org.telegram.x.harmony/TelegramX` 标签）；
 *    默认日志流是 stderr，鸿蒙这边没人接。
 * 2. 只有 debug 包开（`appInfo.debug`，实测本机 `bm dump` 读到 `"debug": true`）；
 *    正式包不开，避免把服务器原文长期写在盘上。
 * 3. 单步失败就停，不做「第二路兜底」——这两条请求是 TDLib 全局态，
 *    第一条（日志流）没设上，第二条（等级）设了也白设。
 *
 * Kit-free：只依赖生成 DTO（GEN-002）与一个 `execute` 闭包，
 * 单测注入假执行器就能验请求体、顺序与四条失败分支。
 */

import {
  LogStreamFile,
  SetLogStream,
  SetLogVerbosityLevel,
  encodeSetLogStream,
  encodeSetLogVerbosityLevel
} from '@tgx/core-td-api-generated';
import { TdWireObject, TdWireValue } from '@tgx/td-gateway';

/**
 * 同步 execute 的函数形态。
 *
 * 刻意不定义成接口：ArkTS 既不做结构类型匹配（`TdNativeBridgeLike` 不能当
 * `TdSyncExecutor` 用），也不接受带方法的对象字面量，两头都堵。调用方交一个
 * 闭包进来（生产由 EntryAbility 包 `bridge.execute`，测试包假执行器），
 * 本模块要的就只是「发一条同步请求、拿回原文」这一个动作。
 */
export type TdSyncExecuteFn = (requestUtf8: string) => string | null;

/** 日志文件名。放在 filesDir 根目录：这个目录一定已存在，不额外建目录。 */
export const TDLIB_LOG_FILE_NAME: string = 'tdlib.log';
/** TDLib 自己轮转的上限（logStreamFile.max_file_size）；4 MB 够装一次完整复现。 */
export const TDLIB_LOG_MAX_FILE_BYTES: number = 4 * 1024 * 1024;
/**  verbosity 语义（td_api setLogVerbosityLevel 注释）：3=info、4=debug、5=verbose。 */
export const TDLIB_LOG_VERBOSITY_DEBUG: number = 4;
/** TDLib 对同步控制请求的肯定应答。 */
const TDLIB_OK_TYPE: string = 'ok';

export type TdLibLogSinkStatus =
  | 'applied'
  | 'skipped_not_debug'
  | 'no_response'
  | 'unparsable'
  | 'rejected'
  | 'threw';

export type TdLibLogSinkStep = '' | 'setLogStream' | 'setLogVerbosityLevel';

export interface TdLibLogSinkOutcome {
  readonly status: TdLibLogSinkStatus;
  /** 失败发生在哪一步；'applied' / 'skipped_not_debug' 时为空串。 */
  readonly step: TdLibLogSinkStep;
  readonly path: string;
  readonly verbosity: number;
}

export interface TdLibLogSinkRequest {
  readonly filesDir: string;
  /** 只有 debug 包才开；由调用方读 `appInfo.debug` 传进来，本模块不碰 Kit。 */
  readonly debugBuild: boolean;
  readonly verbosity?: number;
  readonly maxFileBytes?: number;
}

export function tdLibLogFilePath(filesDir: string): string {
  const trimmed: string = filesDir.endsWith('/') ? filesDir.substring(0, filesDir.length - 1) : filesDir;
  return `${trimmed}/${TDLIB_LOG_FILE_NAME}`;
}

/** `{"@type":"setLogStream","log_stream":{"@type":"logStreamFile",...}}` */
export function tdLibSetLogStreamRequestUtf8(path: string, maxFileBytes: number): string {
  const file: LogStreamFile = new LogStreamFile();
  file.path = path;
  file.max_file_size = maxFileBytes;
  file.redirect_stderr = false;

  const request: SetLogStream = new SetLogStream();
  request.log_stream = file;
  return JSON.stringify(encodeSetLogStream(request));
}

/** `{"@type":"setLogVerbosityLevel","new_verbosity_level":N}` */
export function tdLibSetLogVerbosityRequestUtf8(verbosity: number): string {
  const request: SetLogVerbosityLevel = new SetLogVerbosityLevel();
  request.new_verbosity_level = verbosity;
  return JSON.stringify(encodeSetLogVerbosityLevel(request));
}

/**
 * 装日志流：先 `setLogStream` 再 `setLogVerbosityLevel`（顺序反了会丢掉第一条
 * 等级变更自身的日志）。任何一步不成都只回状态码，**绝不抛出**，也绝不把
 * TDLib 的应答原文带进返回值——调用方拿到的只有 status/step。
 */
export function enableTdLibLogFileSink(
  execute: TdSyncExecuteFn,
  request: TdLibLogSinkRequest
): TdLibLogSinkOutcome {
  const path: string = tdLibLogFilePath(request.filesDir);
  const verbosity: number = request.verbosity !== undefined ? request.verbosity : TDLIB_LOG_VERBOSITY_DEBUG;
  const maxFileBytes: number = request.maxFileBytes !== undefined ? request.maxFileBytes : TDLIB_LOG_MAX_FILE_BYTES;

  if (!request.debugBuild) {
    return { status: 'skipped_not_debug', step: '', path: path, verbosity: verbosity };
  }

  const streamStatus: TdLibLogSinkStatus = sendSyncRequest(execute, tdLibSetLogStreamRequestUtf8(path, maxFileBytes));
  if (streamStatus !== 'applied') {
    return { status: streamStatus, step: 'setLogStream', path: path, verbosity: verbosity };
  }

  const levelStatus: TdLibLogSinkStatus = sendSyncRequest(execute, tdLibSetLogVerbosityRequestUtf8(verbosity));
  if (levelStatus !== 'applied') {
    return { status: levelStatus, step: 'setLogVerbosityLevel', path: path, verbosity: verbosity };
  }

  return { status: 'applied', step: '', path: path, verbosity: verbosity };
}

function sendSyncRequest(execute: TdSyncExecuteFn, requestUtf8: string): TdLibLogSinkStatus {
  let response: string | null;
  try {
    response = execute(requestUtf8);
  } catch (e) {
    return 'threw';
  }
  if (response === undefined || response === null) {
    return 'no_response';
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(response);
  } catch (e) {
    return 'unparsable';
  }
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
    return 'unparsable';
  }
  const record: TdWireObject = parsed as TdWireObject;
  const typeValue: TdWireValue | undefined = record['@type'];
  if (typeof typeValue === 'string' && typeValue === TDLIB_OK_TYPE) {
    return 'applied';
  }
  return 'rejected';
}
