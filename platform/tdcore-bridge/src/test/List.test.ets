import tdCoreBridgeTest from './TdCoreBridge.test';
import bridgeSoakTest from './BridgeSoak.test';

export default function testsuite() {
  tdCoreBridgeTest();
  bridgeSoakTest();
}

