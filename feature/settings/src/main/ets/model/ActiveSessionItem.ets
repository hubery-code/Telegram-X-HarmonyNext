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
