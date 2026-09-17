/**
 * feature/chat — 消息反应视图模型（CHANNEL-101）。
 *
 * 封装单条消息上的单个反应 chip 数据（如 🔥 9，❤ 1）。
 */
export class ReactionChip {
  readonly emoji: string;
  readonly count: number;
  readonly isChosen: boolean;

  constructor(emoji: string, count: number, isChosen: boolean = false) {
    this.emoji = emoji;
    this.count = count;
    this.isChosen = isChosen;
  }
}
