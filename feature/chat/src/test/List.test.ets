import chatReducerTest from './ChatReducer.test';
import formattedTextParserTest from './FormattedTextParser.test';
import senderInfoTest from './SenderInfo.test';
import readReceiptTest from './ReadReceipt.test';
import mediaAttachmentTest from './MediaAttachment.test';
import mediaViewerTest from './MediaViewer.test';
import forwardSelectionTest from './ForwardSelection.test';
import dateAndUnreadSeparatorTest from './DateAndUnreadSeparator.test';
import mosaicLayoutTest from './MosaicLayout.test';
import mediaAlbumTest from './MediaAlbum.test';
import chatPhotoSendingTest from './ChatPhotoSending.test';
import chatFileSendingTest from './ChatFileSending.test';
import linkPreviewTest from './LinkPreview.test';
import chatSearchJumpTest from './ChatSearchJump.test';
import commentsCoordinatorTest from './CommentsCoordinator.test';
import mediaRedownloadTest from './MediaRedownload.test';
import chatMuteStateTest from './ChatMuteState.test';
import privateChatHeaderProfileTest from './PrivateChatHeaderProfile.test';
import viewerTransformTest from './ViewerTransform.test';
import viewerPlaybackTest from './ViewerPlayback.test';
import chatAppLinkDispatchTest from './ChatAppLinkDispatch.test';
import stickerSendVetoTest from './StickerSendVeto.test';

export default function testsuite(): void {
  chatReducerTest();
  formattedTextParserTest();
  senderInfoTest();
  readReceiptTest();
  mediaAttachmentTest();
  mediaViewerTest();
  forwardSelectionTest();
  dateAndUnreadSeparatorTest();
  mosaicLayoutTest();
  mediaAlbumTest();
  chatPhotoSendingTest();
  chatFileSendingTest();
  linkPreviewTest();
  chatSearchJumpTest();
  commentsCoordinatorTest();
  mediaRedownloadTest();
  chatMuteStateTest();
  privateChatHeaderProfileTest();
  viewerTransformTest();
  viewerPlaybackTest();
  chatAppLinkDispatchTest();
  stickerSendVetoTest();
}

