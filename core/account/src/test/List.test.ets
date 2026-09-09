import accountLifecycleTest from './AccountLifecycle.test';
import accountDescriptorTest from './AccountDescriptor.test';
import accountScopeTest from './AccountScope.test';
import accountRegistryTest from './AccountRegistry.test';

export default function testsuite() {
  accountLifecycleTest();
  accountDescriptorTest();
  accountScopeTest();
  accountRegistryTest();
}
