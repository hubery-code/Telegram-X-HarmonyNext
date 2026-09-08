import { describe, it, expect } from '@ohos/hypium';
import { Result, Ok, Err, ok, err } from '../main/ets/Result';

export default function resultTest() {
  describe('ResultTest', () => {
    it('ok_map_transformsValue', 0, () => {
      const r: Result<number, string> = ok(1);
      const mapped: Result<number, string> = r.map((v: number) => v + 1);
      expect(mapped.isOk()).assertTrue();
      expect(mapped.getOrElse(0)).assertEqual(2);
    });

    it('err_map_preservesError', 0, () => {
      const r: Result<number, string> = err('boom');
      const mapped: Result<number, string> = r.map((v: number) => v + 1);
      expect(mapped.isErr()).assertTrue();
      expect(mapped.getOrElse(42)).assertEqual(42);
      expect(mapped.fold((v: number) => `ok:${v}`, (e: string) => `err:${e}`)).assertEqual('err:boom');
    });

    it('flatMap_chainsOkAndErr', 0, () => {
      const okChain: Result<number, string> = ok<number, string>(2)
        .flatMap((v: number) => ok<number, string>(v * 3))
        .flatMap((v: number) => ok<number, string>(v + 1));
      expect(okChain.getOrElse(0)).assertEqual(7);

      const errChain: Result<number, string> = ok<number, string>(2)
        .flatMap((v: number) => err<number, string>('stop'))
        .flatMap((v: number) => ok<number, string>(999));
      expect(errChain.isErr()).assertTrue();
      expect(errChain.fold((v: number) => 'ok', (e: string) => e)).assertEqual('stop');
    });

    it('mapError_transformsOnlyErrBranch', 0, () => {
      const okSide: Result<number, number> = ok<number, string>(1).mapError((e: string) => e.length);
      expect(okSide.isOk()).assertTrue();
      expect(okSide.getOrElse(0)).assertEqual(1);

      const errSide: Result<number, number> = err<number, string>('abcd').mapError((e: string) => e.length);
      expect(errSide.isErr()).assertTrue();
      expect(errSide.fold((v: number) => -1, (e: number) => e)).assertEqual(4);
    });

    it('getOrElse_and_getOrNull', 0, () => {
      const good: Result<number, string> = ok(5);
      expect(good.getOrElse(0)).assertEqual(5);
      expect(good.getOrNull()).assertEqual(5);

      const bad: Result<number, string> = err('x');
      expect(bad.getOrElse(0)).assertEqual(0);
      expect(bad.getOrNull() === null).assertTrue();
    });

    it('fold_dispatchesBranch', 0, () => {
      const okR: Result<number, string> = ok(10);
      const errR: Result<number, string> = err('e');
      expect(okR.fold((v: number) => v * 2, (e: string) => 0)).assertEqual(20);
      expect(errR.fold((v: number) => v * 2, (e: string) => 0)).assertEqual(0);
    });

    it('discriminantNarrowing_exposesValueOrError', 0, () => {
      const r: Result<number, string> = ok(3);
      if (r.ok) {
        expect(r.value).assertEqual(3);
      } else {
        expect(false).assertTrue();
      }

      const e: Result<number, string> = err('no');
      if (e.err) {
        expect(e.error).assertEqual('no');
      } else {
        expect(false).assertTrue();
      }
    });

    it('constructors_exposeStableDiscriminants', 0, () => {
      const o: Ok<number, string> = new Ok<number, string>(1);
      const er: Err<number, string> = new Err<number, string>('x');
      expect(o.ok).assertTrue();
      expect(o.err).assertFalse();
      expect(er.ok).assertFalse();
      expect(er.err).assertTrue();
    });
  });
}
