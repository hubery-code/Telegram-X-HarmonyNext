/**
 * entry — HarmonyOS 系统振动适配器（CONTACT-103）。
 *
 * 包装 @kit.SensorServiceKit 的 vibrator，实现 platform/ports 的
 * HapticFeedbackPort 契约，由装配层（pages/Index）注入 ContactsCoordinator。
 *
 * 效果选型（依据 .agents/skills/harmony-next 离线文档 @ohos.vibrator，本仓 SDK API 26）：
 * - 预置效果 'haptic.clock.timer'（EFFECT_CLOCK_TIMER，"调整计时器"短振），
 *   观感上最接近 Android 索引条划段用的 HapticFeedbackConstants.CLOCK_TICK；
 * - 场景 usage 走 'physicalFeedback'（VIBRATOR_USAGE_PHYSICAL_FEEDBACK），
 *   归属物理反馈开关管控，不与通知/闹钟抢振动通道。
 *
 * 降级约定：模拟器/无马达、未授权（ohos.permission.VIBRATE，entry
 * module.json5 已声明）、能力不支持（错误码 801）等一律静默返回、只记日志，
 * 绝不影响拖动换段主流程。
 *
 * 真实设备效果无法在本仓自动化验证，人工验证步骤（CONTACT-103 验收）：
 * 1. 真机安装后进入「联系人」页（列表需 ≥ 2 个字母分组，索引条才出现）；
 * 2. 按住右侧 A–Z 索引条上下拖动，每划过一个新分段应有一次短促轻震；
 *    停在同一段内小幅移动不应连续震动；抬起手后再按住拖动，重新从零判定；
 * 3. 点按单个字母（onClick 路径）不应震动，只有拖拽换段才震；
 * 4. 模拟器上同一操作不震动属预期（无马达，走本文件降级分支），可用
 *    hilog 过滤 TAG='HapticFeedback' 确认走了降级而不是崩溃。
 */

import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HapticFeedbackPort } from '@tgx/platform-ports';

const DOMAIN: number = 0x0000;
const TAG: string = 'HapticFeedback';

export class HarmonyHapticFeedbackAdapter implements HapticFeedbackPort {
  vibrateShort(): void {
    try {
      vibrator.startVibration({
        type: 'preset',
        effectId: 'haptic.clock.timer',
        count: 1
      }, {
        id: 0,
        usage: 'physicalFeedback'
      }, (error: BusinessError): void => {
        if (error) {
          // 异步回包失败（无器件/权限拒绝/能力不支持）：静默降级，只留痕。
          hilog.debug(DOMAIN, TAG, 'startVibration failed: %{public}s',
            `${error.code} ${error.message}`);
        }
      });
    } catch (e) {
      // 同步抛出（如参数校验 401）：同样降级，不影响拖动。
      const err: BusinessError = e as BusinessError;
      hilog.debug(DOMAIN, TAG, 'vibrateShort exception: %{public}s',
        `${err.code} ${err.message}`);
    }
  }
}
