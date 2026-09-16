/**
 * feature/contact — 联系人页纯 reducer（CONTACT-101）。
 *
 * 与 ProfileReducer 同约定：未知 kind 走尾部 default 原样返回。
 * 查询过滤在 reducer 内完成（双份缓冲：allItems 全量 + items 过滤视图），
 * 过滤纯函数 filterContactsItems 单独导出供单测覆盖。
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { ContactsItem, ContactsUiState } from '../contract/ContactsUiState';
import {
  QueryChanged,
  OnContactsLoaded,
  OnContactsFailed,
  ContactTapped,
  ContactsIntent
} from '../contract/ContactsIntent';
import { OpenUserProfile, ContactsEffect } from '../contract/ContactsEffect';

/**
 * 查询过滤：大小写不敏感子串匹配 displayName / username；
 * query 归一（trim + lowercase），空查询原样返回全量。
 */
export function filterContactsItems(items: ContactsItem[], query: string): ContactsItem[] {
  const normalized: string = query.trim().toLowerCase();
  if (normalized.length === 0) {
    return items;
  }
  const out: ContactsItem[] = [];
  for (let i: number = 0; i < items.length; i++) {
    const item: ContactsItem = items[i];
    if (item.displayName.toLowerCase().indexOf(normalized) >= 0) {
      out.push(item);
      continue;
    }
    if (item.username.length > 0 && item.username.toLowerCase().indexOf(normalized) >= 0) {
      out.push(item);
    }
  }
  return out;
}

export const contactsReducer: Reducer<ContactsUiState, ContactsIntent, ContactsEffect> = (
  state: ContactsUiState,
  intent: ContactsIntent,
  _env: ReducerEnv
): ReducerResult<ContactsUiState, ContactsEffect> => {
  switch (intent.kind) {
    case 'queryChanged': {
      const changed: QueryChanged = intent as QueryChanged;
      return reduced(state.copyWith({
        query: changed.query,
        items: filterContactsItems(state.allItems, changed.query)
      }));
    }

    case 'onContactsLoaded': {
      const loaded: OnContactsLoaded = intent as OnContactsLoaded;
      return reduced(state.copyWith({
        allItems: loaded.items,
        items: filterContactsItems(loaded.items, state.query),
        isLoading: false,
        errorMessage: null
      }));
    }

    case 'onContactsFailed': {
      const failed: OnContactsFailed = intent as OnContactsFailed;
      return reduced(state.copyWith({ isLoading: false, errorMessage: failed.error.message }));
    }

    case 'contactTapped': {
      const tapped: ContactTapped = intent as ContactTapped;
      if (tapped.userId <= 0) {
        return reduced(state);
      }
      const effect: OpenUserProfile = new OpenUserProfile(tapped.userId);
      return reduced(state, [effect]);
    }

    default:
      return reduced(state);
  }
};
