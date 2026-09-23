import profileReducerTest from './ProfileReducer.test';
import chatProfileReducerTest from './ChatProfileReducer.test';
import sharedMediaPlaceholderTest from './SharedMediaPlaceholder.test';
import profileNotificationTest from './ProfileNotification.test';

export default function testsuite(): void {
  profileReducerTest();
  chatProfileReducerTest();
  sharedMediaPlaceholderTest();
  profileNotificationTest();
}
