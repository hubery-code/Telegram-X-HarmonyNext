import chatReducerTest from './ChatReducer.test';
import formattedTextParserTest from './FormattedTextParser.test';
import senderInfoTest from './SenderInfo.test';

export default function testsuite(): void {
  chatReducerTest();
  formattedTextParserTest();
  senderInfoTest();
}
