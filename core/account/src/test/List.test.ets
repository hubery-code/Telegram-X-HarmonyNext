import accountLifecycleTest from './AccountLifecycle.test';
import accountDescriptorTest from './AccountDescriptor.test';
import accountScopeTest from './AccountScope.test';
import accountRegistryTest from './AccountRegistry.test';
import authorizationStateMachineTest from './AuthorizationStateMachine.test';
import accountDatabaseKeyManagerTest from './AccountDatabaseKeyManager.test';

export default function testsuite() {
  accountLifecycleTest();
  accountDescriptorTest();
  accountScopeTest();
  accountRegistryTest();
  authorizationStateMachineTest();
  accountDatabaseKeyManagerTest();
}
