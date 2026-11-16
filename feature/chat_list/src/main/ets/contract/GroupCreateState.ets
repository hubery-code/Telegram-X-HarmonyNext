/**
 * feature/chat_list — 建群/建频道流程状态（GROUP-CREATE-101）。
 *
 * 一段式流程（选成员 → 命名 → 创建）里「命名 + 提交」这一段的状态：
 * - 成员选择在 feature/contact 的联系人页多选模式完成，装配层把选中
 *   userIds 经 GroupCreateStarted 带进来（feature 之间不互相依赖）；
 * - 本状态挂在 ChatListUiState.groupCreate（null = 流程未激活），命名页
 *   GroupNamingPage 渲染它、装配层决定何时挂载该页；
 * - title/description 是输入原文（不 trim），提交时由 reducer 统一校验，
 *   校验口径与 core/domain 的 validateGroupTitle 同一条（都调它）；
 * - errorMessageKey 存 **Lang key** 而不是成品文案（传 key 不传串约定），
 *   页面 this.t() 现取，切语言随重渲染生效。
 */

/** 建群目标：普通群组（createNewBasicGroupChat）或频道（is_channel=true）。 */
export type GroupCreateMode = 'group' | 'channel';

export interface GroupCreateStateOptions {
  readonly mode?: GroupCreateMode;
  readonly memberUserIds?: number[];
  readonly title?: string;
  readonly description?: string;
  readonly isSubmitting?: boolean;
  readonly errorMessageKey?: string | null;
}

export class GroupCreateState {
  readonly mode: GroupCreateMode;
  /** 成员选择阶段确认的 userIds（保持点选顺序；频道创建忽略此值）。 */
  readonly memberUserIds: number[];
  /** 标题输入原文（1-128 字校验在提交时做，不 trim 保存）。 */
  readonly title: string;
  /** 频道可选简介；群创建不渲染该输入框。 */
  readonly description: string;
  /** 请求在途（防重复提交 + 按钮禁用）。 */
  readonly isSubmitting: boolean;
  /** 内联错误条文案的 Lang key；null = 无错误。 */
  readonly errorMessageKey: string | null;

  constructor(
    mode: GroupCreateMode = 'group',
    memberUserIds: number[] = [],
    title: string = '',
    description: string = '',
    isSubmitting: boolean = false,
    errorMessageKey: string | null = null
  ) {
    this.mode = mode;
    this.memberUserIds = memberUserIds;
    this.title = title;
    this.description = description;
    this.isSubmitting = isSubmitting;
    this.errorMessageKey = errorMessageKey;
  }

  copyWith(options: GroupCreateStateOptions): GroupCreateState {
    return new GroupCreateState(
      options.mode !== undefined ? options.mode : this.mode,
      options.memberUserIds !== undefined ? options.memberUserIds : this.memberUserIds,
      options.title !== undefined ? options.title : this.title,
      options.description !== undefined ? options.description : this.description,
      options.isSubmitting !== undefined ? options.isSubmitting : this.isSubmitting,
      options.errorMessageKey !== undefined ? options.errorMessageKey : this.errorMessageKey
    );
  }
}
