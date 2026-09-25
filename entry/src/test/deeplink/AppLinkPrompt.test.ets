/**
 * entry/src/test/deeplink/AppLinkPrompt.test.ets — 弹窗视图模型与结果文案（DEEPLINK-102）。
 *
 * 这里钉的是「弹窗上会出现什么字」，以及 `AppLinkResult.reason` → 文案的映射：
 * 构卡函数是纯函数（翻译函数注入），所以不需要 Kit、不需要页面，也不会有渲染分支漏掉。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  InvitePromptData,
  PromptCard,
  ProxyPromptData,
  appLinkReasonKey,
  inviteActionLabelKey,
  inviteCountLabelKey,
  invitePromptCard,
  proxyChoiceEnables,
  proxyNeedsMtprotoHint,
  proxyPromptAddress,
  proxyPromptCard
} from '../../main/ets/deeplink/AppLinkPrompt';

/** 假装是 `Lang.getString`：键即文案，`{0}` 用实参替换。测试因此不认识 Kit。 */
function fakeTranslate(key: string, ...args: (string | number)[]): string {
  if (args.length === 0) {
    return key;
  }
  let out: string = key;
  for (let i = 0; i < args.length; i++) {
    out = out.replace(`{${i}}`, `${args[i]}`);
  }
  return out;
}

function inviteData(
  memberCount: number,
  isChannel: boolean,
  createsJoinRequest: boolean
): InvitePromptData {
  return {
    title: 'Qoder Test Group',
    description: 'a place for tests',
    memberCount: memberCount,
    isChannel: isChannel,
    createsJoinRequest: createsJoinRequest
  };
}

function proxyData(kind: string): ProxyPromptData {
  return { server: 'proxy.example.com', port: 8443, kind: kind };
}

export default function appLinkPromptTest() {
  describe('AppLinkPromptTest', () => {
    it('inviteActionLabel_followsJoinRequestFlag', 0, () => {
      // 申请制链接点下去只是发申请，按钮不能写「加入」。
      expect(inviteActionLabelKey(inviteData(3, false, false))).assertEqual('Join');
      expect(inviteActionLabelKey(inviteData(3, false, true))).assertEqual('Request to Join');
    });

    it('inviteCountLabel_distinguishesChannelAndZero', 0, () => {
      expect(inviteCountLabelKey(inviteData(12, false, false))).assertEqual('{0} members');
      expect(inviteCountLabelKey(inviteData(12, true, false))).assertEqual('{0} subscribers');
      // TDLib 对新建/隐私会话给 0；「0 位成员」是句假话，宁可空着。
      expect(inviteCountLabelKey(inviteData(0, true, false))).assertEqual('');
    });

    it('invitePromptCard_hasNoSecondaryAction', 0, () => {
      const card: PromptCard = invitePromptCard(inviteData(1234, true, false), fakeTranslate);
      expect(card.title).assertEqual('Qoder Test Group');
      expect(card.body).assertEqual('a place for tests');
      expect(card.footnote).assertEqual('1234 subscribers');
      expect(card.primaryLabel).assertEqual('Join');
      expect(card.secondaryLabel).assertEqual('');
      expect(card.cancelLabel).assertEqual('Cancel');
    });

    it('invitePromptCard_omitsFootnoteWhenCountUnknown', 0, () => {
      const card: PromptCard = invitePromptCard(inviteData(0, false, true), fakeTranslate);
      expect(card.footnote).assertEqual('');
      expect(card.primaryLabel).assertEqual('Request to Join');
    });

    it('proxyPromptCard_showsAddressAndBothActions', 0, () => {
      const card: PromptCard = proxyPromptCard(proxyData('socks5'), fakeTranslate);
      expect(card.title).assertEqual('Connect to This Proxy?');
      expect(card.body).assertEqual('Server: proxy.example.com\nPort: 8443');
      expect(card.primaryLabel).assertEqual('Enable');
      expect(card.secondaryLabel).assertEqual('Save for Later');
      // 密钥/用户名不出现在弹窗的任何一行。
      expect(card.footnote.indexOf('secret')).assertEqual(-1);
    });

    it('proxyPromptCard_addsSecretHintOnlyForMtproto', 0, () => {
      const socks: PromptCard = proxyPromptCard(proxyData('socks5'), fakeTranslate);
      const mtproto: PromptCard = proxyPromptCard(proxyData('mtproto'), fakeTranslate);
      expect(proxyNeedsMtprotoHint(proxyData('socks5'))).assertFalse();
      expect(proxyNeedsMtprotoHint(proxyData('mtproto'))).assertTrue();
      expect(mtproto.footnote.length > socks.footnote.length).assertTrue();
      expect(socks.footnote).assertEqual('This will add a proxy server to your configuration.');
    });

    it('proxyPromptAddress_isPlainServerColonPort', 0, () => {
      expect(proxyPromptAddress(proxyData('http'))).assertEqual('proxy.example.com:8443');
    });

    it('proxyChoiceEnables_mapsCancelToNull', 0, () => {
      // cancel → null 是「什么都别写」的唯一表示；save 是 false 而不是 null。
      expect(proxyChoiceEnables('enable') === true).assertTrue();
      expect(proxyChoiceEnables('save') === false).assertTrue();
      expect(proxyChoiceEnables('cancel') === null).assertTrue();
    });

    it('appLinkReasonKey_mapsEveryNotifiedReason', 0, () => {
      expect(appLinkReasonKey('join_request_sent')).assertEqual('Join request sent');
      expect(appLinkReasonKey('proxy_enabled')).assertEqual('Proxy enabled');
      expect(appLinkReasonKey('proxy_saved')).assertEqual('Proxy saved for later use');
      // 认不出的键不许把内部键名印到用户脸上。
      expect(appLinkReasonKey('internalLinkTypeGame')).assertEqual('Failed to open link');
      expect(appLinkReasonKey('')).assertEqual('Failed to open link');
    });
  });
}
