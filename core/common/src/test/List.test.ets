import resultTest from './Result.test';
import appErrorTest from './AppError.test';
import clockTest from './Clock.test';
import idGeneratorTest from './Id.test';

export default function testsuite() {
  resultTest();
  appErrorTest();
  clockTest();
  idGeneratorTest();
}
