import chatRegistryTest from './chatlist/ChatRegistry.test';
import chatListProjectionTest from './chatlist/ChatListProjection.test';
import messageProjectionTest from './chat/MessageProjection.test';
import fileRegistryTest from './file/FileRegistry.test';
import fileStoreTest from './file/FileStore.test';
import userRegistryTest from './user/UserRegistry.test';
import groupRegistryTest from './group/GroupRegistry.test';

export default function testsuite() {
  chatRegistryTest();
  chatListProjectionTest();
  messageProjectionTest();
  fileRegistryTest();
  fileStoreTest();
  userRegistryTest();
  groupRegistryTest();
}
