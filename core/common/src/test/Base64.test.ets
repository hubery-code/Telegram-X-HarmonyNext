import { describe, it, expect } from '@ohos/hypium';
import { base64Encode, base64Decode } from '../main/ets/Base64';

export default function base64Test() {
  describe('Base64Test', () => {
    it('rfc4648_testVectors_encode', 0, () => {
      // "" -> ""
      expect(base64Encode(new Uint8Array([]))).assertEqual('');

      // "f" -> "Zg=="
      expect(base64Encode(new Uint8Array([0x66]))).assertEqual('Zg==');

      // "fo" -> "Zm8="
      expect(base64Encode(new Uint8Array([0x66, 0x6f]))).assertEqual('Zm8=');

      // "foo" -> "Zm9v"
      expect(base64Encode(new Uint8Array([0x66, 0x6f, 0x6f]))).assertEqual('Zm9v');

      // "foob" -> "Zm9vYg=="
      expect(base64Encode(new Uint8Array([0x66, 0x6f, 0x6f, 0x62]))).assertEqual('Zm9vYg==');

      // "fooba" -> "Zm9vYmE="
      expect(base64Encode(new Uint8Array([0x66, 0x6f, 0x6f, 0x62, 0x61]))).assertEqual('Zm9vYmE=');

      // "foobar" -> "Zm9vYmFy"
      expect(base64Encode(new Uint8Array([0x66, 0x6f, 0x6f, 0x62, 0x61, 0x72]))).assertEqual('Zm9vYmFy');
    });

    it('rfc4648_testVectors_decode', 0, () => {
      expect(base64Decode('').length).assertEqual(0);

      const d1: Uint8Array = base64Decode('Zg==');
      expect(d1.length).assertEqual(1);
      expect(d1[0]).assertEqual(0x66);

      const d2: Uint8Array = base64Decode('Zm8=');
      expect(d2.length).assertEqual(2);
      expect(d2[0]).assertEqual(0x66);
      expect(d2[1]).assertEqual(0x6f);

      const d3: Uint8Array = base64Decode('Zm9v');
      expect(d3.length).assertEqual(3);
      expect(d3[0]).assertEqual(0x66);
      expect(d3[1]).assertEqual(0x6f);
      expect(d3[2]).assertEqual(0x6f);

      const d6: Uint8Array = base64Decode('Zm9vYmFy');
      expect(d6.length).assertEqual(6);
      expect(d6[0]).assertEqual(0x66);
      expect(d6[5]).assertEqual(0x72);
    });

    it('roundTrip_32BytesHighEntropy', 0, () => {
      // 模拟 TDLib 32 字节高熵密钥
      const key: Uint8Array = new Uint8Array(32);
      for (let i = 0; i < 32; i++) {
        key[i] = (i * 37 + 13) & 0xff;
      }

      const encoded: string = base64Encode(key);
      expect(encoded.length).assertEqual(44); // 32 字节 Base64 编码为 44 字符 (含 == 填充)

      const decoded: Uint8Array = base64Decode(encoded);
      expect(decoded.length).assertEqual(32);
      for (let i = 0; i < 32; i++) {
        expect(decoded[i]).assertEqual(key[i]);
      }
    });

    it('roundTrip_boundaryValues', 0, () => {
      const zeros: Uint8Array = new Uint8Array(32); // 全部为 0
      const encZeros: string = base64Encode(zeros);
      const decZeros: Uint8Array = base64Decode(encZeros);
      expect(decZeros.length).assertEqual(32);
      for (let i = 0; i < 32; i++) {
        expect(decZeros[i]).assertEqual(0);
      }

      const ones: Uint8Array = new Uint8Array(32); // 全部为 0xff
      ones.fill(0xff);
      const encOnes: string = base64Encode(ones);
      const decOnes: Uint8Array = base64Decode(encOnes);
      expect(decOnes.length).assertEqual(32);
      for (let i = 0; i < 32; i++) {
        expect(decOnes[i]).assertEqual(0xff);
      }
    });

    it('decode_ignoresWhitespace', 0, () => {
      const withSpaces: string = ' Zm 9 v \n\r\t';
      const decoded: Uint8Array = base64Decode(withSpaces);
      expect(decoded.length).assertEqual(3);
      expect(decoded[0]).assertEqual(0x66);
      expect(decoded[1]).assertEqual(0x6f);
      expect(decoded[2]).assertEqual(0x6f);
    });

    it('decode_throwsOnInvalidInput', 0, () => {
      // 非法长度
      let threwLength: boolean = false;
      try {
        base64Decode('abc');
      } catch (e) {
        threwLength = true;
      }
      expect(threwLength).assertTrue();

      // 非法字符
      let threwChar: boolean = false;
      try {
        base64Decode('Zm9#');
      } catch (e) {
        threwChar = true;
      }
      expect(threwChar).assertTrue();
    });
  });
}
