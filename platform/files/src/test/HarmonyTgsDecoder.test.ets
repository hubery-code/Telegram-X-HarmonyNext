/**
 * platform/files — TGS 解码器单测（TGS-101）。
 *
 * 覆盖范围划在「Local Test 运行时能真正干活的那一侧」：这个运行时里 `@ohos.zlib` 的流式
 * 接口是空壳（探针实测：`deflateInit2`/`inflate` 全回 status 0，但 `totalOut` 是
 * `undefined`、一段自压自解的回路解出 0 字节），所以 gzip 分支**不在这里证**，
 * 留给模拟器上的真档取证（`.hilog` 里能看到 inflate 的实际字节数）。
 * 这正是分层里「Kit 调用不进单测逻辑」的同一件事，只是这次撞在解压上。
 *
 * 钉住的五条（都不依赖 zlib）：
 * - 不是 gzip 的输入按「已是 JSON」原样放行（TDLib 哪天直接给 `.json` 不用改代码）；
 * - 解出来不像 JSON → 回 `AppError`，绝不回半截文本（上层靠它退回缩略图）；
 * - 文件读不到 → 回 `AppError`；
 * - 同一个路径二次解码命中内存缓存：把档从假文件系统里删掉后仍应解得出来；
 * - gzip 魔数与 JSON 形状两个纯判定的边界。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, Result } from '@tgx/core-common';
import { FakeAppFiles } from '@tgx/platform-ports';
import { HarmonyTgsDecoder, bytesAreGzipStream, textLooksLikeLottieJson } from '../main/ets/HarmonyTgsDecoder';

/** gzip('{"v":"5.5.2",...,"layers":[{"ddd":0,"ind":1,"ty":4,"nm":"shape"}]}') 的字节，117 B。 */
const GZIP_LOTTIE: number[] = [
  0x1f, 0x8b, 0x08, 0x00, 0xc1, 0xc5, 0xb7, 0x6a, 0x02, 0xff, 0x3d, 0xcc, 0x4b, 0x0a, 0x80, 0x30,
  0x0c, 0x04, 0xd0, 0xbb, 0xcc, 0x3a, 0x88, 0x55, 0xeb, 0x22, 0x57, 0x11, 0x17, 0x85, 0x56, 0x2c,
  0x68, 0x2d, 0xd6, 0x0f, 0x22, 0xde, 0xdd, 0x28, 0xe2, 0xea, 0x0d, 0x64, 0x26, 0x27, 0x36, 0x30,
  0x74, 0xa6, 0xb3, 0x02, 0x84, 0x6e, 0x06, 0x97, 0x39, 0xc1, 0x47, 0xb0, 0x30, 0x09, 0xb5, 0xb8,
  0x83, 0xb5, 0x2a, 0x08, 0xfd, 0x67, 0x18, 0x65, 0xb3, 0x06, 0x2f, 0x0b, 0x6b, 0xed, 0x5b, 0x35,
  0x29, 0xb9, 0x25, 0x81, 0x9b, 0x96, 0x30, 0x98, 0xc3, 0xcd, 0x4f, 0x3e, 0xff, 0xb3, 0x0f, 0xa2,
  0x22, 0x2c, 0x07, 0xb8, 0xfa, 0x1e, 0xa4, 0xde, 0x44, 0x87, 0xab, 0xbd, 0x6e, 0x0a, 0x2d, 0x5c,
  0xd4, 0x84, 0x00, 0x00, 0x00
];

const LOTTIE_JSON: string =
  '{"v":"5.5.2","fr":30,"ip":0,"op":60,"w":512,"h":512,"nm":"uni","ddd":0,"assets":[],'
  + '"layers":[{"ddd":0,"ind":1,"ty":4,"nm":"shape"}]}';

const JSON_PATH: string = '/sandbox/files/tdlib/db/stickers/1052321353216032834.json';

function bytesOf(values: number[]): Uint8Array {
  const out: Uint8Array = new Uint8Array(values.length);
  for (let i = 0; i < values.length; i++) {
    out[i] = values[i];
  }
  return out;
}

function utf8(text: string): Uint8Array {
  const out: number[] = [];
  for (let i = 0; i < text.length; i++) {
    out.push(text.charCodeAt(i) & 0xff);
  }
  return bytesOf(out);
}

export default function harmonyTgsDecoderTest() {
  describe('HarmonyTgsDecoderTest', () => {

    it('plain_json_passes_through', 0, async () => {
      const files: FakeAppFiles = new FakeAppFiles();
      files.writeBytes(JSON_PATH, utf8(LOTTIE_JSON));
      const decoder: HarmonyTgsDecoder = new HarmonyTgsDecoder(files);
      const res: Result<string, AppError> = await decoder.decode(JSON_PATH);
      if (res.ok === true) {
        expect(res.value).assertEqual(LOTTIE_JSON);
      } else {
        expect(`unexpected ${res.error.kind}:${res.error.message}`).assertEqual(LOTTIE_JSON);
      }
    });

    it('non_json_payload_is_a_failure_not_truncated_text', 0, async () => {
      const files: FakeAppFiles = new FakeAppFiles();
      const path: string = '/sandbox/files/tdlib/db/stickers/broken.tgs';
      files.writeBytes(path, utf8('this is not a lottie json'));
      const decoder: HarmonyTgsDecoder = new HarmonyTgsDecoder(files);
      const res: Result<string, AppError> = await decoder.decode(path);
      expect(res.err).assertTrue();
    });

    it('missing_file_reports_error', 0, async () => {
      const decoder: HarmonyTgsDecoder = new HarmonyTgsDecoder(new FakeAppFiles());
      const res: Result<string, AppError> = await decoder.decode(JSON_PATH);
      expect(res.err).assertTrue();
    });

    it('second_decode_hits_the_memory_cache', 0, async () => {
      const files: FakeAppFiles = new FakeAppFiles();
      files.writeBytes(JSON_PATH, utf8(LOTTIE_JSON));
      const decoder: HarmonyTgsDecoder = new HarmonyTgsDecoder(files);
      const first: Result<string, AppError> = await decoder.decode(JSON_PATH);
      expect(first.ok).assertTrue();
      // 把档从假沙盒里抹掉：还能解出来 = 走的是缓存，没有重复读盘
      files.delete(JSON_PATH);
      const second: Result<string, AppError> = await decoder.decode(JSON_PATH);
      if (second.ok === true) {
        expect(second.value).assertEqual(LOTTIE_JSON);
      } else {
        expect(`unexpected ${second.error.kind}:${second.error.message}`).assertEqual(LOTTIE_JSON);
      }
    });

    it('gzip_magic_and_json_shape_checks', 0, () => {
      expect(bytesAreGzipStream(bytesOf(GZIP_LOTTIE))).assertTrue();
      expect(bytesAreGzipStream(utf8(LOTTIE_JSON))).assertFalse();
      expect(bytesAreGzipStream(bytesOf([0x1f]))).assertFalse();
      expect(bytesAreGzipStream(bytesOf([]))).assertFalse();
      expect(textLooksLikeLottieJson('  \n {"v":"5.5.2"}')).assertTrue();
      expect(textLooksLikeLottieJson('{"v":1')).assertTrue();
      expect(textLooksLikeLottieJson('[')).assertFalse();
      expect(textLooksLikeLottieJson('')).assertFalse();
    });
  });
}
