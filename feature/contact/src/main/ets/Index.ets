/**
 * feature/contact — 模块统一导出入口（CONTACT-101：联系人页）。
 */

export { ContactsItem, ContactsUiStateOptions, ContactsUiState } from './contract/ContactsUiState';
export {
  QueryChanged,
  OnContactsLoaded,
  OnContactsFailed,
  ContactTapped,
  ContactsIntent
} from './contract/ContactsIntent';
export { FetchContacts, OpenUserProfile, ContactsEffect } from './contract/ContactsEffect';
export { contactsReducer, filterContactsItems } from './reducer/ContactsReducer';
export {
  ContactsCoordinatorOptions,
  ContactsUiStateListener,
  ContactsCoordinator
} from './coordinator/ContactsCoordinator';
export { ContactsPage } from './pages/ContactsPage';
