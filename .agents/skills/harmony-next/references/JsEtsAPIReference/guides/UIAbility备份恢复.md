# UIAbility备份恢复

本文根据华为开发者官网 `ability-recover-guideline` 页面整理为离线版入口。
来源：<https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ability-recover-guideline>
更新时间：2026-05-12 09:31:20

## 场景介绍

当应用后台运行时，可能由于系统资源管控等原因导致应用关闭、进程退出，应用直接退出可能会导致用户数据丢失。如果应用在UIAbilityContext中启用了UIAbility备份恢复功能，并对临时数据进行保存，则可以在应用退出后的下一次启动时恢复先前的状态和数据（包括应用的页面栈以及onSaveState接口中保存的数据），从而保证用户体验的连贯性。

应用正常关闭时，不会触发UIAbility备份流程。应用正常启动（例如通过startAbility接口启动或点击图标启动）时，不触发UIAbility恢复流程。

## 运行机制

- UIAbility数据备份：当应用后台运行时，如果因系统资源管控、进程被kill、异常崩溃等非正常原因退出时，系统自动调用onSaveState进行备份。
- UIAbility数据恢复：恢复的Want数据可以在应用的onCreate生命周期中获取，页面栈数据在应用的onWindowStageCreate生命周期中恢复。

## 约束限制

- UIAbility备份恢复支持多实例，备份数据保存7天，以文件的形式存储在应用的沙箱路径中。
- 备份数据存储在Want中的parameter字段中，由于序列化大小限制，支持的最大数据量为200KB。
- 重启设备不支持还原备份。
- 备份恢复机制依赖任务保留机制，如果应用设置removeMissionAfterTerminate为true，或者设备不支持任务保留（比如PC/2in1设备），则备份恢复机制不生效。
- UIExtensionAbility不支持备份恢复。

## 接口说明

UIAbility备份恢复接口由UIAbilityContext模块提供，开发者可以通过在UIAbility中通过this.context直接调用，详见开发步骤。

接口名称

说明

setRestoreEnabled(enabled: boolean): void

设置UIAbility是否启用备份恢复。

setRestoreEnabled接口需要在应用初始化阶段调用（onForeground前），比如UIAbility的onCreate调用。

## 开发步骤

开发者需要在应用模块初始化时启用UIAbility的备份恢复功能。

```text
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
// ···

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'EntryAbility', '[Demo] EntryAbility onCreate');
    this.context.setRestoreEnabled(true);
    // ···
  }

// ···
}
```

开发者主动保存数据，在UIAbility启动时恢复。

```text
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
// ···

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'EntryAbility', '[Demo] EntryAbility onCreate');
    this.context.setRestoreEnabled(true);
    if (want && want.parameters) {
      let recoveryMyData = want.parameters['myData'];
    }
  }

  onSaveState(reason: AbilityConstant.StateType, wantParam: Record<string, Object>): AbilityConstant.OnSaveResult {
    // 保存应用数据。
    hilog.info(DOMAIN, 'EntryAbility', '[Demo] EntryAbility onSaveState');
    wantParam['myData'] = 'my1234567';
    return AbilityConstant.OnSaveResult.ALL_AGREE;
  }

// ···
}
```
