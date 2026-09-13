/**
 * feature/settings — 存储占用的人类可读格式化（SET-104 / FEAT-SET-004）。
 *
 * 纯函数，无 ArkUI / Kit / 生成类型依赖，便于单测。
 *
 * 单位用 1024 进制（与 TDLib 的字节口径一致），KB 及以上保留 1 位小数；
 * 字节级不带小数（"512 B" 而不是 "512.0 B"），与既有 `'0 B'` 默认值同风格。
 */

const KB: number = 1024;
const MB: number = 1024 * 1024;
const GB: number = 1024 * 1024 * 1024;

/** 字节 → "512 B" / "1.5 KB" / "12.3 MB" / "1.1 GB"。非法/负值统一按 0 处理。 */
export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '0 B';
  }
  if (bytes < KB) {
    return `${Math.round(bytes)} B`;
  }
  if (bytes < MB) {
    return `${(bytes / KB).toFixed(1)} KB`;
  }
  if (bytes < GB) {
    return `${(bytes / MB).toFixed(1)} MB`;
  }
  return `${(bytes / GB).toFixed(1)} GB`;
}

/**
 * 设置页"Cache size"一行的完整文案。
 * - 空缓存（bytes<=0）只出 "0 B"，不缀文件数——避免 "0 B · 0 files" 的冗余；
 * - 文件数 1 用单数 "file"。
 */
export function formatStorageLabel(bytes: number, fileCount: number): string {
  const size: string = formatBytes(bytes);
  const count: number = Number.isFinite(fileCount) && fileCount > 0 ? Math.floor(fileCount) : 0;
  if (count === 0) {
    return size;
  }
  return `${size} · ${count} ${count === 1 ? 'file' : 'files'}`;
}
