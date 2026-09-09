/**
 * core/account — accountId 生成器（CORE-003）。
 *
 * accountId 是账号的稳定字符串标识（跨进程存活，写入持久化描述符），
 * 与 TDLib 进程内的 clientId 不同：clientId 每次冷启动经 createClient 重新分配。
 * 生产用 RandomAccountIdGenerator；测试注入 Sequential/固定 fake 保证确定性。
 */

export interface AccountIdGenerator {
  nextAccountId(): string;
}

const ACCOUNT_ID_PREFIX: string = 'acct-';
const ACCOUNT_ID_RANDOM_LENGTH: number = 20;
const ALPHABET: string = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

export class RandomAccountIdGenerator implements AccountIdGenerator {
  private readonly randomSource: () => number;

  constructor(randomSource?: () => number) {
    if (randomSource !== undefined) {
      this.randomSource = randomSource;
    } else {
      this.randomSource = Math.random;
    }
  }

  nextAccountId(): string {
    let id: string = ACCOUNT_ID_PREFIX;
    for (let i = 0; i < ACCOUNT_ID_RANDOM_LENGTH; i++) {
      const index: number = Math.floor(this.randomSource() * ALPHABET.length);
      id += ALPHABET.charAt(index);
    }
    return id;
  }
}

/** 测试 fake：单调递增、可预期。 */
export class SequentialAccountIdGenerator implements AccountIdGenerator {
  private counter: number = 0;
  private readonly prefix: string;

  constructor(prefix: string = 'acct-test-') {
    this.prefix = prefix;
  }

  nextAccountId(): string {
    this.counter += 1;
    return `${this.prefix}${this.counter}`;
  }
}
