/**
 * entry/src/main/ets/navigation/EntryNavigationController.ets
 *
 * 统一类型化导航控制器（NAV-001 / P1-ARCH-003）。
 * 包装 core/navigation 的 NavigationStack 与 RouteCodec，作为 entry 唯一的路由事实源。
 *
 * 核心特性：
 * 1. 强类型路由状态：通过 push/replace/pop/popToRoot 维护 NavigationStack；
 * 2. 路由监听与派发：支持订阅当前栈顶变更；
 * 3. 深链解析（Deep Link）：基于 RouteCodec 将外部 URI 解析并压栈；
 * 4. 序列化与状态恢复：支持页面状态的持久化与冷启动恢复；
 * 5. 返回栈管理：支持 search → chat → back → search 返回栈保活。
 */

import { ok, err, Result, AppError, AppErrors } from '@tgx/core-common';
import {
  AppRoute,
  RouteName,
  NavigationStack,
  RouteCodec,
  RouteRegistry,
  defaultRegistry,
  defaultDeepLinkRules,
  DeepLinkRule
} from '@tgx/core-navigation';
import { Logger } from '@tgx/observability';

export type RouteChangeListener = (currentRoute: AppRoute, previousRoute: AppRoute | null) => void;

export class EntryNavigationController {
  private stack: NavigationStack;
  private readonly codec: RouteCodec;
  private readonly deepLinkRules: DeepLinkRule[];
  private readonly subscribers: RouteChangeListener[] = [];
  private readonly logger?: Logger;

  constructor(
    initialRoute: AppRoute = { name: 'auth' },
    registry: RouteRegistry = defaultRegistry(),
    rules: DeepLinkRule[] = defaultDeepLinkRules(),
    logger?: Logger
  ) {
    this.codec = new RouteCodec(registry);
    this.deepLinkRules = rules;
    this.logger = logger;
    this.stack = new NavigationStack();
    this.stack.push(initialRoute);
  }

  getCurrentRoute(): AppRoute {
    const peeked: AppRoute | null = this.stack.peek();
    if (peeked === null) {
      return { name: 'auth' };
    }
    return peeked;
  }

  getRoutes(): AppRoute[] {
    return this.stack.getRoutes();
  }

  getSize(): number {
    return this.stack.getSize();
  }

  hasRoute(name: RouteName): boolean {
    const routes: AppRoute[] = this.stack.getRoutes();
    for (let i = 0; i < routes.length; i++) {
      if (routes[i].name === name) {
        return true;
      }
    }
    return false;
  }

  navigateTo(route: AppRoute): void {
    const prev: AppRoute = this.getCurrentRoute();
    this.stack.push(route);
    this.logger?.info('Navigation', `navigateTo: ${route.name} (stack depth=${this.stack.getSize()})`);
    this.notify(prev);
  }

  replace(route: AppRoute): void {
    const prev: AppRoute = this.getCurrentRoute();
    this.stack.replace(route);
    this.logger?.info('Navigation', `replace: ${route.name} (stack depth=${this.stack.getSize()})`);
    this.notify(prev);
  }

  /**
   * 重置根路由：清空除当前外所有栈并设为新根（用于登录成功进 home 或登出清栈回 auth）。
   */
  replaceRoot(route: AppRoute): void {
    const prev: AppRoute = this.getCurrentRoute();
    this.stack.popToRoot();
    this.stack.replace(route);
    this.logger?.info('Navigation', `replaceRoot: ${route.name}`);
    this.notify(prev);
  }

  /**
   * 回退：弹出栈顶路由。若当前仅剩根路由则不弹出并返回 false（交由系统默认处理）。
   */
  pop(): boolean {
    if (this.stack.getSize() <= 1) {
      return false;
    }
    const prev: AppRoute = this.getCurrentRoute();
    this.stack.pop();
    this.logger?.info('Navigation', `pop: current=${this.getCurrentRoute().name} (stack depth=${this.stack.getSize()})`);
    this.notify(prev);
    return true;
  }

  popToRoot(): void {
    if (this.stack.getSize() <= 1) {
      return;
    }
    const prev: AppRoute = this.getCurrentRoute();
    this.stack.popToRoot();
    this.logger?.info('Navigation', `popToRoot: current=${this.getCurrentRoute().name}`);
    this.notify(prev);
  }

  handleDeepLink(uri: string): Result<AppRoute, AppError> {
    const parseResult: Result<AppRoute, AppError> = this.codec.parseDeepLink(uri, this.deepLinkRules);
    if (parseResult.ok === false) {
      this.logger?.warn('Navigation', `handleDeepLink failed for uri: ${uri}`);
      return parseResult;
    }
    const route: AppRoute = parseResult.value;
    this.navigateTo(route);
    return ok(route);
  }

  serialize(): string {
    return this.stack.serialize(this.codec);
  }

  restore(serialized: string): Result<void, AppError> {
    const result: Result<NavigationStack, AppError> = NavigationStack.restore(serialized, this.codec);
    if (result.ok === false) {
      this.logger?.warn('Navigation', `restore failed: ${result.error.message}`);
      return err(result.error);
    }
    const restoredStack: NavigationStack = result.value;
    if (restoredStack.getSize() === 0) {
      return err(AppErrors.parameter('invalid', 'stack', 'empty stack after restore'));
    }
    const prev: AppRoute = this.getCurrentRoute();
    this.stack = restoredStack;
    this.logger?.info('Navigation', `stack restored: size=${this.stack.getSize()}, top=${this.getCurrentRoute().name}`);
    this.notify(prev);
    return ok(undefined);
  }

  subscribe(listener: RouteChangeListener): () => void {
    this.subscribers.push(listener);
    return () => {
      const index = this.subscribers.indexOf(listener);
      if (index >= 0) {
        this.subscribers.splice(index, 1);
      }
    };
  }

  private notify(prev: AppRoute | null): void {
    const current: AppRoute = this.getCurrentRoute();
    for (let i = 0; i < this.subscribers.length; i++) {
      this.subscribers[i](current, prev);
    }
  }
}
