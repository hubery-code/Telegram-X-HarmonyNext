/**
 * feature/contact — 联系人页纯 reducer（CONTACT-101）。
 *
 * 与 ProfileReducer 同约定：未知 kind 走尾部 default 原样返回。
 * 查询过滤在 reducer 内完成（双份缓冲：allItems 全量 + items 过滤视图），
 * 过滤纯函数 filterContactsItems 单独导出供单测覆盖。
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { ContactsItem, ContactsUiState, ContactsUiStateOptions } from '../contract/ContactsUiState';
import { buildContactsSections } from '../model/ContactsSections';
import { contactMatchesQuery } from '../model/ContactsFilter';
import {
  QueryChanged,
  OnContactsLoaded,
  OnContactsFailed,
  ContactTapped,
  ContactsIntent
} from '../contract/ContactsIntent';
import { OpenUserProfile, ContactsEffect } from '../contract/ContactsEffect';

/**
 * 查询过滤：交给 `model/ContactsFilter.contactMatchesQuery` —— **词首前缀**匹配展示名，
 * 或前缀匹配用户名（对齐 Android `ContactsController.sortUsers()` :901）。
 * 空查询原样返回全量引用，避免每次输入都新建数组触发整表重排。
 */
export function filterContactsItems(items: ContactsItem[], query: string): ContactsItem[] {
  if (query.trim().length === 0) {
    return items;
  }
  const out: ContactsItem[] = [];
  for (let i: number = 0; i < items.length; i++) {
    if (contactMatchesQuery(items[i], query)) {
      out.push(items[i]);
    }
  }
  return out;
}

/** 过滤视图与其字母分段一起出：两者必须由同一份 items 推出，否则索引条会对不上列表。 */
function toView(items: ContactsItem[], query: string): ContactsUiStateOptions {
  const filtered: ContactsItem[] = filterContactsItems(items, query);
  return {
    items: filtered,
    sections: buildContactsSections(filtered)
  };
}

export const contactsReducer: Reducer<ContactsUiState, ContactsIntent, ContactsEffect> = (
  state: ContactsUiState,
  intent: ContactsIntent,
  _env: ReducerEnv
): ReducerResult<ContactsUiState, ContactsEffect> => {
  switch (intent.kind) {
    case 'queryChanged': {
      const changed: QueryChanged = intent as QueryChanged;
      const view: ContactsUiStateOptions = toView(state.allItems, changed.query);
      return reduced(state.copyWith({
        query: changed.query,
        items: view.items,
        sections: view.sections
      }));
    }

    case 'onContactsLoaded': {
      const loaded: OnContactsLoaded = intent as OnContactsLoaded;
      const view: ContactsUiStateOptions = toView(loaded.items, state.query);
      return reduced(state.copyWith({
        allItems: loaded.items,
        items: view.items,
        sections: view.sections,
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
