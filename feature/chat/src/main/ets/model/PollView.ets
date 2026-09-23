/**
 * feature/chat — 投票消息视图模型（POLL-101 / FEAT-P2-003）。
 *
 * PollView 由 TDLib `poll`（messageContent.messagePoll.poll）映射产出，
 * 承载一个投票气泡渲染所需的全部扁平数据；票数/百分比/is_chosen 直接取自
 * PollOption（服务端在 setPollAnswer 后经 updateMessageContent 回灌）。
 *
 * PollComposerState 是投票创建面板的编辑态（受控，全部变更走 reducer），
 * options 恒 ≥2 项（POLL_MIN_OPTIONS），上限 POLL_MAX_OPTIONS 项。
 */

import { Poll, PollOption } from '@tgx/core-td-api-generated';

/** 创建投票允许的最少/最多选项数（对齐 Telegram：2..10）。 */
export const POLL_MIN_OPTIONS: number = 2;
export const POLL_MAX_OPTIONS: number = 10;
/** 选项与问题的输入长度上限（TDLib：question 1-255、option 1-100）。 */
export const POLL_QUESTION_MAX_LENGTH: number = 255;
export const POLL_OPTION_MAX_LENGTH: number = 100;

export class PollOptionView {
  /** 0-based 选项位置，setPollAnswer 的 option_ids 即用它。 */
  readonly index: number;
  readonly text: string;
  readonly voterCount: number;
  readonly votePercentage: number;
  readonly isChosen: boolean;

  constructor(index: number, text: string, voterCount: number, votePercentage: number, isChosen: boolean) {
    this.index = index;
    this.text = text;
    this.voterCount = voterCount;
    this.votePercentage = votePercentage;
    this.isChosen = isChosen;
  }
}

export class PollView {
  readonly question: string;
  readonly options: PollOptionView[];
  readonly totalVoterCount: number;
  readonly isAnonymous: boolean;
  readonly allowsMultipleAnswers: boolean;
  readonly isClosed: boolean;
  /** 结果可见性：已投票 / 已结束 / 自己建的投票才展示计数与进度条。 */
  readonly showResults: boolean;
  /** 本端是否已投出过一票（任一选项 is_chosen）。 */
  readonly hasVoted: boolean;

  constructor(
    question: string,
    options: PollOptionView[],
    totalVoterCount: number,
    isAnonymous: boolean,
    allowsMultipleAnswers: boolean,
    isClosed: boolean,
    showResults: boolean,
    hasVoted: boolean
  ) {
    this.question = question;
    this.options = options;
    this.totalVoterCount = totalVoterCount;
    this.isAnonymous = isAnonymous;
    this.allowsMultipleAnswers = allowsMultipleAnswers;
    this.isClosed = isClosed;
    this.showResults = showResults;
    this.hasVoted = hasVoted;
  }
}

/** TDLib poll → PollView；poll 为 null 时返回 null（消息不是投票或解析失败）。 */
export function pollViewOf(poll: Poll | null): PollView | null {
  if (poll === null || poll === undefined) {
    return null;
  }
  const options: PollOptionView[] = [];
  let hasVoted: boolean = false;
  for (let i: number = 0; i < poll.options.length; i++) {
    const option: PollOption = poll.options[i];
    const optionText: string = option.text !== null ? option.text.text : '';
    if (option.is_chosen) {
      hasVoted = true;
    }
    options.push(new PollOptionView(i, optionText, option.voter_count, option.vote_percentage, option.is_chosen));
  }
  const showResults: boolean = poll.can_see_results || hasVoted || poll.is_closed;
  return new PollView(
    poll.question !== null ? poll.question.text : '',
    options,
    poll.total_voter_count,
    poll.is_anonymous,
    poll.allows_multiple_answers,
    poll.is_closed,
    showResults,
    hasVoted
  );
}

/** 投票创建面板编辑态（不可变，copyWith 派生）。 */
export class PollComposerState {
  readonly question: string;
  readonly options: string[];
  readonly isAnonymous: boolean;
  readonly allowsMultiple: boolean;

  constructor(
    question: string = '',
    options: string[] = ['', ''],
    isAnonymous: boolean = true,
    allowsMultiple: boolean = false
  ) {
    this.question = question;
    this.options = options;
    this.isAnonymous = isAnonymous;
    this.allowsMultiple = allowsMultiple;
  }

  static draft(): PollComposerState {
    return new PollComposerState();
  }

  copyWith(options: PollComposerOptions): PollComposerState {
    return new PollComposerState(
      options.question !== undefined ? options.question : this.question,
      options.options !== undefined ? options.options : this.options,
      options.isAnonymous !== undefined ? options.isAnonymous : this.isAnonymous,
      options.allowsMultiple !== undefined ? options.allowsMultiple : this.allowsMultiple
    );
  }

  /** 可提交判定：问题非空且非空选项 ≥ POLL_MIN_OPTIONS。 */
  isValid(): boolean {
    return this.nonEmptyOptions().length >= POLL_MIN_OPTIONS;
  }

  /** 去空白后的非空选项列表（提交发送用）。 */
  nonEmptyOptions(): string[] {
    const out: string[] = [];
    for (let i: number = 0; i < this.options.length; i++) {
      const trimmed: string = this.options[i].trim();
      if (trimmed.length > 0) {
        out.push(trimmed);
      }
    }
    return out;
  }
}

export interface PollComposerOptions {
  readonly question?: string;
  readonly options?: string[];
  readonly isAnonymous?: boolean;
  readonly allowsMultiple?: boolean;
}
