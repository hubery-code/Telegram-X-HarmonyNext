/**
 * core/common — RFC 4648 Base64 编解码器。
 *
 * 纯 ArkTS/TypeScript 实现，零平台依赖（可在 node / ArkTS / hypium 中运行）。
 * 用于将二进制密钥（Uint8Array）转换为 TDLib JSON 通信协议所要求的 Base64 字符串。
 */

const BASE64_CHARS: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

const REVERSE_LOOKUP: number[] = [
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 62, -1, -1, -1, 63,
  52, 53, 54, 55, 56, 57, 58, 59, 60, 61, -1, -1, -1, -1, -1, -1,
  -1,  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14,
  15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, -1, -1, -1, -1, -1,
  -1, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
  41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, -1, -1, -1, -1, -1
];

/**
 * 将二进制数据编码为标准 Base64 字符串（RFC 4648）。
 */
export function base64Encode(bytes: Uint8Array): string {
  const len: number = bytes.length;
  if (len === 0) {
    return '';
  }

  let result: string = '';
  let i: number = 0;

  for (; i + 2 < len; i += 3) {
    const b0: number = bytes[i];
    const b1: number = bytes[i + 1];
    const b2: number = bytes[i + 2];

    result += BASE64_CHARS.charAt(b0 >> 2);
    result += BASE64_CHARS.charAt(((b0 & 0x03) << 4) | (b1 >> 4));
    result += BASE64_CHARS.charAt(((b1 & 0x0f) << 2) | (b2 >> 6));
    result += BASE64_CHARS.charAt(b2 & 0x3f);
  }

  const remaining: number = len - i;
  if (remaining === 1) {
    const b0: number = bytes[i];
    result += BASE64_CHARS.charAt(b0 >> 2);
    result += BASE64_CHARS.charAt((b0 & 0x03) << 4);
    result += '==';
  } else if (remaining === 2) {
    const b0: number = bytes[i];
    const b1: number = bytes[i + 1];
    result += BASE64_CHARS.charAt(b0 >> 2);
    result += BASE64_CHARS.charAt(((b0 & 0x03) << 4) | (b1 >> 4));
    result += BASE64_CHARS.charAt((b1 & 0x0f) << 2);
    result += '=';
  }

  return result;
}

/**
 * 将标准 Base64 字符串解码为二进制数据（Uint8Array）。
 * 忽略空白字符（换行、回车、空格）。
 */
export function base64Decode(str: string): Uint8Array {
  // 清洗空白
  let clean: string = '';
  for (let i = 0; i < str.length; i++) {
    const ch: string = str.charAt(i);
    if (ch !== ' ' && ch !== '\t' && ch !== '\r' && ch !== '\n') {
      clean += ch;
    }
  }

  if (clean.length === 0) {
    return new Uint8Array(0);
  }

  if (clean.length % 4 !== 0) {
    throw new Error(`Invalid Base64 string length: ${clean.length}`);
  }

  let padCount: number = 0;
  if (clean.charAt(clean.length - 1) === '=') {
    padCount += 1;
    if (clean.charAt(clean.length - 2) === '=') {
      padCount += 1;
    }
  }

  const outputLen: number = (clean.length / 4) * 3 - padCount;
  const out: Uint8Array = new Uint8Array(outputLen);
  let outIndex: number = 0;

  for (let i = 0; i < clean.length; i += 4) {
    const c0: number = clean.charCodeAt(i);
    const c1: number = clean.charCodeAt(i + 1);
    const c2: number = clean.charCodeAt(i + 2);
    const c3: number = clean.charCodeAt(i + 3);

    const v0: number = c0 < 128 ? REVERSE_LOOKUP[c0] : -1;
    const v1: number = c1 < 128 ? REVERSE_LOOKUP[c1] : -1;
    const v2: number = (c2 === 61) ? 0 : (c2 < 128 ? REVERSE_LOOKUP[c2] : -1);
    const v3: number = (c3 === 61) ? 0 : (c3 < 128 ? REVERSE_LOOKUP[c3] : -1);

    if (v0 === -1 || v1 === -1 || (c2 !== 61 && v2 === -1) || (c3 !== 61 && v3 === -1)) {
      throw new Error('Invalid Base64 character encountered');
    }

    const triple: number = (v0 << 18) | (v1 << 12) | (v2 << 6) | v3;

    if (outIndex < outputLen) {
      out[outIndex++] = (triple >> 16) & 0xff;
    }
    if (outIndex < outputLen) {
      out[outIndex++] = (triple >> 8) & 0xff;
    }
    if (outIndex < outputLen) {
      out[outIndex++] = triple & 0xff;
    }
  }

  return out;
}
