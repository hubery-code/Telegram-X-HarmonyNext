/**
 * core/navigation — RouteRegistry：路由注册与查找（UI-002）。
 *
 * route name ↔ path 模板双向查找；注册重复 name 或重复 pathTemplate 返回错误，
 * 不做异常控制流。默认注册表 defaultRegistry() 预置 ROUTE_DEFINITIONS 全部路由，
 * entry/feature 也可以 new RouteRegistry() 注册自定义路由（测试隔离同样适用）。
 */

import { AppErrors } from '@tgx/core-common';
import { ok, err } from '@tgx/core-common';
import type { Result, AppError } from '@tgx/core-common';
import { RouteDefinition, RouteName, ROUTE_DEFINITIONS } from './Route';

export class RouteRegistry {
  private readonly byName: Map<string, RouteDefinition> = new Map<string, RouteDefinition>();
  private readonly byTemplate: Map<string, RouteDefinition> = new Map<string, RouteDefinition>();

  register(definition: RouteDefinition): Result<void, AppError> {
    if (this.byName.has(definition.name)) {
      return err(AppErrors.internal('route.duplicateName', `route already registered: ${definition.name}`));
    }
    if (this.byTemplate.has(definition.pathTemplate)) {
      return err(AppErrors.internal('route.duplicateTemplate', `path template already registered: ${definition.pathTemplate}`));
    }
    const templateError: string | null = validatePathTemplate(definition.pathTemplate, definition);
    if (templateError !== null) {
      return err(AppErrors.parameter('invalid', 'pathTemplate', templateError));
    }
    this.byName.set(definition.name, definition);
    this.byTemplate.set(definition.pathTemplate, definition);
    return ok(undefined);
  }

  registerAll(definitions: RouteDefinition[]): Result<void, AppError> {
    for (let i: number = 0; i < definitions.length; i++) {
      const result: Result<void, AppError> = this.register(definitions[i]);
      if (result.isErr()) {
        return result;
      }
    }
    return ok(undefined);
  }

  /** 按 route name 查找；未注册返回 null（调用方自行决定是错误还是放行）。 */
  find(name: RouteName): RouteDefinition | null {
    const hit: RouteDefinition | undefined = this.byName.get(name);
    return hit === undefined ? null : hit;
  }

  /** 按 path 反查路由定义：段数一致且字面量段全部相等即命中。 */
  findByPath(path: string): RouteDefinition | null {
    const segments: string[] = path.length === 0 ? [] : path.split('/');
    const defs: RouteDefinition[] = this.allDefinitions();
    for (let i: number = 0; i < defs.length; i++) {
      if (templateMatches(defs[i].pathTemplate, segments)) {
        return defs[i];
      }
    }
    return null;
  }

  pathTemplateFor(name: RouteName): string | null {
    const def: RouteDefinition | null = this.find(name);
    return def === null ? null : def.pathTemplate;
  }

  allDefinitions(): RouteDefinition[] {
    const out: RouteDefinition[] = [];
    for (const def of this.byName.values()) {
      out.push(def);
    }
    return out;
  }
}

/**
 * 预置全部内置路由的注册表。
 * 内置表与代码同仓库演进，理论不可能注册失败；若失败说明 schema 与定义表不一致，
 * 属于构建期不变量破坏，让启动直接失败比静默吞掉更安全。
 */
export function defaultRegistry(): RouteRegistry {
  const registry: RouteRegistry = new RouteRegistry();
  const result: Result<void, AppError> = registry.registerAll(ROUTE_DEFINITIONS);
  if (result.ok === false) {
    throw new Error(`builtin route definitions invalid: ${result.error.message}`);
  }
  return registry;
}

/** path 模板合法性：非空、无空段，'{param}' 占位必须在 schema 中声明且唯一。 */
function validatePathTemplate(template: string, definition: RouteDefinition): string | null {
  if (template.length === 0) {
    return 'path template must not be empty';
  }
  const segments: string[] = template.split('/');
  const seen: Map<string, boolean> = new Map<string, boolean>();
  for (let i: number = 0; i < segments.length; i++) {
    const segment: string = segments[i];
    if (segment.length === 0) {
      return `empty path segment in template: ${template}`;
    }
    if (segment.startsWith('{') && segment.endsWith('}')) {
      const paramName: string = segment.substring(1, segment.length - 1);
      if (paramName.length === 0) {
        return `empty placeholder in template: ${template}`;
      }
      if (seen.has(paramName)) {
        return `duplicate placeholder in template: ${paramName}`;
      }
      seen.set(paramName, true);
      if (!hasSpec(definition, paramName)) {
        return `placeholder ${paramName} missing in param schema`;
      }
    }
  }
  return null;
}

function hasSpec(definition: RouteDefinition, paramName: string): boolean {
  for (let i: number = 0; i < definition.params.length; i++) {
    if (definition.params[i].name === paramName) {
      return true;
    }
  }
  return false;
}

/** 模板与 path 段匹配：段数一致；字面量段相等；'{x}' 占位段接受任意非空值。 */
export function templateMatches(template: string, pathSegments: string[]): boolean {
  const templateSegments: string[] = template.split('/');
  if (templateSegments.length !== pathSegments.length) {
    return false;
  }
  for (let i: number = 0; i < templateSegments.length; i++) {
    const t: string = templateSegments[i];
    if (t.startsWith('{') && t.endsWith('}')) {
      if (pathSegments[i].length === 0) {
        return false;
      }
      continue;
    }
    if (t !== pathSegments[i]) {
      return false;
    }
  }
  return true;
}
