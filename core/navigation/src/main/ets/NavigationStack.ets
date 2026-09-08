/**
 * core/navigation — NavigationStack：导航栈抽象（UI-002）。
 *
 * 纯逻辑栈，不依赖 ArkUI Navigation 组件；entry 侧由 adapter 把
 * push/replace/pop/popToRoot 桥接到 ArkUI Navigation 的 pathStack。
 *
 * 恢复序列化：serialize() 输出换行分隔的 encode 结果（编码后值不含结构字符，
 * 换行分隔安全）；restore() 逐条 parse，任何一条非法即整体拒绝（Err），
 * 并去除「与前一条完全相同」的连续重复项（重复恢复去重）。
 */

import { AppErrors } from '@tgx/core-common';
import { ok, err } from '@tgx/core-common';
import type { Result, AppError } from '@tgx/core-common';
import { AppRoute } from './Route';
import { RouteCodec } from './RouteCodec';

export interface StackEntry {
  readonly id: number;
  readonly route: AppRoute;
}

export class NavigationStack {
  private entries: StackEntry[] = [];
  private nextId: number = 1;

  push(route: AppRoute): StackEntry {
    const entry: StackEntry = { id: this.nextId, route: route };
    this.nextId = this.nextId + 1;
    this.entries.push(entry);
    return entry;
  }

  /** 替换栈顶；空栈时等价于 push。 */
  replace(route: AppRoute): StackEntry {
    if (this.entries.length === 0) {
      return this.push(route);
    }
    const entry: StackEntry = { id: this.nextId, route: route };
    this.nextId = this.nextId + 1;
    this.entries[this.entries.length - 1] = entry;
    return entry;
  }

  /** 弹出栈顶；空栈返回 null。 */
  pop(): AppRoute | null {
    if (this.entries.length === 0) {
      return null;
    }
    const removed: StackEntry = this.entries.pop() as StackEntry;
    return removed.route;
  }

  /** 回退到栈底：保留第一条，移除其余。 */
  popToRoot(): void {
    if (this.entries.length <= 1) {
      return;
    }
    const root: StackEntry = this.entries[0];
    this.entries = [root];
  }

  peek(): AppRoute | null {
    if (this.entries.length === 0) {
      return null;
    }
    return this.entries[this.entries.length - 1].route;
  }

  getSize(): number {
    return this.entries.length;
  }

  getRoutes(): AppRoute[] {
    const out: AppRoute[] = [];
    for (let i: number = 0; i < this.entries.length; i++) {
      out.push(this.entries[i].route);
    }
    return out;
  }

  /** 序列化为换行分隔的 path 列表（用 codec 编码，保证可解析往返）。 */
  serialize(codec: RouteCodec): string {
    const lines: string[] = [];
    for (let i: number = 0; i < this.entries.length; i++) {
      const encoded: Result<string, AppError> = codec.encode(this.entries[i].route);
      if (encoded.ok === false) {
        // 栈内路由对象来自类型化 push，encode 失败属于不变量破坏。
        throw new Error(`navigation stack entry not encodable: ${encoded.error.message}`);
      }
      lines.push(encoded.value);
    }
    return lines.join('\n');
  }

  /**
   * 从序列化文本恢复导航栈。
   * - 空文本 → 空栈；
   * - 任一 path 解析失败 → 整体 Err（恢复数据不可信时宁可丢弃）；
   * - 与前一条 path 完全相同的连续项被去除（重复恢复去重）。
   */
  static restore(serialized: string, codec: RouteCodec): Result<NavigationStack, AppError> {
    const stack: NavigationStack = new NavigationStack();
    if (serialized.length === 0) {
      return ok(stack);
    }
    const lines: string[] = serialized.split('\n');
    let previousPath: string | null = null;
    for (let i: number = 0; i < lines.length; i++) {
      const line: string = lines[i];
      if (line.length === 0) {
        return err(AppErrors.parameter('invalid', 'stack', `empty entry at line ${i}`));
      }
      if (line === previousPath) {
        continue;
      }
      const parsed: Result<AppRoute, AppError> = codec.parse(line);
      if (parsed.ok === false) {
        return err(AppErrors.parameter('invalid', 'stack', `entry ${i} not restorable: ${parsed.error.message}`));
      }
      stack.push(parsed.value);
      previousPath = line;
    }
    return ok(stack);
  }
}
