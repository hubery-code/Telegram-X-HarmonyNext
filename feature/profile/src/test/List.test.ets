import profileReducerTest from './ProfileReducer.test';
import chatProfileReducerTest from './ChatProfileReducer.test';

export default function testsuite(): void {
  profileReducerTest();
  chatProfileReducerTest();
}
