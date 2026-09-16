/**
 * feature/chat — 链接预览单元测试（MSG-107 / FEAT-COMP-002）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { LinkPreviewInfo } from '../main/ets/model/LinkPreviewInfo';
import { MessageItem } from '../main/ets/model/MessageItem';

export default function linkPreviewTest(): void {
  describe('LinkPreviewTest', (): void => {

    it('linkPreviewInfo_defaultValues_hasNoContent', 0, (): void => {
      const info: LinkPreviewInfo = new LinkPreviewInfo();
      expect(info.url).assertEqual('');
      expect(info.displayUrl).assertEqual('');
      expect(info.siteName).assertEqual('');
      expect(info.title).assertEqual('');
      expect(info.description).assertEqual('');
      expect(info.thumbnailPath).assertNull();
      expect(info.fileId).assertEqual(0);
      expect(info.isPhoto).assertFalse();
      expect(info.isLargeMedia).assertFalse();
      expect(info.showAboveText).assertFalse();
      expect(info.hasContent()).assertFalse();
    });

    it('linkPreviewInfo_withValidArticleContent_hasContentIsTrue', 0, (): void => {
      const info: LinkPreviewInfo = new LinkPreviewInfo(
        'https://github.com/telegram',
        'github.com',
        'GitHub',
        'Telegram · GitHub',
        'Telegram source code repositories and official organizations.',
        'Telegram',
        false,
        '/data/storage/el2/base/cache/preview_thumb.jpg',
        999,
        false,
        false
      );

      expect(info.url).assertEqual('https://github.com/telegram');
      expect(info.displayUrl).assertEqual('github.com');
      expect(info.siteName).assertEqual('GitHub');
      expect(info.title).assertEqual('Telegram · GitHub');
      expect(info.description).assertEqual('Telegram source code repositories and official organizations.');
      expect(info.author).assertEqual('Telegram');
      expect(info.thumbnailPath).assertEqual('/data/storage/el2/base/cache/preview_thumb.jpg');
      expect(info.fileId).assertEqual(999);
      expect(info.isPhoto).assertFalse();
      expect(info.isLargeMedia).assertFalse();
      expect(info.showAboveText).assertFalse();
      expect(info.hasContent()).assertTrue();
    });

    it('linkPreviewInfo_withLargeMedia_preservesFlags', 0, (): void => {
      const info: LinkPreviewInfo = new LinkPreviewInfo(
        'https://t.me/photo_sample',
        't.me',
        'Telegram',
        'Sample Photo',
        'Photo caption',
        '',
        true,
        '/data/storage/photo.jpg',
        1001,
        true,
        true
      );

      expect(info.isPhoto).assertTrue();
      expect(info.isLargeMedia).assertTrue();
      expect(info.showAboveText).assertTrue();
      expect(info.hasContent()).assertTrue();
    });

    it('messageItem_withLinkPreview_storesAndExposesField', 0, (): void => {
      const preview: LinkPreviewInfo = new LinkPreviewInfo(
        'https://harmonyos.com',
        'harmonyos.com',
        'HarmonyOS',
        'OpenHarmony Official',
        'All scenario operating system'
      );

      const item: MessageItem = new MessageItem(
        101,
        'Visit https://harmonyos.com',
        1700000000000,
        false,
        'Alice',
        'none',
        true,
        false,
        null,
        '',
        [],
        -1,
        false,
        null,
        '',
        -1,
        null,
        false,
        false,
        '',
        false,
        null,
        [],
        [],
        preview
      );

      expect(item.messageId).assertEqual(101);
      expect(item.linkPreview !== null).assertTrue();
      expect(item.linkPreview!.siteName).assertEqual('HarmonyOS');
      expect(item.linkPreview!.url).assertEqual('https://harmonyos.com');
      expect(item.linkPreview!.title).assertEqual('OpenHarmony Official');
    });

    it('messageItem_withoutLinkPreview_defaultsToNull', 0, (): void => {
      const item: MessageItem = new MessageItem(
        102,
        'Plain message',
        1700000000000,
        true,
        'Me'
      );

      expect(item.linkPreview).assertNull();
    });

    it('linkPreviewInfo_aspectRatio_calculatesProperly', 0, (): void => {
      const defaultInfo: LinkPreviewInfo = new LinkPreviewInfo();
      expect(defaultInfo.aspectRatio).assertEqual(1.777);

      const landscapeInfo: LinkPreviewInfo = new LinkPreviewInfo(
        'https://github.com',
        'github.com',
        'GitHub',
        'Title',
        'Desc',
        '',
        false,
        null,
        0,
        false,
        true,
        true,
        1200,
        600
      );
      expect(landscapeInfo.showMediaAboveDescription).assertTrue();
      expect(landscapeInfo.mediaWidth).assertEqual(1200);
      expect(landscapeInfo.mediaHeight).assertEqual(600);
      expect(landscapeInfo.aspectRatio).assertEqual(2.0);

      // 极端高瘦比例 clamp 到 0.5
      const tallInfo: LinkPreviewInfo = new LinkPreviewInfo(
        'https://example.com',
        'example.com',
        '',
        '',
        '',
        '',
        false,
        null,
        0,
        false,
        true,
        false,
        100,
        500
      );
      expect(tallInfo.aspectRatio).assertEqual(0.5);

      // 极端扁平比例 clamp 到 2.5
      const wideInfo: LinkPreviewInfo = new LinkPreviewInfo(
        'https://example.com',
        'example.com',
        '',
        '',
        '',
        '',
        false,
        null,
        0,
        false,
        true,
        false,
        1000,
        100
      );
      expect(wideInfo.aspectRatio).assertEqual(2.5);
    });
  });
}
