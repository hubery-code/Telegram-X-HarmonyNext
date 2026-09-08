/**
 * core/common — Result 判别联合。
 *
 * ArkTS 习惯的 Rust/Kotlin Result 等价物：ok/err 两个分支，
 * map / flatMap / mapError / getOrElse / fold 组合子。
 * 领域代码用 Result 表达可预期失败，不做异常控制流。
 *
 * 用法：函数声明返回 Result<T, AppError>，用 ok(value) / err(error)
 * 构造；类型参数由返回类型上下文推断。
 */

export type Result<T, E> = Ok<T, E> | Err<T, E>;

export class Ok<T, E> {
  readonly ok: true = true;
  readonly err: false = false;
  readonly value: T;

  constructor(value: T) {
    this.value = value;
  }

  isOk(): boolean {
    return true;
  }

  isErr(): boolean {
    return false;
  }

  map<U>(fn: (value: T) => U): Result<U, E> {
    return new Ok<U, E>(fn(this.value));
  }

  flatMap<U>(fn: (value: T) => Result<U, E>): Result<U, E> {
    return fn(this.value);
  }

  mapError<F>(fn: (error: E) => F): Result<T, F> {
    return new Ok<T, F>(this.value);
  }

  getOrElse(defaultValue: T): T {
    return this.value;
  }

  getOrNull(): T {
    return this.value;
  }

  fold<U>(onOk: (value: T) => U, onErr: (error: E) => U): U {
    return onOk(this.value);
  }
}

export class Err<T, E> {
  readonly ok: false = false;
  readonly err: true = true;
  readonly error: E;

  constructor(error: E) {
    this.error = error;
  }

  isOk(): boolean {
    return false;
  }

  isErr(): boolean {
    return true;
  }

  map<U>(fn: (value: T) => U): Result<U, E> {
    return new Err<U, E>(this.error);
  }

  flatMap<U>(fn: (value: T) => Result<U, E>): Result<U, E> {
    return new Err<U, E>(this.error);
  }

  mapError<F>(fn: (error: E) => F): Result<T, F> {
    return new Err<T, F>(fn(this.error));
  }

  getOrElse(defaultValue: T): T {
    return defaultValue;
  }

  getOrNull(): null {
    return null;
  }

  fold<U>(onOk: (value: T) => U, onErr: (error: E) => U): U {
    return onErr(this.error);
  }
}

export function ok<T, E>(value: T): Result<T, E> {
  return new Ok<T, E>(value);
}

export function err<T, E>(error: E): Result<T, E> {
  return new Err<T, E>(error);
}
