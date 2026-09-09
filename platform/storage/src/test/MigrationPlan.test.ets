import { describe, it, expect } from '@ohos/hypium';
import { MigrationStep, planMigrations } from '../main/ets/core/MigrationPlan';
import { SqlStatement } from '../main/ets/core/RdbKvStatements';

function stmt(sql: string): SqlStatement {
  return { sql: sql, args: [] };
}

/** 构造 from -> from+1 的步骤，up/down 各 n/m 条语句。 */
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

export default function migrationPlanTest() {
  describe('MigrationPlan', () => {
    it('equalVersions_yieldsEmptyPlan', 0, () => {
      const plan = planMigrations([step(1, 1, 1)], 2, 2);
      expect(plan.ok).assertTrue();
      if (plan.ok) {
        expect(plan.value.steps.length).assertEqual(0);
        expect(plan.value.direction).assertEqual('up');
      }
    });

    it('upgradePlansOrderedChain', 0, () => {
      const s12 = step(1, 2, 1);
      const s23 = step(2, 1, 2);
      const plan = planMigrations([s23, s12], 1, 3);
      expect(plan.ok).assertTrue();
      if (plan.ok) {
        expect(plan.value.direction).assertEqual('up');
        expect(plan.value.steps.length).assertEqual(2);
        expect(plan.value.steps[0].fromVersion).assertEqual(1);
        expect(plan.value.steps[1].fromVersion).assertEqual(2);
      }
    });

    it('versionJump_traversesIntermediateSteps', 0, () => {
      const plan = planMigrations([step(1, 1, 1), step(2, 1, 1), step(3, 1, 1)], 1, 4);
      expect(plan.ok).assertTrue();
      if (plan.ok) {
        expect(plan.value.steps.length).assertEqual(3);
      }
    });

    it('gapInChain_returnsMigrationError', 0, () => {
      const plan = planMigrations([step(1, 1, 1), step(3, 1, 1)], 1, 3);
      expect(plan.err).assertTrue();
      if (plan.err) {
        expect(plan.error.kind).assertEqual('storage');
        if (plan.error.kind === 'storage') {
          expect(plan.error.code).assertEqual('migration');
        }
      }
    });

    it('unknownStoredVersion_returnsMigrationError', 0, () => {
      const plan = planMigrations([step(1, 1, 1)], 7, 2);
      expect(plan.err).assertTrue();
      if (plan.err) {
        expect(plan.error.kind).assertEqual('storage');
      }
    });

    it('invalidVersions_returnParameterError', 0, () => {
      expect(planMigrations([], 0, 1).err).assertTrue();
      expect(planMigrations([], 1, 0).err).assertTrue();
      expect(planMigrations([], 1.5, 2).err).assertTrue();
    });

    it('downgradePlansReverseChain', 0, () => {
      const s12 = step(1, 1, 2);
      const s23 = step(2, 1, 1);
      const plan = planMigrations([s12, s23], 3, 1);
      expect(plan.ok).assertTrue();
      if (plan.ok) {
        expect(plan.value.direction).assertEqual('down');
        expect(plan.value.steps.length).assertEqual(2);
        expect(plan.value.steps[0].fromVersion).assertEqual(2);
        expect(plan.value.steps[1].fromVersion).assertEqual(1);
      }
    });

    it('stepWithoutDownStatements_rejectsRollback', 0, () => {
      const s12 = step(1, 1, 0);
      const plan = planMigrations([s12], 2, 1);
      expect(plan.err).assertTrue();
      if (plan.err) {
        expect(plan.error.kind).assertEqual('storage');
        if (plan.error.kind === 'storage') {
          expect(plan.error.code).assertEqual('migration');
        }
      }
    });

    it('metadataOnlyStep_allowsBothDirections', 0, () => {
      const bump: MigrationStep = { fromVersion: 4, toVersion: 5, up: [], down: [] };
      expect(planMigrations([bump], 4, 5).ok).assertTrue();
      expect(planMigrations([bump], 5, 4).ok).assertTrue();
    });
  });
}
