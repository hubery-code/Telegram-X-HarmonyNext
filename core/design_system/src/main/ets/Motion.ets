/**
 * Motion tokens. Curves are stored as cubic-bezier control points so the
 * module stays Kit-free; at the ArkUI boundary map them with
 * `curves.cubicBezier(motion.curveStandard.x1, ...)`.
 * Durations in milliseconds.
 * Stored as Record; keep MOTION_TOKEN_NAMES in sync when adding one.
 */
export interface BezierCurve {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}

export interface MotionTokens extends Record<string, number | BezierCurve> {
  durationInstant: number;
  durationFast: number;
  durationNormal: number;
  durationSlow: number;
  curveStandard: BezierCurve;
  curveDecelerate: BezierCurve;
  curveAccelerate: BezierCurve;
  curveEmphasized: BezierCurve;
}

export const DefaultMotion: MotionTokens = {
  durationInstant: 0,
  durationFast: 120,
  durationNormal: 200,
  durationSlow: 320,
  curveStandard: { x1: 0.4, y1: 0.0, x2: 0.2, y2: 1.0 },
  curveDecelerate: { x1: 0.0, y1: 0.0, x2: 0.2, y2: 1.0 },
  curveAccelerate: { x1: 0.4, y1: 0.0, x2: 1.0, y2: 1.0 },
  curveEmphasized: { x1: 0.2, y1: 0.0, x2: 0.0, y2: 1.0 }
};

export const MOTION_TOKEN_NAMES: string[] = [
  'durationInstant',
  'durationFast',
  'durationNormal',
  'durationSlow',
  'curveStandard',
  'curveDecelerate',
  'curveAccelerate',
  'curveEmphasized'
];
