import chatRegistryTest from './chatlist/ChatRegistry.test';
import chatListProjectionTest from './chatlist/ChatListProjection.test';
import fileRegistryTest from './file/FileRegistry.test';
import fileStoreTest from './file/FileStore.test';
import userRegistryTest from './user/UserRegistry.test';

export default function testsuite() {
  chatRegistryTest();
  chatListProjectionTest();
  fileRegistryTest();
  fileStoreTest();
  userRegistryTest();
}
