import { TdJsonRaw } from '@tgx/core-td-api-generated/src/main/ets/runtime/TdJson';

/**
 * Test helper: builds a TDLib-shaped JSON object without inline object
 * literals (arkts-no-untyped-obj-literals forbids them in value positions).
 */
export function jsonObj(): Record<string, TdJsonRaw> {
  return {};
}

export function jsonArr(): TdJsonRaw[] {
  return [];
}
