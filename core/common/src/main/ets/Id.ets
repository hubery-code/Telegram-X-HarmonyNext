/**
 * core/common — Id 生成抽象（CORE-001）。
 *
 * requestId 等局部标识只允许经 IdGenerator 生成，便于注入 fake 做确定性测试。
 * - RandomIdGenerator：生产用，默认 Math.random，可通过注入 random source 做确定性测试；
 * - SequentialIdGenerator：测试 fake，单调递增、可预期。
 */

export interface IdGenerator {
  nextRequestId(): string;
}

const REQUEST_ID_PREFIX: string = 'req-';
const REQUEST_ID_LENGTH: number = 16;
const ALPHABET: string = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

export class RandomIdGenerator implements IdGenerator {
  private readonly randomSource: () => number;

  constructor(randomSource?: () => number) {
    if (randomSource !== undefined) {
      this.randomSource = randomSource;
    } else {
      this.randomSource = Math.random;
    }
  }

  nextRequestId(): string {
    let id: string = REQUEST_ID_PREFIX;
    for (let i = 0; i < REQUEST_ID_LENGTH; i++) {
      const index: number = Math.floor(this.randomSource() * ALPHABET.length);
      id += ALPHABET.charAt(index);
    }
    return id;
  }
}

export class SequentialIdGenerator implements IdGenerator {
  private counter: number = 0;
  private readonly prefix: string;

  constructor(prefix: string = 'req-test-') {
    this.prefix = prefix;
  }

  nextRequestId(): string {
    this.counter += 1;
    return `${this.prefix}${this.counter}`;
  }
}
