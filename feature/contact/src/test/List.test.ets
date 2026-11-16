import contactsReducerTest from './ContactsReducer.test';
import contactsSectionsTest from './ContactsSections.test';
import contactsFilterTest from './ContactsFilter.test';
import contactsMultiSelectReducerTest from './ContactsMultiSelectReducer.test';

export default function testsuite(): void {
  contactsReducerTest();
  contactsSectionsTest();
  contactsFilterTest();
  contactsMultiSelectReducerTest();
}
