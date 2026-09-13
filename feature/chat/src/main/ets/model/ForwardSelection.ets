/**
 * feature/chat — 转发多选集合的纯函数（MSG-106 / FEAT-COMP-004）。
 *
 * 选择集合是 `readonly number[]`（消息 id），**恒保持升序且无重复**：
 * - TDLib forwardMessages 要求 message_ids 严格递增，升序维护让 reducer 产出的
 *   effect 参数直接可用（领域层仍会兜底排序去重，这里保证 UI 侧语义正确）；
 * - LazyForEach 的 key 需要稳定内容签名，有序数组使签名可确定比较。
 *
 * 所有函数不可变：返回新数组，不改动入参——reducer 纯度要求。
 */

/** 是否已选中该消息。 */
export function isMessageSelected(selected: readonly number[], messageId: number): boolean {
  for (let i = 0; i < selected.length; i++) {
    if (selected[i] === messageId) {
      return true;
    }
  }
  return false;
}

/** 升序插入；已存在则原样返回入参（幂等）。 */
function insertAscending(selected: readonly number[], messageId: number): number[] {
  const next: number[] = [];
  let inserted: boolean = false;
  for (let i = 0; i < selected.length; i++) {
    if (!inserted && messageId < selected[i]) {
      next.push(messageId);
      inserted = true;
    }
    next.push(selected[i]);
  }
  if (!inserted) {
    next.push(messageId);
  }
  return next;
}

/**
 * 切换选中态：未选中 → 插入（保持升序）；已选中 → 移除。
 * 返回新数组，入参不变。
 */
export function toggleMessageSelection(selected: readonly number[], messageId: number): number[] {
  if (isMessageSelected(selected, messageId)) {
    const next: number[] = [];
    for (let i = 0; i < selected.length; i++) {
      if (selected[i] !== messageId) {
        next.push(selected[i]);
      }
    }
    return next;
  }
  return insertAscending(selected, messageId);
}

/** 取消全部选择（恒返回空数组，便于 reducer 早期返回判定）。 */
export function clearSelection(): number[] {
  return [];
}

/**
 * 批量移除已不存在的消息 id（消息在选中期间被删除/撤回时收敛选择集合）。
 * 无变化时返回原引用，供 reducer 判定状态是否真的变了。
 */
export function retainExistingSelection(
  selected: readonly number[],
  exists: (messageId: number) => boolean
): readonly number[] {
  let changed: boolean = false;
  const next: number[] = [];
  for (let i = 0; i < selected.length; i++) {
    if (exists(selected[i])) {
      next.push(selected[i]);
    } else {
      changed = true;
    }
  }
  return changed ? next : selected;
}
