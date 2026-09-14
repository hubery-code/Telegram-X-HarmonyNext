/**
 * entry — HarmonyOS 系统 Hilog 日志 Sink（ARCH-001 / P1-ARCH-002）。
 *
 * 将 core/observability 脱敏经过白名单过滤的日志行输出至系统 hilog。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogLevel, LogSink, Logger } from '@tgx/observability';

const DOMAIN: number = 0x0000;
const TAG: string = 'TelegramX';

export const harmonyHilogSink: LogSink = (level: LogLevel, line: string): void => {
  switch (level) {
    case 'debug':
      hilog.debug(DOMAIN, TAG, '%{public}s', line);
      break;
    case 'info':
      hilog.info(DOMAIN, TAG, '%{public}s', line);
      break;
    case 'warn':
      hilog.warn(DOMAIN, TAG, '%{public}s', line);
      break;
    case 'error':
      hilog.error(DOMAIN, TAG, '%{public}s', line);
      break;
  }
};

export function createHarmonyLogger(minLevel: LogLevel = 'info'): Logger {
  return new Logger(minLevel, harmonyHilogSink);
}
