import { describe, it, expect } from '@ohos/hypium';
import {
  FormattedText,
  TextEntity,
  TdTextEntityType,
  TdUnknownObject,
  TextEntityTypeBold,
  TextEntityTypeCustomEmoji,
  TextEntityTypeItalic,
  TextEntityTypeSpoiler,
  TextEntityTypeTextUrl,
  TextEntityTypeUrl
} from '@tgx/core-td-api-generated';
import { MessageTextSpan } from '../main/ets/model/MessageTextSpan';
import { parseFormattedText } from '../main/ets/model/FormattedTextParser';

function makeEntity(offset: number, length: number, type: TdTextEntityType): TextEntity {
  const entity = new TextEntity();
  entity.offset = offset;
  entity.length = length;
  entity.type_ = type;
  return entity;
}

function makeFormatted(text: string, entities: TextEntity[]): FormattedText {
  const formatted = new FormattedText();
  formatted.text = text;
  formatted.entities = entities;
  return formatted;
}

function expectPlain(span: MessageTextSpan): void {
  expect(span.bold).assertFalse();
  expect(span.italic).assertFalse();
  expect(span.underline).assertFalse();
  expect(span.strikethrough).assertFalse();
  expect(span.isCode).assertFalse();
  expect(span.isPre).assertFalse();
  expect(span.isSpoiler).assertFalse();
  expect(span.isAccent).assertFalse();
  expect(span.linkUrl).assertNull();
}

export default function formattedTextParserTest() {
  describe('FormattedTextParserTest', () => {
    it('nullFormattedText_returnsEmpty', 0, () => {
      const spans: MessageTextSpan[] = parseFormattedText(null);
      expect(spans.length).assertEqual(0);
    });

    it('emptyText_returnsEmpty', 0, () => {
      const spans: MessageTextSpan[] =
        parseFormattedText(makeFormatted('', [makeEntity(0, 1, new TextEntityTypeBold())]));
      expect(spans.length).assertEqual(0);
    });

    it('emptyEntities_singlePlainSpan', 0, () => {
      const spans: MessageTextSpan[] = parseFormattedText(makeFormatted('hello', []));
      expect(spans.length).assertEqual(1);
      expect(spans[0].text).assertEqual('hello');
      expectPlain(spans[0]);
    });

    it('singleBold_splitsAroundEntity', 0, () => {
      const spans: MessageTextSpan[] =
        parseFormattedText(makeFormatted('hello world', [makeEntity(6, 5, new TextEntityTypeBold())]));
      expect(spans.length).assertEqual(2);
      expect(spans[0].text).assertEqual('hello ');
      expectPlain(spans[0]);
      expect(spans[1].text).assertEqual('world');
      expect(spans[1].bold).assertTrue();
      expect(spans[1].italic).assertFalse();
    });

    it('overlappingBoldItalic_unionFlagsPerSegment', 0, () => {
      // bold [0,4) 与 italic [2,6) 交叠：三段样式分别为 bold / bold+italic / italic。
      const spans: MessageTextSpan[] = parseFormattedText(makeFormatted('aabbcc', [
        makeEntity(0, 4, new TextEntityTypeBold()),
        makeEntity(2, 4, new TextEntityTypeItalic())
      ]));
      expect(spans.length).assertEqual(3);
      expect(spans[0].text).assertEqual('aa');
      expect(spans[0].bold).assertTrue();
      expect(spans[0].italic).assertFalse();
      expect(spans[1].text).assertEqual('bb');
      expect(spans[1].bold).assertTrue();
      expect(spans[1].italic).assertTrue();
      expect(spans[2].text).assertEqual('cc');
      expect(spans[2].bold).assertFalse();
      expect(spans[2].italic).assertTrue();
    });

    it('adjacentSameStyle_mergesIntoSingleSpan', 0, () => {
      const spans: MessageTextSpan[] = parseFormattedText(makeFormatted('hello', [
        makeEntity(0, 2, new TextEntityTypeBold()),
        makeEntity(2, 3, new TextEntityTypeBold())
      ]));
      expect(spans.length).assertEqual(1);
      expect(spans[0].text).assertEqual('hello');
      expect(spans[0].bold).assertTrue();
    });

    it('outOfBoundsEntity_clampedToText', 0, () => {
      const spans: MessageTextSpan[] =
        parseFormattedText(makeFormatted('hello', [makeEntity(3, 100, new TextEntityTypeBold())]));
      expect(spans.length).assertEqual(2);
      expect(spans[0].text).assertEqual('hel');
      expectPlain(spans[0]);
      expect(spans[1].text).assertEqual('lo');
      expect(spans[1].bold).assertTrue();
    });

    it('illegalEntities_areSkipped', 0, () => {
      // 负 offset / 零长 / 负长度 / 完全越界（offset 起始于文本末尾之后）都跳过。
      const spans: MessageTextSpan[] = parseFormattedText(makeFormatted('hello', [
        makeEntity(-1, 3, new TextEntityTypeBold()),
        makeEntity(1, 0, new TextEntityTypeItalic()),
        makeEntity(1, -2, new TextEntityTypeItalic()),
        makeEntity(10, 5, new TextEntityTypeSpoiler())
      ]));
      expect(spans.length).assertEqual(1);
      expect(spans[0].text).assertEqual('hello');
      expectPlain(spans[0]);
    });

    it('textUrl_extractsLinkUrlFromEntity', 0, () => {
      const textUrl = new TextEntityTypeTextUrl();
      textUrl.url = 'https://example.com';
      const spans: MessageTextSpan[] =
        parseFormattedText(makeFormatted('click here', [makeEntity(0, 5, textUrl)]));
      expect(spans.length).assertEqual(2);
      expect(spans[0].text).assertEqual('click');
      expect(spans[0].linkUrl).assertEqual('https://example.com');
      expect(spans[1].text).assertEqual(' here');
      expectPlain(spans[1]);
    });

    it('urlEntity_linkUrlIsSegmentText', 0, () => {
      const spans: MessageTextSpan[] =
        parseFormattedText(makeFormatted('visit example.com now', [makeEntity(6, 11, new TextEntityTypeUrl())]));
      expect(spans.length).assertEqual(3);
      expect(spans[1].text).assertEqual('example.com');
      expect(spans[1].linkUrl).assertEqual('example.com');
      expectPlain(spans[0]);
      expectPlain(spans[2]);
    });

    it('spoiler_setsSpoilerFlag', 0, () => {
      const spans: MessageTextSpan[] =
        parseFormattedText(makeFormatted('secret', [makeEntity(0, 6, new TextEntityTypeSpoiler())]));
      expect(spans.length).assertEqual(1);
      expect(spans[0].isSpoiler).assertTrue();
      expect(spans[0].linkUrl).assertNull();
    });

    it('customEmoji_rendersAsPlainPlaceholder', 0, () => {
      const spans: MessageTextSpan[] =
        parseFormattedText(makeFormatted('hi 👋', [makeEntity(3, 2, new TextEntityTypeCustomEmoji())]));
      expect(spans.length).assertEqual(1);
      expect(spans[0].text).assertEqual('hi 👋');
      expectPlain(spans[0]);
    });

    it('unknownEntityType_rendersAsPlainText', 0, () => {
      const unknown = new TdUnknownObject('textEntityTypeFutureFeature', {});
      const spans: MessageTextSpan[] =
        parseFormattedText(makeFormatted('hello world', [makeEntity(0, 5, unknown)]));
      expect(spans.length).assertEqual(1);
      expect(spans[0].text).assertEqual('hello world');
      expectPlain(spans[0]);
    });
  });
}
