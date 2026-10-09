/**
 * entry/src/test/tdlog/TdLibLogSink.test.ets — TDLib 内部日志落盘（TDLOG-BRIDGE-101）。
 *
 * 这里测的全是「读数」：发了几条、顺序对不对、字段名是不是 TDLib 认的那套、
 * 失败能不能归因到具体某一步，以及最要紧的一条——TDLib 的应答原文绝不能
 * 从返回值里漏出来（它带的是服务器侧的措辞，本仓口径是原文不进普通日志）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  enableTdLibLogFileSink,
  tdLibLogFilePath,
  tdLibSetLogStreamRequestUtf8,
  tdLibSetLogVerbosityRequestUtf8,
  TDLIB_LOG_MAX_FILE_BYTES,
  TDLIB_LOG_VERBOSITY_DEBUG,
  TdLibLogSinkOutcome,
  TdLibLogSinkRequest,
  TdSyncExecuteFn
} from '../../main/ets/tdlog/TdLibLogSink';

/** 记录每一条 execute 的载荷，并按脚本回话；脚本用完一律回 ok。 */
class FakeExecutor {
  readonly requests: string[] = [];
  private readonly responses: string[] = [];
  private nullNext: boolean = false;
  throwAt: number = -1;

  /** 第一条应答为 null（native execute 无返回的形态）。 */
  firstResponseNull(): FakeExecutor {
    this.nullNext = true;
    return this;
  }

  addResponse(response: string): FakeExecutor {
    this.responses.push(response);
    return this;
  }

  execute(requestUtf8: string): string | null {
    this.requests.push(requestUtf8);
    if (this.throwAt === this.requests.length - 1) {
      throw new Error('bridge exploded');
    }
    if (this.nullNext) {
      this.nullNext = false;
      return null;
    }
    const scripted: string | undefined = this.responses.shift();
    return scripted !== undefined ? scripted : '{"@type":"ok"}';
  }
}

const OK_RESPONSE: string = '{"@type":"ok"}';
const FILES_DIR: string = '/data/app/el2/100/base/org.telegram.x.harmony/files';
const LOG_PATH: string = `${FILES_DIR}/tdlib.log`;
const STREAM_REQUEST: string = tdLibSetLogStreamRequestUtf8(LOG_PATH, TDLIB_LOG_MAX_FILE_BYTES);
const VERBOSITY_REQUEST: string = tdLibSetLogVerbosityRequestUtf8(TDLIB_LOG_VERBOSITY_DEBUG);

function debugRequest(): TdLibLogSinkRequest {
  return { filesDir: FILES_DIR, debugBuild: true };
}

/** 与生产同一个包法：把执行器的 execute 收成闭包。 */
function runSink(executor: FakeExecutor, request: TdLibLogSinkRequest): TdLibLogSinkOutcome {
  const execute: TdSyncExecuteFn = (requestUtf8: string): string | null => executor.execute(requestUtf8);
  return enableTdLibLogFileSink(execute, request);
}

export default function tdLibLogSinkTest() {
  describe('TdLibLogSinkTest', () => {
    it('debug_build_sends_stream_then_verbosity_and_reports_applied', 0, () => {
      const executor: FakeExecutor = new FakeExecutor();
      const outcome: TdLibLogSinkOutcome = runSink(executor, debugRequest());

      expect(executor.requests.length).assertEqual(2);
      expect(executor.requests[0]).assertEqual(STREAM_REQUEST);
      expect(executor.requests[1]).assertEqual(VERBOSITY_REQUEST);
      expect(outcome.status).assertEqual('applied');
      expect(outcome.step).assertEqual('');
      expect(outcome.path).assertEqual(LOG_PATH);
      expect(outcome.verbosity).assertEqual(4);
    });

    it('set_log_stream_wire_shape_is_exactly_what_tdlib_parses', 0, () => {
      expect(STREAM_REQUEST).assertEqual(
        '{"@type":"setLogStream","log_stream":{"@type":"logStreamFile",' +
        `"path":"${LOG_PATH}","max_file_size":4194304,"redirect_stderr":false}}`
      );
      expect(VERBOSITY_REQUEST).assertEqual('{"@type":"setLogVerbosityLevel","new_verbosity_level":4}');
    });

    it('release_build_sends_nothing', 0, () => {
      const executor: FakeExecutor = new FakeExecutor();
      const release: TdLibLogSinkRequest = { filesDir: FILES_DIR, debugBuild: false };
      const outcome: TdLibLogSinkOutcome = runSink(executor, release);

      expect(executor.requests.length).assertEqual(0);
      expect(outcome.status).assertEqual('skipped_not_debug');
      expect(outcome.path).assertEqual(LOG_PATH);
    });

    it('path_lives_in_files_dir_root_and_tolerates_trailing_slash', 0, () => {
      expect(tdLibLogFilePath(FILES_DIR)).assertEqual(LOG_PATH);
      expect(tdLibLogFilePath(`${FILES_DIR}/`)).assertEqual(LOG_PATH);
    });

    it('null_response_stops_at_the_stream_step', 0, () => {
      const executor: FakeExecutor = new FakeExecutor().firstResponseNull();
      const outcome: TdLibLogSinkOutcome = runSink(executor, debugRequest());

      expect(executor.requests.length).assertEqual(1);
      expect(outcome.status).assertEqual('no_response');
      expect(outcome.step).assertEqual('setLogStream');
    });

    it('unparsable_response_is_classified_not_thrown', 0, () => {
      const executor: FakeExecutor = new FakeExecutor().addResponse('not json at all');
      const outcome: TdLibLogSinkOutcome = runSink(executor, debugRequest());

      expect(outcome.status).assertEqual('unparsable');
      expect(outcome.step).assertEqual('setLogStream');
    });

    it('tdlib_error_stops_the_chain_before_touching_verbosity', 0, () => {
      const executor: FakeExecutor =
        new FakeExecutor().addResponse('{"@type":"error","code":400,"message":"some TDLib wording we must not echo"}');
      const outcome: TdLibLogSinkOutcome = runSink(executor, debugRequest());

      expect(executor.requests.length).assertEqual(1);
      expect(outcome.status).assertEqual('rejected');
      expect(outcome.step).assertEqual('setLogStream');
      // 隐私口径的回归：返回值只有状态码与步骤，没有 TDLib 原文。
      expect(JSON.stringify(outcome).indexOf('some TDLib wording') < 0).assertTrue();
    });

    it('verbosity_failure_is_attributed_to_its_own_step', 0, () => {
      const executor: FakeExecutor =
        new FakeExecutor().addResponse(OK_RESPONSE).addResponse('{"@type":"error","code":404}');
      const outcome: TdLibLogSinkOutcome = runSink(executor, debugRequest());

      expect(executor.requests.length).assertEqual(2);
      expect(outcome.status).assertEqual('rejected');
      expect(outcome.step).assertEqual('setLogVerbosityLevel');
    });

    it('exploding_bridge_is_contained', 0, () => {
      const executor: FakeExecutor = new FakeExecutor();
      executor.throwAt = 0;
      const outcome: TdLibLogSinkOutcome = runSink(executor, debugRequest());

      expect(outcome.status).assertEqual('threw');
      expect(outcome.step).assertEqual('setLogStream');
    });

    it('verbosity_and_rotation_size_are_overridable', 0, () => {
      const executor: FakeExecutor = new FakeExecutor();
      const tuned: TdLibLogSinkRequest = {
        filesDir: FILES_DIR,
        debugBuild: true,
        verbosity: 5,
        maxFileBytes: 1024
      };
      const outcome: TdLibLogSinkOutcome = runSink(executor, tuned);

      expect(outcome.verbosity).assertEqual(5);
      expect(executor.requests[0]).assertEqual(tdLibSetLogStreamRequestUtf8(LOG_PATH, 1024));
      expect(executor.requests[1]).assertEqual('{"@type":"setLogVerbosityLevel","new_verbosity_level":5}');
    });
  });
}
