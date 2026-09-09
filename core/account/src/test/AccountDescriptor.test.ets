/**
 * AccountDescriptor 编解码 + AccountDirectories 校验单测（CORE-003）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, Result } from '@tgx/core-common';
import {
  AccountDescriptor,
  createDescriptor,
  decodeAccountDescriptor,
  decodeAccountManifest,
  encodeAccountDescriptor,
  encodeAccountManifest
} from '../main/ets/AccountDescriptor';
import {
  AccountDirectoryLayout,
  buildAccountDirectories,
  validateAccountKey
} from '../main/ets/AccountDirectories';

function expectErr(result: Result<Object, AppError>): AppError {
  expect(result.ok).assertFalse();
  if (result.ok === false) {
    return result.error;
  }
  const fallback: AppError = { kind: 'internal', invariant: 'test', message: 'unreachable' };
  return fallback;
}

export default function accountDescriptorTest() {
  describe('AccountDescriptorTest', () => {

    it('encodeDecode_roundTrips', 0, () => {
      const original: AccountDescriptor = createDescriptor('8613800138000', 'acct-abc', 1725840000000, true);
      const decoded: Result<AccountDescriptor, AppError> = decodeAccountDescriptor(encodeAccountDescriptor(original));
      expect(decoded.ok).assertTrue();
      if (decoded.ok) {
        expect(decoded.value.accountKey).assertEqual('8613800138000');
        expect(decoded.value.accountId).assertEqual('acct-abc');
        expect(decoded.value.createdAtMillis).assertEqual(1725840000000);
        expect(decoded.value.enabled).assertTrue();
      }
    });

    it('decode_malformedJson_returnsCorrupted', 0, () => {
      const error: AppError = expectErr(decodeAccountDescriptor('not json{{'));
      expect(error.kind).assertEqual('storage');
      if (error.kind === 'storage') {
        expect(error.code).assertEqual('corrupted');
      }
    });

    it('decode_missingAccountKey_returnsCorrupted', 0, () => {
      const error: AppError = expectErr(decodeAccountDescriptor('{"accountId":"a","createdAtMillis":1,"enabled":true}'));
      expect(error.kind).assertEqual('storage');
    });

    it('decode_emptyAccountKey_returnsCorrupted', 0, () => {
      const error: AppError = expectErr(decodeAccountDescriptor('{"accountKey":"","accountId":"a","createdAtMillis":1,"enabled":true}'));
      expect(error.kind).assertEqual('storage');
    });

    it('decode_missingEnabled_returnsCorrupted', 0, () => {
      const error: AppError = expectErr(decodeAccountDescriptor('{"accountKey":"k","accountId":"a","createdAtMillis":1}'));
      expect(error.kind).assertEqual('storage');
    });

    it('decode_negativeCreatedAt_returnsCorrupted', 0, () => {
      const error: AppError = expectErr(decodeAccountDescriptor('{"accountKey":"k","accountId":"a","createdAtMillis":-5,"enabled":true}'));
      expect(error.kind).assertEqual('storage');
    });

    it('manifest_roundTrips_multipleDescriptors', 0, () => {
      const list: AccountDescriptor[] = [
        createDescriptor('a', 'acct-1', 100, true),
        createDescriptor('b', 'acct-2', 200, false)
      ];
      const decoded: Result<AccountDescriptor[], AppError> = decodeAccountManifest(encodeAccountManifest(list));
      expect(decoded.ok).assertTrue();
      if (decoded.ok) {
        expect(decoded.value.length).assertEqual(2);
        expect(decoded.value[0].accountKey).assertEqual('a');
        expect(decoded.value[0].enabled).assertTrue();
        expect(decoded.value[1].accountKey).assertEqual('b');
        expect(decoded.value[1].enabled).assertFalse();
      }
    });

    it('manifest_oneBadEntry_failsWholeManifest', 0, () => {
      const list: AccountDescriptor[] = [createDescriptor('a', 'acct-1', 100, true)];
      const good: string = encodeAccountManifest(list);
      const corrupted: string = good.replace('"accountId":"acct-1"', '"accountId":""');
      const decoded: Result<AccountDescriptor[], AppError> = decodeAccountManifest(corrupted);
      expect(decoded.ok).assertFalse();
    });

    it('manifest_unsupportedVersion_fails', 0, () => {
      const decoded: Result<AccountDescriptor[], AppError> = decodeAccountManifest('{"schemaVersion":99,"accounts":[]}');
      expect(decoded.ok).assertFalse();
    });

    it('directories_validKey_buildsLayout', 0, () => {
      const layout: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('8613800138000');
      expect(layout.ok).assertTrue();
      if (layout.ok) {
        expect(layout.value.accountDir.root).assertEqual('files');
        expect(layout.value.accountDir.sub).assertEqual('accounts/8613800138000');
        expect(layout.value.tdlibDbDir.sub).assertEqual('accounts/8613800138000/tdlib/db');
        expect(layout.value.tdlibFilesDir.sub).assertEqual('accounts/8613800138000/tdlib/files');
        expect(layout.value.exportsDir.sub).assertEqual('accounts/8613800138000/exports');
      }
    });

    it('directories_keyWithSlash_rejected', 0, () => {
      const error: AppError = expectErr(buildAccountDirectories('a/b'));
      expect(error.kind).assertEqual('parameter');
    });

    it('directories_dotDotKey_rejected', 0, () => {
      const error: AppError = expectErr(buildAccountDirectories('..'));
      expect(error.kind).assertEqual('parameter');
    });

    it('directories_emptyKey_rejected', 0, () => {
      const error: AppError = expectErr(buildAccountDirectories(''));
      expect(error.kind).assertEqual('parameter');
      if (error.kind === 'parameter') {
        expect(error.code).assertEqual('missing');
      }
    });

    it('validateAccountKey_acceptsPlainKey', 0, () => {
      expect(validateAccountKey('user-42') === null).assertTrue();
    });
  });
}
