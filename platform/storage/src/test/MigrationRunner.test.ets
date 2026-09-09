import { describe, it, expect } from '@ohos/hypium';
import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { MigrationStep } from '../main/ets/core/MigrationPlan';
import { SqlStatement, RdbKvStatements } from '../main/ets/core/RdbKvStatements';
import { SqlExecutor, runMigrations } from '../main/ets/core/MigrationRunner';

function stmt(sql: string): SqlStatement {
  return { sql: sql, args: [] };
}

function step(from: number, upCount: number, downCount: number): MigrationStep {
  const up: SqlStatement[] = [];
  for (let i = 0; i < upCount; i++) {
    up.push(stmt(`up-${from}-${i}`));
  }
  const down: SqlStatement[] = [];
  for (let i = 0; i < downCount; i++) {
    down.push(stmt(`down-${from}-${i}`));
  }
  return { fromVersion: from, toVersion: from + 1, up: up, down: down };
}

const STEPS: MigrationStep[] = [step(1, 2, 1), step(2, 1, 1)];

/** 记录执行序列、可在第 N 次 exec 注入一次失败的 fake（模拟写一半中断）。 */
class FakeExecutor implements SqlExecutor {
  readonly executed: SqlStatement[] = [];
  failAtIndex: number = -1;
  private failUsed: boolean = false;

  async exec(statement: SqlStatement): Promise<Result<void, AppError>> {
    const index: number = this.executed.length;
    this.executed.push(statement);
    if (this.failAtIndex === index && !this.failUsed) {
      this.failUsed = true;
      return err(AppErrors.storage('io', 'injected exec failure mid-migration', true));
    }
    return ok(undefined);
  }

  sqlSequence(): string[] {
    const out: string[] = [];
    for (const s of this.executed) {
      out.push(s.sql);
    }
    return out;
  }
}

function versionMark(version: number): SqlStatement {
  return RdbKvStatements.upsertUserVersion(version);
}

function isVersionMark(sql: string): boolean {
  return sql.indexOf('tgx_meta') >= 0;
}

export default function migrationRunnerTest() {
  describe('MigrationRunner', () => {
    it('equalVersions_isNoOp', 0, async () => {
      const executor = new FakeExecutor();
      const r = await runMigrations(executor, STEPS, 2, 2, versionMark);
      expect(r.getOrNull()).assertEqual(2);
      expect(executor.executed.length).assertEqual(0);
    });

    it('upgradeExecutesStepsInOrderWithVersionMarkAfterEachStep', 0, async () => {
      const executor = new FakeExecutor();
      const r = await runMigrations(executor, STEPS, 1, 3, versionMark);
      expect(r.getOrNull()).assertEqual(3);
      const seq: string[] = executor.sqlSequence();
      expect(seq.length).assertEqual(5);
      expect(seq[0]).assertEqual('up-1-0');
      expect(seq[1]).assertEqual('up-1-1');
      expect(isVersionMark(seq[2])).assertTrue();
      expect(seq[3]).assertEqual('up-2-0');
      expect(isVersionMark(seq[4])).assertTrue();
    });

    it('interruptionMidStep_failsAndLeavesVersionAtLastCompletedStep', 0, async () => {
      const executor = new FakeExecutor();
      executor.failAtIndex = 1;
      const r = await runMigrations(executor, STEPS, 1, 3, versionMark);
      expect(r.err).assertTrue();
      const marks: number = executor.sqlSequence().filter(isVersionMark).length;
      expect(marks).assertEqual(0);
    });

    it('interruptionMidStep_resumeFromStoredVersionCompletes', 0, async () => {
      const executor = new FakeExecutor();
      executor.failAtIndex = 1;
      const failed = await runMigrations(executor, STEPS, 1, 3, versionMark);
      expect(failed.err).assertTrue();

      executor.failAtIndex = -1;
      const resumed = await runMigrations(executor, STEPS, 1, 3, versionMark);
      expect(resumed.getOrNull()).assertEqual(3);
    });

    it('interruptionAtSecondStep_resumesFromVersion2', 0, async () => {
      const executor = new FakeExecutor();
      executor.failAtIndex = 3;
      const failed = await runMigrations(executor, STEPS, 1, 3, versionMark);
      expect(failed.err).assertTrue();

      executor.failAtIndex = -1;
      const resumed = await runMigrations(executor, STEPS, 2, 3, versionMark);
      expect(resumed.getOrNull()).assertEqual(3);
      const tail: string[] = executor.sqlSequence().slice(4);
      expect(tail[0]).assertEqual('up-2-0');
    });

    it('failedVersionMark_failsAndRerunCompletes', 0, async () => {
      const executor = new FakeExecutor();
      executor.failAtIndex = 2;
      const r = await runMigrations(executor, STEPS, 1, 3, versionMark);
      expect(r.err).assertTrue();
      // 失败点恰为版本标记语句：步骤语句已全部执行，但版本未被推进。
      expect(isVersionMark(executor.executed[2].sql)).assertTrue();

      executor.failAtIndex = -1;
      const resumed = await runMigrations(executor, STEPS, 1, 3, versionMark);
      expect(resumed.getOrNull()).assertEqual(3);
    });

    it('downgradeExecutesDownStatementsInReverseOrder', 0, async () => {
      const executor = new FakeExecutor();
      const r = await runMigrations(executor, STEPS, 3, 1, versionMark);
      expect(r.getOrNull()).assertEqual(1);
      const seq: string[] = executor.sqlSequence();
      expect(seq.length).assertEqual(4);
      expect(seq[0]).assertEqual('down-2-0');
      expect(isVersionMark(seq[1])).assertTrue();
      expect(seq[2]).assertEqual('down-1-0');
      expect(isVersionMark(seq[3])).assertTrue();
    });

    it('versionJumpFrom1To3_runsFullChain', 0, async () => {
      const executor = new FakeExecutor();
      const r = await runMigrations(executor, STEPS, 1, 3, versionMark);
      expect(r.ok).assertTrue();
      expect(executor.sqlSequence().filter((s: string) => !isVersionMark(s)).length).assertEqual(3);
    });

    it('planFailure_surfacesAsError', 0, async () => {
      const executor = new FakeExecutor();
      const r = await runMigrations(executor, STEPS, 1, 5, versionMark);
      expect(r.err).assertTrue();
      if (r.err) {
        expect(r.error.kind).assertEqual('storage');
        if (r.error.kind === 'storage') {
          expect(r.error.code).assertEqual('migration');
        }
      }
      expect(executor.executed.length).assertEqual(0);
    });
  });
}
