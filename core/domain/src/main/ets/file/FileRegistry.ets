/**
 * core/domain — 文件状态注册表（FILE-101）。
 *
 * 管理单账号作用域下的文件实体与下载状态：
 * - 单账号事实源：内存维护 Map<number, File>；
 * - 事件监听：订阅 Gateway 的 update 事件，处理 UpdateFile（type === 'updateFile'），
 *   就地更新已缓存 File 对象的各项属性；
 * - 监听器机制：支持按 fileId 订阅状态变更，返回符合 @tgx/platform-ports 契约的标准 Subscription；
 * - 解析辅助：提供 getFile, putFile, isDownloaded, getLocalPath, getDownloadProgress 等；
 * - 下载/取消：调用 TDLib downloadFile 与 cancelDownloadFile。
 */

import {
  File,
  LocalFile,
  RemoteFile,
  DownloadFile,
  CancelDownloadFile,
  UpdateFile,
  encodeDownloadFile,
  encodeCancelDownloadFile,
  decodeFile,
  decodeTdUpdate,
  TdJsonRaw,
  TdUpdate
} from '@tgx/core-td-api-generated';
import { AccountScope } from '@tgx/core-account';
import { TdPendingRequest, TdRoutedEvent, TdUpdateFilter, TdUpdateSubscription, TdWireObject } from '@tgx/td-gateway';
import { Result, AppError } from '@tgx/core-common';
import { Subscription } from '@tgx/platform-ports';
export { Subscription };

class FileSubscription implements Subscription {
  private active: boolean = true;
  private readonly onUnsubscribe: () => void;

  constructor(onUnsubscribe: () => void) {
    this.onUnsubscribe = onUnsubscribe;
  }

  get isActive(): boolean {
    return this.active;
  }

  unsubscribe(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.onUnsubscribe();
  }
}

export class FileRegistry {
  private readonly scope: AccountScope;
  private readonly files: Map<number, File> = new Map();
  private readonly listenersByFileId: Map<number, ((file: File) => void)[]> = new Map();
  private subscription: TdUpdateSubscription | null = null;

  constructor(scope: AccountScope) {
    this.scope = scope;
    this.start();
  }

  start(): void {
    if (this.subscription !== null) {
      return;
    }
    const filter: TdUpdateFilter = {
      clientId: this.scope.clientId,
      types: ['updateFile']
    };
    this.subscription = this.scope.gatewayInstance.subscribeUpdates(
      filter,
      (event: TdRoutedEvent): void => {
        const update: TdUpdate | null = decodeTdUpdate(event.payload as TdJsonRaw);
        if (update === null) {
          return;
        }
        if (update.type === 'updateFile') {
          const fileUpdate: UpdateFile = update as UpdateFile;
          if (fileUpdate.file !== null) {
            this.handleFileUpdate(fileUpdate.file);
          }
        }
      }
    );
  }

  stop(): void {
    if (this.subscription !== null) {
      this.subscription.unsubscribe();
      this.subscription = null;
    }
    this.listenersByFileId.clear();
  }

  clear(): void {
    this.files.clear();
    this.listenersByFileId.clear();
  }

  getFile(fileId: number): File | null {
    const file: File | undefined = this.files.get(fileId);
    return file !== undefined ? file : null;
  }

  putFile(file: File): void {
    const existing: File | undefined = this.files.get(file.id);
    let targetFile: File;
    if (existing !== undefined && existing !== file) {
      this.updateInPlace(existing, file);
      targetFile = existing;
    } else {
      this.files.set(file.id, file);
      targetFile = file;
    }
    this.notifyListeners(file.id, targetFile);
  }

  subscribeFile(fileId: number, listener: (file: File) => void): Subscription {
    let listeners: ((file: File) => void)[] | undefined = this.listenersByFileId.get(fileId);
    if (listeners === undefined) {
      listeners = [];
      this.listenersByFileId.set(fileId, listeners);
    }
    listeners.push(listener);

    return new FileSubscription((): void => {
      const list: ((file: File) => void)[] | undefined = this.listenersByFileId.get(fileId);
      if (list !== undefined) {
        const index: number = list.indexOf(listener);
        if (index >= 0) {
          list.splice(index, 1);
        }
        if (list.length === 0) {
          this.listenersByFileId.delete(fileId);
        }
      }
    });
  }

  isDownloaded(fileId: number): boolean {
    const file: File | undefined = this.files.get(fileId);
    if (file === undefined || file.local === null) {
      return false;
    }
    return file.local.is_downloading_completed;
  }

  getLocalPath(fileId: number): string | null {
    const file: File | undefined = this.files.get(fileId);
    if (file === undefined || file.local === null) {
      return null;
    }
    const path: string = file.local.path;
    return path.length > 0 ? path : null;
  }

  getDownloadProgress(fileId: number): number {
    const file: File | undefined = this.files.get(fileId);
    if (file === undefined || file.local === null) {
      return 0.0;
    }
    if (file.local.is_downloading_completed) {
      return 1.0;
    }
    const totalSize: number = file.size > 0 ? file.size : file.expected_size;
    if (totalSize <= 0) {
      return 0.0;
    }
    const downloaded: number = file.local.downloaded_size;
    if (downloaded <= 0) {
      return 0.0;
    }
    const progress: number = downloaded / totalSize;
    if (progress > 1.0) {
      return 1.0;
    }
    return progress;
  }

  isUploading(fileId: number): boolean {
    const file: File | undefined = this.files.get(fileId);
    if (file === undefined || file.remote === null) {
      return false;
    }
    return file.remote.is_uploading_active;
  }

  isUploaded(fileId: number): boolean {
    const file: File | undefined = this.files.get(fileId);
    if (file === undefined || file.remote === null) {
      return false;
    }
    return file.remote.is_uploading_completed;
  }

  getUploadProgress(fileId: number): number {
    const file: File | undefined = this.files.get(fileId);
    if (file === undefined || file.remote === null) {
      return 0.0;
    }
    if (file.remote.is_uploading_completed) {
      return 1.0;
    }
    const totalSize: number = file.size > 0 ? file.size : file.expected_size;
    if (totalSize <= 0) {
      return 0.0;
    }
    const uploaded: number = file.remote.uploaded_size;
    if (uploaded <= 0) {
      return 0.0;
    }
    const progress: number = uploaded / totalSize;
    if (progress > 1.0) {
      return 1.0;
    }
    return progress;
  }

  downloadFile(
    fileId: number,
    priority: number = 1,
    offset: number = 0,
    limit: number = 0,
    synchronous: boolean = false
  ): Result<TdPendingRequest, AppError> {
    const req: DownloadFile = new DownloadFile();
    req.file_id = fileId;
    req.priority = priority;
    req.offset = offset;
    req.limit = limit;
    req.synchronous = synchronous;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('downloadFile', encodeDownloadFile(req) as TdWireObject);
    if (result.ok) {
      const self: FileRegistry = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (res.ok) {
          const file: File | null = decodeFile(res.value as TdJsonRaw);
          if (file !== null) {
            self.putFile(file);
          }
        }
      }).catch((): void => {
      });
    }
    return result;
  }

  cancelDownloadFile(fileId: number, onlyIfPending: boolean = false): Result<TdPendingRequest, AppError> {
    const req: CancelDownloadFile = new CancelDownloadFile();
    req.file_id = fileId;
    req.only_if_pending = onlyIfPending;

    return this.scope.request('cancelDownloadFile', encodeCancelDownloadFile(req) as TdWireObject);
  }

  private handleFileUpdate(newFile: File): void {
    const existing: File | undefined = this.files.get(newFile.id);
    let targetFile: File;
    if (existing !== undefined) {
      this.updateInPlace(existing, newFile);
      targetFile = existing;
    } else {
      this.files.set(newFile.id, newFile);
      targetFile = newFile;
    }
    this.notifyListeners(newFile.id, targetFile);
  }

  private updateInPlace(target: File, source: File): void {
    target.size = source.size;
    target.expected_size = source.expected_size;
    if (source.local !== null) {
      if (target.local === null) {
        target.local = new LocalFile();
      }
      target.local.path = source.local.path;
      target.local.can_be_downloaded = source.local.can_be_downloaded;
      target.local.can_be_deleted = source.local.can_be_deleted;
      target.local.is_downloading_active = source.local.is_downloading_active;
      target.local.is_downloading_completed = source.local.is_downloading_completed;
      target.local.download_offset = source.local.download_offset;
      target.local.downloaded_prefix_size = source.local.downloaded_prefix_size;
      target.local.downloaded_size = source.local.downloaded_size;
    } else {
      target.local = null;
    }
    if (source.remote !== null) {
      if (target.remote === null) {
        target.remote = new RemoteFile();
      }
      target.remote.id = source.remote.id;
      target.remote.unique_id = source.remote.unique_id;
      target.remote.is_uploading_active = source.remote.is_uploading_active;
      target.remote.is_uploading_completed = source.remote.is_uploading_completed;
      target.remote.uploaded_size = source.remote.uploaded_size;
    } else {
      target.remote = null;
    }
  }

  private notifyListeners(fileId: number, file: File): void {
    const listeners: ((file: File) => void)[] | undefined = this.listenersByFileId.get(fileId);
    if (listeners !== undefined && listeners.length > 0) {
      const copy: ((file: File) => void)[] = [...listeners];
      for (let i = 0; i < copy.length; i++) {
        copy[i](file);
      }
    }
  }
}
