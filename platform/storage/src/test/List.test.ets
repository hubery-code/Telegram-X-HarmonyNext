import preferenceStoreCoreTest from './PreferenceStoreCore.test';
import rdbKvCodecTest from './RdbKvCodec.test';
import rdbKvStatementsTest from './RdbKvStatements.test';
import migrationPlanTest from './MigrationPlan.test';
import migrationRunnerTest from './MigrationRunner.test';

export default function testsuite() {
  preferenceStoreCoreTest();
  rdbKvCodecTest();
  rdbKvStatementsTest();
  migrationPlanTest();
  migrationRunnerTest();
}
