import { TestRunner, AbilityDelegatorRegistry } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'PlatformNetworkTestRunner';

class PlatformNetworkTestRunner implements TestRunner {
  constructor() {}

  onPrepare(): void {
    hilog.info(DOMAIN, TAG, 'OnPrepare');
  }

  async onRun(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'onRun');
    const abilityDelegator = AbilityDelegatorRegistry.getAbilityDelegator();
    const abilityDelegatorArguments = AbilityDelegatorRegistry.getArguments();
    abilityDelegator.startAbility({ bundleName: abilityDelegatorArguments.bundleName,
      abilityName: 'TestAbility' });
    await abilityDelegator.print('PlatformNetworkTestRunner onRun');
  }
}

export default PlatformNetworkTestRunner;
