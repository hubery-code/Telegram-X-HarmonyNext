/**
 * 测试助手：从 JSON 文本构造 wire 记录。
 * ArkTS 不允许带属性的对象字面量直接作为 TdWireObject 参数传递
 * （空 interface extends Record 不是合法参数字面量目标），
 * 统一经 JSON.parse + 断言转换构造。
 */

import { TdWireObject } from '../main/ets/TdWire';

export function tdWire(json: string): TdWireObject {
  const parsed: Object = JSON.parse(json);
  return parsed as TdWireObject;
}
