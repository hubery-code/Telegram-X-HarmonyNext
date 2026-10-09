/**
 * feature/chat — 整包取数失败分类（STICKER-FETCH-102）。
 *
 * 只守纯函数那半边：同一个数字码 406 有两个来源（服务端的 `STICKERSET_INVALID` 与
 * TDLib 在 `NetQueryDispatcher.cpp:102` 本地重写的 `420 FROZEN_METHOD_INVALID`），
 * 前者是「这一包解析不出来」，后者是「这个 api_id/会话不被允许调这个方法」——
 * 分不开就会把配置问题当服务端问题定案（本仓第十五轮正是这么错的）。
 * 取数链路本身（先短名后 id、`ignore_cache=false`）由 StickerBoardFetch.test.ets 守。
 *
 * DEEPLINK-STICKER-102 另守装包地址那半边：`changeStickerSet` 在 TDLib 1.8.67 里只有
 * `set_id: int64` 一种入参，而深链 `t.me/addstickers/<名>` 那一进的弹层键是**短名** ——
 * 装/卸必须换成整包回包里带回来的数字 id，两条都拿不到就不发请求。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, AppErrors } from '@tgx/core-common';
import {
  classifyStickerSetFetchFailure,
  stickerSetFetchFailureLogKey,
  isNumericStickerSetId,
  stickerSetChangeTargetId,
  StickerSetFetchFailure
} from '../main/ets/model/StickerSetFetch';

/** 与真实链路一致：错误原文只进 `cause`，形状是 `"<数字码>:<TDLib 原文>"`。 */
function tdError(code: number, rawMessage: string): AppError {
  return AppErrors.fromTdlibError(code, rawMessage);
}

export default function stickerSetFetchTest(): void {
  describe('StickerSetFetchTest', () => {

    it('frozenMethodRewriteIsItsOwnClass', 0, () => {
      // 406 + FROZEN_METHOD_INVALID：TDLib 本地造的方法冻结，不是服务端否决这一包。
      const error: AppError = tdError(406, 'FROZEN_METHOD_INVALID');
      expect(classifyStickerSetFetchFailure(error)).assertEqual('frozenMethod' as StickerSetFetchFailure);
      expect(stickerSetFetchFailureLogKey(error)).assertEqual('code=406 reason=frozenMethod');
    });

    it('stickerSetInvalidIsServerSide', 0, () => {
      const error: AppError = tdError(406, 'STICKERSET_INVALID');
      expect(classifyStickerSetFetchFailure(error)).assertEqual('stickerSetInvalid' as StickerSetFetchFailure);
      expect(stickerSetFetchFailureLogKey(error)).assertEqual('code=406 reason=stickerSetInvalid');
    });

    it('neverSeenSetIdIsLocalNotFound', 0, () => {
      // `StickersManager.cpp:4970` 对从未见过的 set_id 合成 400，不走网络。
      const error: AppError = tdError(400, 'Sticker set not found');
      expect(classifyStickerSetFetchFailure(error)).assertEqual('setNotFound' as StickerSetFetchFailure);
      expect(stickerSetFetchFailureLogKey(error)).assertEqual('code=400 reason=setNotFound');
    });

    it('logKeyNeverCarriesRawText', 0, () => {
      const error: AppError = tdError(420, 'FROZEN_METHOD_INVALID some server detail');
      const key: string = stickerSetFetchFailureLogKey(error);
      expect(key).assertEqual('code=420 reason=frozenMethod');
      expect(key.indexOf('server detail') === -1).assertTrue();
    });

    it('nonTdlibFailureHasNoCode', 0, () => {
      // 网关/平台侧的失败没有 TDLib 数字码；分类落 other，code 记 0 而不是猜一个。
      const error: AppError = AppErrors.network('timeout', 'Gateway timeout', true);
      expect(classifyStickerSetFetchFailure(error)).assertEqual('other' as StickerSetFetchFailure);
      expect(stickerSetFetchFailureLogKey(error)).assertEqual('code=0 reason=other');
    });

    it('missingFallsBackToMessageWithoutThrowing', 0, () => {
      // 兜底路径：没有 cause 时读 message，分类仍要给出（不能因为字段缺失崩在日志里）。
      const error: AppError = AppErrors.tdlib('unknown', 'STICKERSET_INVALID', false);
      expect(classifyStickerSetFetchFailure(error)).assertEqual('stickerSetInvalid' as StickerSetFetchFailure);
    });

    it('numericEntry_addressesItself', 0, () => {
      // 气泡/板卡/热门行入口自带数字 id：装包就发这一格，不该被回包里的别的 id 顶掉。
      expect(stickerSetChangeTargetId('21', '99')).assertEqual('21');
      expect(stickerSetChangeTargetId('21', '')).assertEqual('21');
    });

    it('shortNameEntry_addressesTheIdFromTheResponse', 0, () => {
      // DEEPLINK-STICKER-102：`t.me/addstickers/<名>` 的键是短名，而 TDLib 的
      // `changeStickerSet` 只有 `set_id: int64` —— 只能发整包回包里带回来的数字 id。
      expect(stickerSetChangeTargetId('pandamonium_by_tgx', '21')).assertEqual('21');
    });

    it('shortNameEntryWithoutResolvedIdSendsNothing', 0, () => {
      // 短名 + 还没拿到 id：返回空串让调用方**不发请求**。把名字塞进 int64 的位置上
      // 只会换来一个注定的 400，那比「这次动作没发生」更难查。
      expect(stickerSetChangeTargetId('pandamonium_by_tgx', '')).assertEqual('');
      expect(stickerSetChangeTargetId('pandamonium_by_tgx', 'pandamonium_by_tgx')).assertEqual('');
    });

    it('numericIdPredicateRejectsNames', 0, () => {
      expect(isNumericStickerSetId('21')).assertTrue();
      expect(isNumericStickerSetId('-21')).assertTrue();
      expect(isNumericStickerSetId('pandamonium_by_tgx')).assertFalse();
      expect(isNumericStickerSetId('21x')).assertFalse();
      expect(isNumericStickerSetId('')).assertFalse();
    });
  });
}
