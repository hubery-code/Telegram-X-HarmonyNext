import appFilesPortContract, { appFilesQuotaContract } from './contract/AppFilesPortContract';
import { FakeAppFiles } from '../main/ets/fakes/FakeAppFiles';

export default function fakeAppFilesContractTest() {
  appFilesPortContract('FakeAppFiles', () => new FakeAppFiles());
  appFilesQuotaContract('FakeAppFiles', () => new FakeAppFiles(512));
}
