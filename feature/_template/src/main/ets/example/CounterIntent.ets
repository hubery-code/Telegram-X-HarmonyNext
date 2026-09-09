/**
 * feature/_template — 示例 feature：CounterIntent（UI-003）。
 *
 * Intent 是用户/系统意图；每个变体带 `kind` 判别字面量，
 * reducer 内用 switch (intent.kind) 做穷尽分支（ArkTS 判别联合收窄）。
 */

import { Intent } from '../contract/UiState';

export class IncrementPressed implements Intent {
  readonly kind: 'incrementPressed' = 'incrementPressed';
}

export class DecrementPressed implements Intent {
  readonly kind: 'decrementPressed' = 'decrementPressed';
}

export class StepChanged implements Intent {
  readonly kind: 'stepChanged' = 'stepChanged';
  readonly value: number;

  constructor(value: number) {
    this.value = value;
  }
}

export class SavePressed implements Intent {
  readonly kind: 'savePressed' = 'savePressed';
}

export class ResetPressed implements Intent {
  readonly kind: 'resetPressed' = 'resetPressed';
}

export type CounterIntent =
  IncrementPressed
  | DecrementPressed
  | StepChanged
  | SavePressed
  | ResetPressed;
