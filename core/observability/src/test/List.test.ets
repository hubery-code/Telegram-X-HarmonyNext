import tdRedactJsonTest from './TdRedactJson.test';
import tdRedactFieldsTest from './TdRedactFields.test';
import whitelistLoggerTest from './WhitelistLogger.test';

export default function testsuite() {
  tdRedactJsonTest();
  tdRedactFieldsTest();
  whitelistLoggerTest();
}
