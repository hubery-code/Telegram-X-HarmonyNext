import { TestRunner, AbilityDelegatorRegistry } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'OpenHarmonyTestRunner';

class OpenHarmonyTestRunner implements TestRunner {
  constructor() {}

  onPrepare(): void {
    hilog.info(DOMAIN, TAG, 'OpenHarmonyTestRunner OnPrepare');
  }

  async onRun(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'OpenHarmonyTestRunner onRun');
    const abilityDelegator = AbilityDelegatorRegistry.getAbilityDelegator();
    const abilityDelegatorArguments = AbilityDelegatorRegistry.getArguments();
    const testAbilityName: string = 'TestAbility';
    abilityDelegator.startAbility({ bundleName: abilityDelegatorArguments.bundleName,
      abilityName: testAbilityName });
    await abilityDelegator.print('OpenHarmonyTestRunner onRun');
  }
}

export default OpenHarmonyTestRunner;
