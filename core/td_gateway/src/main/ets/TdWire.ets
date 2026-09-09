/**
 * core/td_gateway — TDLib JSON wire 类型与基础助手（CORE-002）。
 *
 * 与 core/td_api_generated 的 TdJsonRaw/TdJsonObject 结构完全一致
 * （同一套 TDLib JSON 线格式的 ArkTS 建模），因此两处类型可安全互转
 * （见 README「与 GEN 类型的对接」）。本模块不依赖 GEN 产物，
 * 保持 gateway 层与生成 DTO 解耦：gateway 只搬运 wire 记录，
 * decode 成具体 DTO 是消费方（AccountScope / use case）的职责。
 *
 * 精度规则（计划 §5.2）：64 位值（业务 ID、单调 sequence）一律 string，
 * 不经过 JS number；clientId 是 int32，用经范围校验的 number。
 */

/** TDLib JSON 值。int64 已建模为 string。 */
export type TdWireValue = boolean | number | string | TdWireValue[] | TdWireObject | null;

/**
 * TDLib JSON 对象（wire 记录）。
 * 用「空 interface extends Record」而非类型别名：ArkTS 类型别名经 Record
 * 自引用会被判循环引用，interface 可破环（与 core/td_api_generated 的
 * TdJsonObject 同一写法，两者同形可互转）。
 * 注意 ArkTS 限制：带属性的对象字面量不能直接以本类型做参数传递，
 * 测试/调用方经 wire()/decode 得到的值传递没有问题。
 */
export interface TdWireObject extends Record<string, TdWireValue> {
}

/** 取对象的 string 字段，缺省/类型不符返回 defaultValue。 */
export function wireString(value: TdWireValue | undefined, defaultValue: string = ''): string {
  if (typeof value === 'string') {
    return value;
  }
  return defaultValue;
}

/** 取对象的 number 字段（int32 场景），缺省/类型不符返回 defaultValue。 */
export function wireNumber(value: TdWireValue | undefined, defaultValue: number = 0): number {
  if (typeof value === 'number') {
    return value;
  }
  return defaultValue;
}

/** 判断 wire 值是否为对象记录（非数组、非 null）。 */
export function isWireObject(value: TdWireValue | undefined): boolean {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * 十进制非负整数字符串比较（兼容任意长度，不转 number/bigint）。
 * 返回负数 / 0 / 正数，语义同 Comparator。
 * 输入约定为 native 层产出的十进制字符串（可能带前导零时先规整）。
 */
export function compareDecimalString(a: string, b: string): number {
  const na: string = stripLeadingZeros(a);
  const nb: string = stripLeadingZeros(b);
  if (na.length !== nb.length) {
    return na.length < nb.length ? -1 : 1;
  }
  if (na === nb) {
    return 0;
  }
  return na < nb ? -1 : 1;
}

function stripLeadingZeros(s: string): string {
  let i: number = 0;
  while (i < s.length - 1 && s.charAt(i) === '0') {
    i += 1;
  }
  return s.substring(i);
}

/** 校验 clientId（TDLib 全局 client id 为 int32，必须是非负安全整数）。 */
export function isValidClientId(clientId: number): boolean {
  return Number.isInteger(clientId) && clientId >= 0;
}

/** 浅拷贝 wire 对象（ArkTS 不使用对象展开，显式拷贝）。 */
export function copyWireObject(source: TdWireObject): TdWireObject {
  const out: TdWireObject = {};
  for (const key of Object.keys(source)) {
    out[key] = source[key];
  }
  return out;
}
