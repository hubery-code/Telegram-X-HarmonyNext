import mappingTest from './ConnectivityMapping.test';
import deduperTest from './SnapshotDeduper.test';
import adapterContractTest from './ConnectivityAdapterContract.test';

export default function testsuite() {
  mappingTest();
  deduperTest();
  adapterContractTest();
}
