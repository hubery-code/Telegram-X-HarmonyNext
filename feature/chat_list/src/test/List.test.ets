import chatListReducerTest from './ChatListReducer.test';
import chatListDrawerReducerTest from './ChatListDrawerReducer.test';
import chatListGroupCreateReducerTest from './ChatListGroupCreateReducer.test';
import drawerStateTest from './DrawerState.test';
import chatListOverlayBackTest from './ChatListOverlayBack.test';

export default function testsuite(): void {
  chatListReducerTest();
  chatListDrawerReducerTest();
  chatListGroupCreateReducerTest();
  drawerStateTest();
  chatListOverlayBackTest();
}
