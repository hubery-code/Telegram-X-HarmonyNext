import chatRegistryTest from './chatlist/ChatRegistry.test';
import chatListProjectionTest from './chatlist/ChatListProjection.test';

export default function testsuite() {
  chatRegistryTest();
  chatListProjectionTest();
}
