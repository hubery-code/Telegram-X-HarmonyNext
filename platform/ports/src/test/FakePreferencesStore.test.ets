import preferencesPortContract from './contract/PreferencesPortContract';
import { FakePreferencesStore } from '../main/ets/fakes/FakePreferencesStore';

export default function fakePreferencesContractTest() {
  preferencesPortContract('FakePreferencesStore', () => new FakePreferencesStore());
}
