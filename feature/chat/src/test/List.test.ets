import chatReducerTest from './ChatReducer.test';
import formattedTextParserTest from './FormattedTextParser.test';

export default function testsuite(): void {
  chatReducerTest();
  formattedTextParserTest();
}
