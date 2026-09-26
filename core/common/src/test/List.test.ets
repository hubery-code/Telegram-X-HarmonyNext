import resultTest from './Result.test';
import appErrorTest from './AppError.test';
import clockTest from './Clock.test';
import idGeneratorTest from './Id.test';
import base64Test from './Base64.test';
import langTest from './Lang.test';
import a11ySlotsTest from './A11ySlots.test';

export default function testsuite() {
  resultTest();
  appErrorTest();
  clockTest();
  idGeneratorTest();
  base64Test();
  langTest();
  a11ySlotsTest();
}
