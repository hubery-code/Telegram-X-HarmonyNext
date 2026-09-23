import profileReducerTest from './ProfileReducer.test';
import chatProfileReducerTest from './ChatProfileReducer.test';
import sharedMediaPlaceholderTest from './SharedMediaPlaceholder.test';
import profileNotificationTest from './ProfileNotification.test';
import profileMenuTest from './ProfileMenu.test';

export default function testsuite(): void {
  profileReducerTest();
  chatProfileReducerTest();
  sharedMediaPlaceholderTest();
  profileNotificationTest();
  profileMenuTest();
}
