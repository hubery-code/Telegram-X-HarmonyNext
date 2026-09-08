import { describe, it, expect } from '@ohos/hypium';
import {
  DefaultSpacing,
  SPACING_TOKEN_NAMES,
  DefaultRadius,
  RADIUS_TOKEN_NAMES,
  DefaultMotion,
  MOTION_TOKEN_NAMES,
  BezierCurve
} from '../main/ets/Index';

export default function staticTokensTest() {
  describe('StaticTokensTest', () => {
    it('spacing_allTokensExistAndAreNonNegative', 0, () => {
      expect(SPACING_TOKEN_NAMES.length >= 8).assertTrue();
      for (const name of SPACING_TOKEN_NAMES) {
        const value = DefaultSpacing[name];
        expect(value >= 0 && !Number.isNaN(value)).assertTrue();
      }
    });

    it('spacing_scaleIsMonotonic', 0, () => {
      const ascending = ['hairline', 'xs', 'sm', 'md', 'lg', 'xl', 'xxl', 'huge'];
      for (let i = 1; i < ascending.length; i++) {
        expect(DefaultSpacing[ascending[i]] > DefaultSpacing[ascending[i - 1]]).assertTrue();
      }
    });

    it('radius_allTokensExist', 0, () => {
      for (const name of RADIUS_TOKEN_NAMES) {
        const value = DefaultRadius[name];
        expect(value >= 0 && !Number.isNaN(value)).assertTrue();
      }
      expect(DefaultRadius.full > DefaultRadius.xl).assertTrue();
    });

    it('motion_durationsAreOrdered', 0, () => {
      expect(DefaultMotion.durationInstant < DefaultMotion.durationFast).assertTrue();
      expect(DefaultMotion.durationFast < DefaultMotion.durationNormal).assertTrue();
      expect(DefaultMotion.durationNormal < DefaultMotion.durationSlow).assertTrue();
      expect(MOTION_TOKEN_NAMES.length).assertEqual(8);
    });

    it('motion_curvesAreValidUnitCubicBeziers', 0, () => {
      const curveNames = ['curveStandard', 'curveDecelerate', 'curveAccelerate', 'curveEmphasized'];
      for (const name of curveNames) {
        const c = DefaultMotion[name] as BezierCurve;
        expect(c.x1 >= 0 && c.x1 <= 1).assertTrue();
        expect(c.y1 >= 0 && c.y1 <= 1).assertTrue();
        expect(c.x2 >= 0 && c.x2 <= 1).assertTrue();
        expect(c.y2 >= 0 && c.y2 <= 1).assertTrue();
      }
    });
  });
}
