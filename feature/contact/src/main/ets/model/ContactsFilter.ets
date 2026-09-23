/**
 * feature/contact — 联系人搜索匹配纯函数（CONTACT-102）。
 *
 * 逐条对齐 Android `ContactsController.sortUsers()`（:901）的过滤条件：
 * `!Strings.anyWordStartsWith(check, q) && !Td.findUsernameByPrefix(usernames, q)` 则跳过，
 * 即**词首前缀匹配**，不是子串匹配。旧实现用 `indexOf` 子串，会把 `hu` 命中
 * `Zhu Feng` 这种中间片段，和 Android 的行为不一致（用户在 Android 上习惯的是词首）。
 *
 * `Strings.anyWordStartsWith`（`tool/Strings.java:574-601`）：
 * - 先整体 `regionMatches(true, 0, prefix, 0, len)` —— 忽略大小写的前缀比较；
 * - 再按分隔符 `WORDS_LOOKUP = {' ', '\n'}` 逐词取词首，逐个比较；
 * - 命中任一即 true。整个 query 作为**一个**前缀参与比较（不是按空格拆成多条件），
 *   所以 `be h` 能命中 `be hu`（整体前缀），`h hu` 不能（既非整体前缀也非任何词首）。
 *
 * 本文件不得 import `@kit` / `ohos`：reducer 与单测都要直接跑。
 */

import { ContactsItem } from '../contract/ContactsUiState';

/** Android `Strings.WORDS_LOOKUP`：词分隔符只有空格与换行。 */
const WORD_SPLITTERS: string = ' \n';

/** 忽略大小写的「从 `from` 起是否以 `prefix` 开头」（对齐 `regionMatches(true, ...)`）。 */
function startsWithIgnoreCaseAt(source: string, from: number, prefix: string): boolean {
  if (from < 0 || from + prefix.length > source.length) {
    return false;
  }
  for (let i: number = 0; i < prefix.length; i++) {
    const a: string = source.charAt(from + i).toLowerCase();
    const b: string = prefix.charAt(i).toLowerCase();
    if (a !== b) {
      return false;
    }
  }
  return true;
}

/** 从 `from` 起的下一个分隔符下标，没有则 -1（对齐 `Strings.indexOfAnyChar`）。 */
function indexOfSplitter(source: string, from: number): number {
  for (let i: number = from; i < source.length; i++) {
    if (WORD_SPLITTERS.indexOf(source.charAt(i)) >= 0) {
      return i;
    }
  }
  return -1;
}

/**
 * `source` 的**整体或任一词的词首**是否以 `prefix` 开头（忽略大小写）。
 * 空 prefix 恒为 true（Android 同行为：`regionMatches` 长度为 0 直接命中），
 * 调用方需自己保证空查询不进过滤分支。
 */
export function anyWordStartsWith(source: string, prefix: string): boolean {
  if (startsWithIgnoreCaseAt(source, 0, prefix)) {
    return true;
  }
  let startIndex: number = 0;
  let i: number = indexOfSplitter(source, startIndex);
  while (i !== -1) {
    startIndex = i + 1;
    if (startsWithIgnoreCaseAt(source, startIndex, prefix)) {
      return true;
    }
    i = indexOfSplitter(source, startIndex);
  }
  return false;
}

/**
 * 单个联系人是否命中查询：展示名词首匹配，或用户名前缀匹配。
 *
 * `query` 归一为 `trim`（Android 传进来的 `q` 同样是去掉首尾空白的输入框文本），
 * 大小写不敏感由 `anyWordStartsWith` 内部处理。
 *
 * 刻意**不**匹配电话号码：Android 的联系人页过滤只有这两项
 * （`ContactsController.java:901`），号码匹配只存在于全局搜索 `SearchManager`。
 */
export function contactMatchesQuery(item: ContactsItem, query: string): boolean {
  const q: string = query.trim();
  if (q.length === 0) {
    return true;
  }
  if (anyWordStartsWith(item.displayName, q)) {
    return true;
  }
  return item.username.length > 0 && startsWithIgnoreCaseAt(item.username, 0, q);
}
