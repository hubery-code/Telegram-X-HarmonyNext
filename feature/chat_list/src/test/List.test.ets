import chatListReducerTest from './ChatListReducer.test';
import chatListDrawerReducerTest from './ChatListDrawerReducer.test';
import drawerStateTest from './DrawerState.test';

export default function testsuite(): void {
  chatListReducerTest();
  chatListDrawerReducerTest();
  drawerStateTest();
}
