/**
 * feature/contact — 电话号码展示格式化（CONTACT-102）。
 *
 * Android 联系人行的副标题走 `Strings.formatPhone(user.phoneNumber)`
 * （`data/TGUser.java:314-315`：`FLAG_CONTACT` 或 `FLAG_SHOW_PHONE_NUMBER` 时副标题就是号码）：
 * 1. `Strings.getNumber()`（`tool/Strings.java:704-720`）只保留 ASCII 数字，剥掉空格、
 *    连字符、括号等一切非数字；
 * 2. 交给 `TGPhoneFormat.build()` 按国家规则分组（`+44 7741 417158` 这类）；
 * 3. 分组失败时兜底 `'+' + digits`（`forcePlus`）再走系统 locale 格式化。
 *
 * **本端只移植 1 + 3 的 `+digits` 兜底**：`TGPhoneFormat` 是一张随版本更新的国家号段
 * 分组表（Android 侧近千行），移植它不属于联系人页的范围，且分组错了比不分更难看。
 * TDLib 的 `user.phone_number` 本身也不保证带 `+`（实测本账号回包是
 * `447741417158`），所以补 `+` 是有意义的一步，不是纯装饰。
 *
 * 本文件不得 import `@kit` / `ohos`：coordinator、页面与单测都要直接跑。
 */

/**
 * 展示用号码：只留 ASCII 数字并强制前缀 `+`；无可用数字则返回空串（调用方按
 * 「没有号码」处理，回退到 @username / 在线状态）。
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
  return digits.length > 0 ? `+${digits}` : '';
}
