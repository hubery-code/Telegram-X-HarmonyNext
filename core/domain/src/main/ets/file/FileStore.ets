/**
 * core/domain — 文件下载队列调度器 FileStore（FILE-102）。
 *
 * 包装底层 FileRegistry，统一管理文件下载调度：
 * - 并发控制：可配置 maxConcurrentDownloads（默认 3）。活跃下载数达到上限时，新请求入队排队；
 * - 优先级调度：支持 priority（默认 1，数值越大优先级越高）。入队时按优先级降序、同优先级按加入时间先进先出（FIFO）排序；
 * - 状态跟踪：提供 FileDownloadTask / TaskStatus ('queued' | 'downloading' | 'completed' | 'failed' | 'paused' | 'canceled')；
 * - 生命周期与事件响应：
 *   - enqueue(fileId: number, priority?: number): void
 *   - cancel(fileId: number): void
 *   - pause(fileId: number): void
 *   - resume(fileId: number): void
 *   - pauseAll(): void
 *   - resumeAll(): void
 *   - getTaskStatus(fileId: number): FileDownloadStatus
 *   - getActiveCount(): number
 *   - getQueuedCount(): number
 * - 自动推进：监听 FileRegistry.subscribeFile(fileId, ...)。当文件 is_downloading_completed 或下载出错/被取消时，
 *   清理当前活跃槽位，自动抽取队列中的下一个高优先级任务并调用 fileRegistry.downloadFile(nextFileId, priority)；
 * - 网络感知与暂停：支持 setNetworkAvailable(isAvailable: boolean)。断网时自动挂起未完成任务（标记为 paused），
 *   恢复网络时自动继续排队并按并发限制恢复下载。
 */

import { File } from '@tgx/core-td-api-generated';
import { Result, AppError } from '@tgx/core-common';
import { Subscription } from '@tgx/platform-ports';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { FileRegistry } from './FileRegistry';

export type TaskStatus = 'queued' | 'downloading' | 'completed' | 'failed' | 'paused' | 'canceled';

export type FileDownloadStatus = TaskStatus;

export class FileDownloadTask {
  readonly fileId: number;
  priority: number;
  status: TaskStatus;
  sequence: number;
  pausedByNetwork: boolean;

  constructor(fileId: number, priority: number = 1, status: TaskStatus = 'queued', sequence: number = 0) {
    this.fileId = fileId;
    this.priority = priority;
    this.status = status;
    this.sequence = sequence;
    this.pausedByNetwork = false;
  }
}

export class FileStore {
  private readonly fileRegistry: FileRegistry;
  private maxConcurrentDownloads: number;
  private readonly tasks: Map<number, FileDownloadTask> = new Map();
  private readonly activeTasks: Set<number> = new Set();
  private readonly fileSubscriptions: Map<number, Subscription> = new Map();
  private queue: FileDownloadTask[] = [];
  private nextSequence: number = 0;
  private isNetworkAvailable: boolean = true;
  private isPausedAll: boolean = false;

  constructor(fileRegistry: FileRegistry, maxConcurrentDownloads: number = 3) {
    this.fileRegistry = fileRegistry;
    this.maxConcurrentDownloads = maxConcurrentDownloads > 0 ? maxConcurrentDownloads : 3;
  }

  getMaxConcurrentDownloads(): number {
    return this.maxConcurrentDownloads;
  }

  setMaxConcurrentDownloads(limit: number): void {
    if (limit <= 0) {
      return;
    }
    this.maxConcurrentDownloads = limit;
    this.schedule();
  }

  isNetworkConnected(): boolean {
    return this.isNetworkAvailable;
  }

  getActiveCount(): number {
    return this.activeTasks.size;
  }

  getQueuedCount(): number {
    return this.queue.length;
  }

  getTask(fileId: number): FileDownloadTask | null {
    const task: FileDownloadTask | undefined = this.tasks.get(fileId);
    return task !== undefined ? task : null;
  }

  getTaskStatus(fileId: number): FileDownloadStatus {
    const task: FileDownloadTask | undefined = this.tasks.get(fileId);
    if (task !== undefined) {
      return task.status;
    }
    if (this.fileRegistry.isDownloaded(fileId)) {
      return 'completed';
    }
    return 'canceled';
  }

  enqueue(fileId: number, priority: number = 1): void {
    if (this.fileRegistry.isDownloaded(fileId)) {
      let task: FileDownloadTask | undefined = this.tasks.get(fileId);
      if (task === undefined) {
        task = new FileDownloadTask(fileId, priority, 'completed', this.nextSequence);
        this.nextSequence += 1;
        this.tasks.set(fileId, task);
      } else {
        task.status = 'completed';
      }
      return;
    }

    const existing: FileDownloadTask | undefined = this.tasks.get(fileId);
    if (existing !== undefined) {
      if (existing.status === 'downloading') {
        existing.priority = priority;
        return;
      }
      if (existing.status === 'queued') {
        existing.priority = priority;
        this.sortQueue();
        return;
      }
      if (existing.status === 'completed') {
        return;
      }

      existing.priority = priority;
      existing.sequence = this.nextSequence;
      this.nextSequence += 1;
      existing.pausedByNetwork = false;

      if (!this.isNetworkAvailable || this.isPausedAll) {
        existing.status = 'paused';
        if (!this.isNetworkAvailable) {
          existing.pausedByNetwork = true;
        }
        return;
      }

      existing.status = 'queued';
      this.queue.push(existing);
      this.sortQueue();
      this.schedule();
      return;
    }

    const newTask: FileDownloadTask = new FileDownloadTask(
      fileId,
      priority,
      'queued',
      this.nextSequence
    );
    this.nextSequence += 1;
    this.tasks.set(fileId, newTask);

    if (!this.isNetworkAvailable || this.isPausedAll) {
      newTask.status = 'paused';
      if (!this.isNetworkAvailable) {
        newTask.pausedByNetwork = true;
      }
      return;
    }

    this.queue.push(newTask);
    this.sortQueue();
    this.schedule();
  }

  cancel(fileId: number): void {
    const task: FileDownloadTask | undefined = this.tasks.get(fileId);
    if (task === undefined) {
      this.fileRegistry.cancelDownloadFile(fileId);
      return;
    }
    if (task.status === 'completed') {
      return;
    }

    const wasDownloading: boolean = (task.status === 'downloading');
    const wasQueued: boolean = (task.status === 'queued');

    task.status = 'canceled';
    task.pausedByNetwork = false;

    if (wasDownloading) {
      this.cleanupActiveSlot(fileId);
      this.fileRegistry.cancelDownloadFile(fileId);
      this.schedule();
    } else if (wasQueued) {
      const index: number = this.queue.findIndex((t: FileDownloadTask): boolean => t.fileId === fileId);
      if (index >= 0) {
        this.queue.splice(index, 1);
      }
    }
  }

  pause(fileId: number): void {
    const task: FileDownloadTask | undefined = this.tasks.get(fileId);
    if (task === undefined) {
      return;
    }
    if (task.status === 'downloading') {
      task.status = 'paused';
      task.pausedByNetwork = false;
      this.cleanupActiveSlot(fileId);
      this.fileRegistry.cancelDownloadFile(fileId);
      this.schedule();
    } else if (task.status === 'queued') {
      task.status = 'paused';
      task.pausedByNetwork = false;
      const index: number = this.queue.findIndex((t: FileDownloadTask): boolean => t.fileId === fileId);
      if (index >= 0) {
        this.queue.splice(index, 1);
      }
    }
  }

  resume(fileId: number): void {
    const task: FileDownloadTask | undefined = this.tasks.get(fileId);
    if (task === undefined) {
      return;
    }
    if (task.status === 'paused') {
      task.pausedByNetwork = false;
      if (!this.isNetworkAvailable || this.isPausedAll) {
        return;
      }
      task.status = 'queued';
      this.queue.push(task);
      this.sortQueue();
      this.schedule();
    }
  }

  pauseAll(): void {
    this.isPausedAll = true;

    const activeList: number[] = [];
    this.activeTasks.forEach((id: number): void => {
      activeList.push(id);
    });

    for (let i = 0; i < activeList.length; i++) {
      const activeFileId: number = activeList[i];
      const task: FileDownloadTask | undefined = this.tasks.get(activeFileId);
      if (task !== undefined) {
        task.status = 'paused';
      }
      this.cleanupActiveSlot(activeFileId);
      this.fileRegistry.cancelDownloadFile(activeFileId);
    }

    for (let i = 0; i < this.queue.length; i++) {
      this.queue[i].status = 'paused';
    }
    this.queue = [];
  }

  resumeAll(): void {
    this.isPausedAll = false;
    if (!this.isNetworkAvailable) {
      return;
    }

    const taskList: FileDownloadTask[] = [];
    this.tasks.forEach((task: FileDownloadTask): void => {
      taskList.push(task);
    });

    for (let i = 0; i < taskList.length; i++) {
      const task: FileDownloadTask = taskList[i];
      if (task.status === 'paused') {
        task.status = 'queued';
        task.pausedByNetwork = false;
        this.queue.push(task);
      }
    }
    this.sortQueue();
    this.schedule();
  }

  setNetworkAvailable(isAvailable: boolean): void {
    if (this.isNetworkAvailable === isAvailable) {
      return;
    }
    this.isNetworkAvailable = isAvailable;

    if (!isAvailable) {
      const activeList: number[] = [];
      this.activeTasks.forEach((id: number): void => {
        activeList.push(id);
      });

      for (let i = 0; i < activeList.length; i++) {
        const activeFileId: number = activeList[i];
        const task: FileDownloadTask | undefined = this.tasks.get(activeFileId);
        if (task !== undefined) {
          task.status = 'paused';
          task.pausedByNetwork = true;
        }
        this.cleanupActiveSlot(activeFileId);
        this.fileRegistry.cancelDownloadFile(activeFileId);
      }

      for (let i = 0; i < this.queue.length; i++) {
        this.queue[i].status = 'paused';
        this.queue[i].pausedByNetwork = true;
      }
      this.queue = [];
    } else {
      if (this.isPausedAll) {
        return;
      }
      const taskList: FileDownloadTask[] = [];
      this.tasks.forEach((task: FileDownloadTask): void => {
        taskList.push(task);
      });

      for (let i = 0; i < taskList.length; i++) {
        const task: FileDownloadTask = taskList[i];
        if (task.status === 'paused' && task.pausedByNetwork) {
          task.status = 'queued';
          task.pausedByNetwork = false;
          this.queue.push(task);
        }
      }
      this.sortQueue();
      this.schedule();
    }
  }

  clear(): void {
    const activeList: number[] = [];
    this.activeTasks.forEach((id: number): void => {
      activeList.push(id);
    });

    for (let i = 0; i < activeList.length; i++) {
      const activeFileId: number = activeList[i];
      this.cleanupActiveSlot(activeFileId);
      this.fileRegistry.cancelDownloadFile(activeFileId);
    }
    this.tasks.clear();
    this.activeTasks.clear();
    this.queue = [];
  }

  private schedule(): void {
    if (!this.isNetworkAvailable || this.isPausedAll) {
      return;
    }

    while (this.activeTasks.size < this.maxConcurrentDownloads && this.queue.length > 0) {
      const task: FileDownloadTask | undefined = this.queue.shift();
      if (task === undefined) {
        break;
      }
      if (task.status !== 'queued') {
        continue;
      }

      task.status = 'downloading';
      this.activeTasks.add(task.fileId);

      const targetFileId: number = task.fileId;
      const sub: Subscription = this.fileRegistry.subscribeFile(targetFileId, (file: File): void => {
        this.handleFileUpdate(file);
      });
      this.fileSubscriptions.set(targetFileId, sub);

      const res: Result<TdPendingRequest, AppError> =
        this.fileRegistry.downloadFile(targetFileId, task.priority);
      if (res.ok) {
        const self: FileStore = this;
        res.value.promise.then((wireRes: Result<TdWireObject, AppError>): void => {
          if (wireRes.err) {
            self.handleDownloadFailed(targetFileId);
          }
        }).catch((): void => {
          self.handleDownloadFailed(targetFileId);
        });
      }
      if (res.err) {
        this.handleDownloadFailed(targetFileId);
      }
    }
  }

  private handleFileUpdate(file: File): void {
    const task: FileDownloadTask | undefined = this.tasks.get(file.id);
    if (task === undefined || task.status !== 'downloading') {
      return;
    }
    if (file.local !== null) {
      if (file.local.is_downloading_completed) {
        this.handleDownloadCompleted(file.id);
      } else if (file.local.can_be_downloaded === false) {
        this.handleDownloadFailed(file.id);
      }
    }
  }

  private handleDownloadCompleted(fileId: number): void {
    const task: FileDownloadTask | undefined = this.tasks.get(fileId);
    if (task === undefined || task.status !== 'downloading') {
      return;
    }
    task.status = 'completed';
    this.cleanupActiveSlot(fileId);
    this.schedule();
  }

  private handleDownloadFailed(fileId: number): void {
    const task: FileDownloadTask | undefined = this.tasks.get(fileId);
    if (task === undefined || task.status !== 'downloading') {
      return;
    }
    task.status = 'failed';
    this.cleanupActiveSlot(fileId);
    this.schedule();
  }

  private cleanupActiveSlot(fileId: number): void {
    this.activeTasks.delete(fileId);
    const sub: Subscription | undefined = this.fileSubscriptions.get(fileId);
    if (sub !== undefined) {
      sub.unsubscribe();
      this.fileSubscriptions.delete(fileId);
    }
  }

  private sortQueue(): void {
    this.queue.sort((a: FileDownloadTask, b: FileDownloadTask): number => {
      if (a.priority !== b.priority) {
        return b.priority - a.priority;
      }
      return a.sequence - b.sequence;
    });
  }
}
