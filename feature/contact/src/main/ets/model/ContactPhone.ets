/**
 * feature/contact — 电话号码展示格式化（CONTACT-102 / CONTACT-FORMAT-103）。
 *
 * Android 联系人行的副标题走 `Strings.formatPhone(user.phoneNumber)`
 * （`data/TGUser.java:314-315`：`FLAG_CONTACT` 或 `FLAG_SHOW_PHONE_NUMBER` 时副标题就是号码）：
 * 1. `Strings.getNumber()`（`tool/Strings.java:704-720`）只保留 ASCII 数字，剥掉空格、
 *    连字符、括号等一切非数字；
 * 2. 交给 `TGPhoneFormat.build()` 按国家规则分组（`+44 7741 417158`、`+86 138 0000 0000` 这类）；
 * 3. 分组失败时兜底 `'+' + digits`（`forcePlus`）。
 *
 * 本端实现对齐主要国家/地区的 E.164 规范分组（+86, +1, +44, +7, +852, +886, +81, +82, +49, +33, +65 等），
 * 未命中模板则平滑回退到 `+digits`。
 *
 * 本文件不得 import `@kit` / `ohos`：coordinator、页面与单测都要直接跑。
 */

/**
 * 按国家代码规则格式化号码段；未匹配到特定国家模板时返回 null。
 */
function formatByCountryRule(digits: string): string | null {
  const len: number = digits.length;
  // +86 (中国大陆: 86 + 11 位手机号 = 13 位)
  if (len === 13 && digits.startsWith('86')) {
    return `+86 ${digits.substring(2, 5)} ${digits.substring(5, 9)} ${digits.substring(9, 13)}`;
  }
  // +1 (美国/加拿大: 1 + 10 位 = 11 位)
  if (len === 11 && digits.startsWith('1')) {
    return `+1 (${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7, 11)}`;
  }
  // +7 (俄罗斯/哈萨克斯坦: 7 + 10 位 = 11 位)
  if (len === 11 && digits.startsWith('7')) {
    return `+7 (${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7, 9)}-${digits.substring(9, 11)}`;
  }
  // +44 (英国: 44 + 10 位 = 12 位)
  if (len === 12 && digits.startsWith('44')) {
    return `+44 ${digits.substring(2, 6)} ${digits.substring(6, 12)}`;
  }
  // +852 (中国香港: 852 + 8 位 = 11 位)
  if (len === 11 && digits.startsWith('852')) {
    return `+852 ${digits.substring(3, 7)} ${digits.substring(7, 11)}`;
  }
  // +886 (中国台湾: 886 + 9 位 = 12 位)
  if (len === 12 && digits.startsWith('886')) {
    return `+886 ${digits.substring(3, 6)} ${digits.substring(6, 9)} ${digits.substring(9, 12)}`;
  }
  // +81 (日本: 81 + 10 位 = 12 位)
  if (len === 12 && digits.startsWith('81')) {
    return `+81 ${digits.substring(2, 4)} ${digits.substring(4, 8)} ${digits.substring(8, 12)}`;
  }
  // +82 (韩国: 82 + 10 位 = 12 位)
  if (len === 12 && digits.startsWith('82')) {
    return `+82 ${digits.substring(2, 4)} ${digits.substring(4, 8)} ${digits.substring(8, 12)}`;
  }
  // +49 (德国: 49 + 10/11 位 = 12/13 位)
  if (len === 12 && digits.startsWith('49')) {
    return `+49 ${digits.substring(2, 5)} ${digits.substring(5, 8)} ${digits.substring(8, 12)}`;
  }
  if (len === 13 && digits.startsWith('49')) {
    return `+49 ${digits.substring(2, 5)} ${digits.substring(5, 9)} ${digits.substring(9, 13)}`;
  }
  // +33 (法国: 33 + 9 位 = 11 位)
  if (len === 11 && digits.startsWith('33')) {
    return `+33 ${digits.substring(2, 3)} ${digits.substring(3, 5)} ${digits.substring(5, 7)} ${digits.substring(7, 9)} ${digits.substring(9, 11)}`;
  }
  // +65 (新加坡: 65 + 8 位 = 10 位)
  if (len === 10 && digits.startsWith('65')) {
    return `+65 ${digits.substring(2, 6)} ${digits.substring(6, 10)}`;
  }
  return null;
}

/**
 * 展示用号码：只留 ASCII 数字并按国家代码规则分段；未命中规则则前缀 `+` 兜底；
 * 无可用数字则返回空串（调用方按「没有号码」处理，回退到 @username / 在线状态）。
 */
export function formatContactPhone(raw: string | null): string {
  if (raw === null || raw === undefined || raw.length === 0) {
    return '';
  }
  let digits: string = '';
  for (let i: number = 0; i < raw.length; i++) {
    const c: string = raw.charAt(i);
    if (c >= '0' && c <= '9') {
      digits += c;
    }
  }
  if (digits.length === 0) {
    return '';
  }
  const formatted: string | null = formatByCountryRule(digits);
  return formatted !== null ? formatted : `+${digits}`;
}

