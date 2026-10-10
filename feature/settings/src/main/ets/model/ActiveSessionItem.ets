/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * FEAT-P2-008: 活跃设备与登录会话视图模型（对齐 Telegram X Sessions）。
 */
export interface ActiveSessionItem {
  readonly id: string;
  readonly isCurrent: boolean;
  readonly deviceModel: string;
  readonly platform: string;
  readonly applicationName: string;
  readonly applicationVersion: string;
  readonly ipAddress: string;
  readonly location: string;
  readonly lastActiveDate: number;
}

/**
 * 设备行副标题的词典键：1 条走单数键（`1 active sessions` 是坏英文），
 * 0 条只留标题不写数字（TDLib 取不到会话时「0 个活跃会话」是句假话）。
 * 0 档的 key 不含 `{0}`，调用点仍统一传 count —— `Lang.formatByKey` 忽略多余实参。
 */
export function devicesRowSubtitleKey(count: number): string {
  if (count <= 0) {
    return 'Active Sessions';
  }
  if (count === 1) {
    return '{0} active session';
  }
  return '{0} active sessions';
}
