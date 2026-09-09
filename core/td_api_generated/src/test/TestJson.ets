import { TdJsonRaw } from '../main/ets/Index';

/**
 * Test helper: builds a TDLib-shaped JSON object without inline object
 * literals (arkts-no-untyped-obj-literals forbids them in value positions).
 */
export function jsonObj(): Record<string, TdJsonRaw> {
  return {};
}

export function toJson(value: Record<string, TdJsonRaw>): TdJsonRaw {
  return value;
}
