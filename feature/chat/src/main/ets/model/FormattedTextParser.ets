/**
 * feature/chat — TDLib FormattedText → MessageTextSpan[] 纯函数解析（MSG-101）。
 *
 * TDLib entity 的 offset/length 是 UTF-16 code unit，ArkTS string 索引同为
 * UTF-16，直接 substring 无需转码。
 *
 * 算法：边界集合 {0, text.length} ∪ 每个合法实体的 [offset, offset+length]
 * （clamp 到文本范围；负 offset / 非正 length / clamp 后为空区间的实体跳过），
 * 排序去重后逐段求覆盖该段的实体并集 → span flags，相邻 flags + linkUrl
 * 完全相同的段合并为一个 span。
 *
 * 空输入约定：formatted 为 null 或 text 为空串时返回 []（空文本没有可渲染
 * 内容，气泡走原有的 Text(item.text) 纯文本分支即可，不产出单 span）。
 */

import {
  FormattedText,
  TextEntity,
  TextEntityTypeTextUrl,
  TdTextEntityType
} from '@tgx/core-td-api-generated';
import { MessageTextSpan } from './MessageTextSpan';

/** 单个实体的合法化区间（闭开区间 [start, end)，已 clamp 到文本范围）。 */
class EntityRange {
  readonly start: number;
  readonly end: number;
  readonly entity: TextEntity;

  constructor(start: number, end: number, entity: TextEntity) {
    this.start = start;
    this.end = end;
    this.entity = entity;
  }
}

/** 段样式累加器：求覆盖同一段的所有实体的样式并集（解析中间态，可变）。 */
class SpanStyleAccumulator {
  bold: boolean = false;
  italic: boolean = false;
  underline: boolean = false;
  strikethrough: boolean = false;
  isCode: boolean = false;
  isPre: boolean = false;
  isSpoiler: boolean = false;
  isAccent: boolean = false;
  linkUrl: string | null = null;

  apply(entity: TextEntity, segmentText: string): void {
    const entityType: TdTextEntityType | null = entity.type_;
    if (entityType === null) {
      return;
    }
    switch (entityType.type) {
      case 'textEntityTypeBold':
        this.bold = true;
        break;
      case 'textEntityTypeItalic':
        this.italic = true;
        break;
      case 'textEntityTypeUnderline':
        this.underline = true;
        break;
      case 'textEntityTypeStrikethrough':
        this.strikethrough = true;
        break;
      case 'textEntityTypeCode':
        this.isCode = true;
        break;
      case 'textEntityTypePre':
      case 'textEntityTypePreCode':
        this.isPre = true;
        break;
      case 'textEntityTypeSpoiler':
        this.isSpoiler = true;
        break;
      case 'textEntityTypeTextUrl': {
        // 多个链接实体覆盖同段时取先到的（TDLib 保证链接互不交叠，此处仅防御）。
        const url: string = (entityType as TextEntityTypeTextUrl).url;
        if (this.linkUrl === null && url.length > 0) {
          this.linkUrl = url;
        }
        break;
      }
      case 'textEntityTypeUrl':
        if (this.linkUrl === null && segmentText.length > 0) {
          this.linkUrl = segmentText;
        }
        break;
      case 'textEntityTypeMention':
      case 'textEntityTypeMentionName':
      case 'textEntityTypeHashtag':
      case 'textEntityTypeCashtag':
      case 'textEntityTypeBotCommand':
      case 'textEntityTypeEmailAddress':
      case 'textEntityTypePhoneNumber':
      case 'textEntityTypeBankCardNumber':
      case 'textEntityTypeMediaTimestamp':
        this.isAccent = true;
        break;
      default:
        // textEntityTypeCustomEmoji（占位：自定义表情暂按普通文本渲染）、
        // BlockQuote/ExpandableBlockQuote/DateTime 与未知类型（TdUnknownObject）
        // 一律不加样式、不抛错。
        break;
    }
  }

  equals(other: SpanStyleAccumulator): boolean {
    return this.bold === other.bold &&
      this.italic === other.italic &&
      this.underline === other.underline &&
      this.strikethrough === other.strikethrough &&
      this.isCode === other.isCode &&
      this.isPre === other.isPre &&
      this.isSpoiler === other.isSpoiler &&
      this.isAccent === other.isAccent &&
      this.linkUrl === other.linkUrl;
  }

  toSpan(text: string): MessageTextSpan {
    return new MessageTextSpan(
      text,
      this.bold,
      this.italic,
      this.underline,
      this.strikethrough,
      this.isCode,
      this.isPre,
      this.isSpoiler,
      this.isAccent,
      this.linkUrl
    );
  }
}

export function parseFormattedText(formatted: FormattedText | null): MessageTextSpan[] {
  if (formatted === null) {
    return [];
  }
  const text: string = formatted.text;
  if (text.length === 0) {
    return [];
  }
  // entities 声明为非空数组，对运行期的 null/undefined 仍做防御。
  const entities: TextEntity[] | null = formatted.entities;

  // 1) 收集合法实体区间与边界点；负 offset / 非正 length / 越界后为空 → 跳过。
  const boundaries: number[] = [0, text.length];
  const ranges: EntityRange[] = [];
  if (entities !== null && entities !== undefined) {
    for (let i = 0; i < entities.length; i++) {
      const entity: TextEntity = entities[i];
      if (entity.offset < 0 || entity.length <= 0) {
        continue;
      }
      const start: number = Math.min(entity.offset, text.length);
      const end: number = Math.min(entity.offset + entity.length, text.length);
      if (start >= end) {
        continue;
      }
      ranges.push(new EntityRange(start, end, entity));
      boundaries.push(start);
      boundaries.push(end);
    }
  }
  boundaries.sort((a: number, b: number) => a - b);

  // 2) 逐段求样式并集；相邻样式相同的段合并。
  const spans: MessageTextSpan[] = [];
  let lastStyle: SpanStyleAccumulator | null = null;
  let i: number = 0;
  while (i + 1 < boundaries.length) {
    const segStart: number = boundaries[i];
    const segEnd: number = boundaries[i + 1];
    i++;
    if (segStart >= segEnd) {
      continue; // 排序去重：跳过重复边界点
    }
    const segText: string = text.substring(segStart, segEnd);
    const style = new SpanStyleAccumulator();
    for (let r = 0; r < ranges.length; r++) {
      const range: EntityRange = ranges[r];
      if (range.start <= segStart && range.end >= segEnd) {
        style.apply(range.entity, segText);
      }
    }
    if (lastStyle !== null && lastStyle.equals(style) && spans.length > 0) {
      const last: MessageTextSpan = spans[spans.length - 1];
      spans[spans.length - 1] = style.toSpan(last.text + segText);
    } else {
      spans.push(style.toSpan(segText));
      lastStyle = style;
    }
  }
  return spans;
}
