import { describe, it, expect } from '@ohos/hypium';
import {
  TdJsonRaw,
  TdObject,
  TdUnknownObject,
  UpdateAuthorizationState,
  UpdateNewMessage,
  AuthorizationStateReady,
  ErrorValue,
  Ok,
  decodeTdObject,
  encodeTdObject
} from '../main/ets/Index';
import { FIXTURES, TdFixture } from './gen/FixtureData';
import { canonicalJson } from './CanonicalJson';

function findFixture(name: string): TdFixture {
  for (const fixture of FIXTURES) {
    if (fixture.name === name) {
      return fixture;
    }
  }
  throw new Error('fixture not found: ' + name);
}

function assertRoundTrip(fixture: TdFixture): void {
  const raw: TdJsonRaw = JSON.parse(fixture.json) as TdJsonRaw;
  const decoded: TdObject | null = decodeTdObject(raw);
  expect(decoded === null).assertFalse();
  if (decoded === null) {
    return;
  }
  const encoded: Record<string, TdJsonRaw> = encodeTdObject(decoded);
  // Semantic equality, key order independent.
  expect(canonicalJson(encoded)).assertEqual(canonicalJson(raw));
  // Second decode must be stable (decode . encode is a fixed point).
  const decoded2: TdObject | null = decodeTdObject(encoded);
  expect(decoded2 === null).assertFalse();
  if (decoded2 === null) {
    return;
  }
  const encoded2: Record<string, TdJsonRaw> = encodeTdObject(decoded2);
  expect(canonicalJson(encoded2)).assertEqual(canonicalJson(encoded));
}

export default function fixtureRoundTripTest() {
  describe('FixtureRoundTripTest', () => {
    for (const fixture of FIXTURES) {
      it('fixture_' + fixture.name, 0, () => {
        assertRoundTrip(fixture);
      });
    }

    it('unknownTopLevel_fallsBackToUnknownObject', 0, () => {
      const raw: TdJsonRaw = JSON.parse(findFixture('unknown_01_top_level').json) as TdJsonRaw;
      const decoded: TdObject | null = decodeTdObject(raw);
      expect(decoded !== null && decoded instanceof TdUnknownObject).assertTrue();
    });

    it('unknownNestedContent_fallsBackToUnknownObjectInsideMessage', 0, () => {
      const raw: TdJsonRaw = JSON.parse(findFixture('unknown_02_nested_content').json) as TdJsonRaw;
      const decoded: TdObject | null = decodeTdObject(raw);
      expect(decoded !== null && decoded instanceof UpdateNewMessage).assertTrue();
      if (decoded !== null && decoded instanceof UpdateNewMessage) {
        const message = decoded.message;
        expect(message !== null).assertTrue();
        if (message !== null) {
          expect(message.content !== null && message.content instanceof TdUnknownObject).assertTrue();
          if (message.content !== null && message.content instanceof TdUnknownObject) {
            expect(message.content.type).assertEqual('messageContentFromFuture');
            expect(message.content.raw['flags'] !== undefined).assertTrue();
          }
        }
      }
    });

    it('summary_allFixturesPresentAndUnique', 0, () => {
      expect(FIXTURES.length).assertEqual(22);
      const seen: Record<string, boolean> = {};
      let authCount: number = 0;
      let msgCount: number = 0;
      for (const fixture of FIXTURES) {
        expect(seen[fixture.name] === undefined).assertTrue();
        seen[fixture.name] = true;
        if (fixture.name.indexOf('auth_') === 0) {
          authCount += 1;
        }
        if (fixture.name.indexOf('msg_') === 0) {
          msgCount += 1;
        }
        const raw: TdJsonRaw = JSON.parse(fixture.json) as TdJsonRaw;
        const record: Record<string, TdJsonRaw> = raw as Record<string, TdJsonRaw>;
        expect(typeof record['@type'] === 'string').assertTrue();
      }
      // Full authorization state machine coverage (13 states).
      expect(authCount).assertEqual(13);
      // updateNewMessage with varied content types.
      expect(msgCount).assertEqual(4);
    });

    it('authReady_decodesToConcreteStateClass', 0, () => {
      const fixture: TdFixture = findFixture('auth_10_ready');
      const raw: TdJsonRaw = JSON.parse(fixture.json) as TdJsonRaw;
      const decoded: TdObject | null = decodeTdObject(raw);
      expect(decoded !== null && decoded instanceof UpdateAuthorizationState).assertTrue();
      if (decoded !== null && decoded instanceof UpdateAuthorizationState) {
        const state = decoded.authorization_state;
        expect(state !== null && state instanceof AuthorizationStateReady).assertTrue();
      }
    });

    it('errorResponse_decodesToErrorValueWithCodeAndExtra', 0, () => {
      const fixture: TdFixture = findFixture('resp_01_error_with_extra');
      const raw: TdJsonRaw = JSON.parse(fixture.json) as TdJsonRaw;
      const decoded: TdObject | null = decodeTdObject(raw);
      expect(decoded !== null && decoded instanceof ErrorValue).assertTrue();
      if (decoded !== null && decoded instanceof ErrorValue) {
        expect(decoded.code).assertEqual(400);
        expect(decoded.message).assertEqual('PHONE_NUMBER_INVALID');
        expect(decoded.extra).assertEqual('req-42-007');
      }
    });

    it('okResponse_extraCorrelationTagIsPreserved', 0, () => {
      const fixture: TdFixture = findFixture('resp_02_ok_with_extra');
      const raw: TdJsonRaw = JSON.parse(fixture.json) as TdJsonRaw;
      const decoded: TdObject | null = decodeTdObject(raw);
      expect(decoded !== null && decoded instanceof Ok).assertTrue();
      if (decoded !== null && decoded instanceof Ok) {
        expect(decoded.extra).assertEqual('req-42-003');
      }
    });
  });
}
