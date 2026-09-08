import networkStatePortContract, { NetworkStateDriver } from './contract/NetworkStatePortContract';
import { FakeNetworkState } from '../main/ets/fakes/FakeNetworkState';
import { NetworkSnapshot } from '../main/ets/NetworkStatePort';

class FakeNetworkStateHolder {
  fake: FakeNetworkState = new FakeNetworkState();
}

class FakeNetworkStateDriver implements NetworkStateDriver {
  private readonly holder: FakeNetworkStateHolder;

  constructor(holder: FakeNetworkStateHolder) {
    this.holder = holder;
  }

  push(snapshot: NetworkSnapshot): void {
    this.holder.fake.push(snapshot);
  }
}

export default function fakeNetworkStateContractTest() {
  const holder: FakeNetworkStateHolder = new FakeNetworkStateHolder();
  networkStatePortContract(
    'FakeNetworkState',
    () => {
      holder.fake = new FakeNetworkState();
      return holder.fake;
    },
    new FakeNetworkStateDriver(holder)
  );
}
