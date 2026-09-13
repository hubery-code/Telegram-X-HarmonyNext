import chatReducerTest from './ChatReducer.test';
import formattedTextParserTest from './FormattedTextParser.test';
import senderInfoTest from './SenderInfo.test';
import readReceiptTest from './ReadReceipt.test';
import mediaAttachmentTest from './MediaAttachment.test';
import mediaViewerTest from './MediaViewer.test';
import forwardSelectionTest from './ForwardSelection.test';
import dateAndUnreadSeparatorTest from './DateAndUnreadSeparator.test';

export default function testsuite(): void {
  chatReducerTest();
  formattedTextParserTest();
  senderInfoTest();
  readReceiptTest();
  mediaAttachmentTest();
  mediaViewerTest();
  forwardSelectionTest();
  dateAndUnreadSeparatorTest();
}
