import { describe, it, expect } from '@ohos/hypium';
import { IdGenerator, RandomIdGenerator, SequentialIdGenerator } from '../main/ets/Id';

export default function idGeneratorTest() {
  describe('IdGeneratorTest', () => {
    it('sequentialIds_areDeterministicAndUnique', 0, () => {
      const gen: SequentialIdGenerator = new SequentialIdGenerator();
      expect(gen.nextRequestId()).assertEqual('req-test-1');
      expect(gen.nextRequestId()).assertEqual('req-test-2');
      expect(gen.nextRequestId()).assertEqual('req-test-3');
    });

    it('sequentialIds_honorCustomPrefix', 0, () => {
      const gen: SequentialIdGenerator = new SequentialIdGenerator('fix-');
      expect(gen.nextRequestId()).assertEqual('fix-1');
    });

    it('randomIds_haveStableFormat', 0, () => {
      const gen: RandomIdGenerator = new RandomIdGenerator();
      const id: string = gen.nextRequestId();
      expect(id.indexOf('req-')).assertEqual(0);
      expect(id.length).assertEqual(20);
    });

    it('randomIds_areUniqueAcrossManyDraws', 0, () => {
      const gen: RandomIdGenerator = new RandomIdGenerator();
      const seen: Set<string> = new Set<string>();
      for (let i = 0; i < 200; i++) {
        seen.add(gen.nextRequestId());
      }
      expect(seen.size).assertEqual(200);
    });

    it('randomIds_withInjectedSource_areDeterministic', 0, () => {
      const gen: RandomIdGenerator = new RandomIdGenerator(() => 0.5);
      const first: string = gen.nextRequestId();
      const second: string = gen.nextRequestId();
      expect(first).assertEqual(second);
      expect(first.indexOf('req-')).assertEqual(0);
      expect(first.length).assertEqual(20);
    });

    it('idGeneratorAbstraction_worksThroughInterface', 0, () => {
      const gen: IdGenerator = new SequentialIdGenerator('iface-');
      expect(gen.nextRequestId()).assertEqual('iface-1');
    });
  });
}
