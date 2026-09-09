/**
 * 测试助手：从 JSON 文本构造 wire 记录（ArkTS 参数字面量限制同 CORE-002 的 TestWire）。
 */

import { TdWireObject } from '@tgx/td-gateway';

export function tdWire(json: string): TdWireObject {
  const parsed: Object = JSON.parse(json);
  return parsed as TdWireObject;
}
