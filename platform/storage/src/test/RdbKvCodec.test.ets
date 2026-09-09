import { describe, it, expect } from '@ohos/hypium';
import {
  RDB_TYPE_STRING,
  RDB_TYPE_NUMBER,
  RDB_TYPE_BOOLEAN,
  encodePreferenceValue,
  decodePreferenceRow,
  RdbKvRow
} from '../main/ets/core/RdbKvCodec';

export default function rdbKvCodecTest() {
  describe('RdbKvCodec', () => {
    it('encode_string_usesTextColumn', 0, () => {
      const row = encodePreferenceValue('hello');
      expect(row.typeTag).assertEqual(RDB_TYPE_STRING);
      expect(row.text).assertEqual('hello');
      expect(row.real === null).assertTrue();
      expect(row.integer === null).assertTrue();
    });

    it('encode_number_usesRealColumn', 0, () => {
      const row = encodePreferenceValue(42.5);
      expect(row.typeTag).assertEqual(RDB_TYPE_NUMBER);
      expect(row.real).assertEqual(42.5);
      expect(row.text === null).assertTrue();
    });

    it('encode_boolean_usesIntegerColumn', 0, () => {
      const t = encodePreferenceValue(true);
      expect(t.typeTag).assertEqual(RDB_TYPE_BOOLEAN);
      expect(t.integer).assertEqual(1);
      const f = encodePreferenceValue(false);
      expect(f.integer).assertEqual(0);
    });

    it('decode_roundTripsAllTypes', 0, () => {
      expect(decodePreferenceRow(encodePreferenceValue('x')).getOrNull()).assertEqual('x');
      expect(decodePreferenceRow(encodePreferenceValue(-0.5)).getOrNull()).assertEqual(-0.5);
      expect(decodePreferenceRow(encodePreferenceValue(true)).getOrNull()).assertTrue();
      expect(decodePreferenceRow(encodePreferenceValue(false)).getOrNull()).assertFalse();
    });

    it('decode_unknownTag_returnsCorrupted', 0, () => {
      const row: RdbKvRow = { typeTag: 99, text: null, real: null, integer: null };
      const r = decodePreferenceRow(row);
      expect(r.err).assertTrue();
      if (r.err) {
        expect(r.error.kind).assertEqual('storage');
        if (r.error.kind === 'storage') {
          expect(r.error.code).assertEqual('corrupted');
        }
      }
    });

    it('decode_nullMismatches_returnCorrupted', 0, () => {
      const s: RdbKvRow = { typeTag: RDB_TYPE_STRING, text: null, real: null, integer: null };
      expect(decodePreferenceRow(s).err).assertTrue();
      const n: RdbKvRow = { typeTag: RDB_TYPE_NUMBER, text: null, real: null, integer: null };
      expect(decodePreferenceRow(n).err).assertTrue();
      const b: RdbKvRow = { typeTag: RDB_TYPE_BOOLEAN, text: null, real: null, integer: null };
      expect(decodePreferenceRow(b).err).assertTrue();
    });

    it('decode_booleanNonBinary_returnsCorrupted', 0, () => {
      const row: RdbKvRow = { typeTag: RDB_TYPE_BOOLEAN, text: null, real: null, integer: 7 };
      expect(decodePreferenceRow(row).err).assertTrue();
    });
  });
}
