import { TdJsonRaw } from '../main/ets/Index';

/**
 * Canonical JSON form used by fixture round-trip tests: object keys are
 * sorted recursively, so comparison is independent of key order.
 */
export function canonicalJson(value: TdJsonRaw): string {
  if (value === null || value === undefined) {
    return 'null';
  }
  if (typeof value === 'boolean' || typeof value === 'number') {
    return JSON.stringify(value);
  }
  if (typeof value === 'string') {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    const parts: string[] = [];
    for (const item of value) {
      parts.push(canonicalJson(item));
    }
    return '[' + parts.join(',') + ']';
  }
  const record: Record<string, TdJsonRaw> = value as Record<string, TdJsonRaw>;
  const keys: string[] = Object.keys(record).sort();
  const fields: string[] = [];
  for (const key of keys) {
    fields.push(JSON.stringify(key) + ':' + canonicalJson(record[key]));
  }
  return '{' + fields.join(',') + '}';
}
