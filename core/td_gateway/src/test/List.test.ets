import requestRegistryTest from './RequestRegistry.test';
import orderedEventRouterTest from './OrderedEventRouter.test';
import tdGatewayTest from './TdGateway.test';

export default function testsuite() {
  requestRegistryTest();
  orderedEventRouterTest();
  tdGatewayTest();
}
