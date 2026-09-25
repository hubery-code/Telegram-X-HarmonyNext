import chatRegistryTest from './chatlist/ChatRegistry.test';
import chatListProjectionTest from './chatlist/ChatListProjection.test';
import messageProjectionTest from './chat/MessageProjection.test';
import chatMuteTest from './chat/ChatMute.test';
import chatSendRightsTest from './chat/ChatSendRights.test';
import fileRegistryTest from './file/FileRegistry.test';
import fileStoreTest from './file/FileStore.test';
import userRegistryTest from './user/UserRegistry.test';
import groupRegistryTest from './group/GroupRegistry.test';
import autoDownloadPolicyTest from './media/AutoDownloadPolicy.test';
import dataSaverTest from './media/DataSaver.test';

export default function testsuite() {
  chatRegistryTest();
  chatListProjectionTest();
  messageProjectionTest();
  chatMuteTest();
  chatSendRightsTest();
  fileRegistryTest();
  fileStoreTest();
  userRegistryTest();
  groupRegistryTest();
  autoDownloadPolicyTest();
}
