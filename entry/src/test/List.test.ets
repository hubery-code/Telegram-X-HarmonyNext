import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, it, expect } from '@ohos/hypium';
import lifecycleCoordinatorTest from './lifecycle/LifecycleCoordinator.test';
import bootstrapKeystoreTest from './lifecycle/BootstrapKeystore.test';
import entryNavigationTest from './navigation/EntryNavigation.test';

const DOMAIN: number = 0x0000;
const TAG: string = 'ListTest';

export default function listTest() {
  describe('ListTest', () => {
    it('assertContain', 0, () => {
      hilog.info(DOMAIN, TAG, 'assertContain start');
      let a: string = 'abc';
      let b: string = 'b';
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
  });

  lifecycleCoordinatorTest();
  bootstrapKeystoreTest();
  entryNavigationTest();
}
