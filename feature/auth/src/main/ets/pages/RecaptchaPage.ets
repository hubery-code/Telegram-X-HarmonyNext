import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LightTheme, Theme } from '@tgx/core-design-system';
import { Lang, SupportedLanguage } from '@tgx/core-common';

const DOMAIN: number = 0x0000;
const TAG: string = 'RecaptchaPage';

class RecaptchaBridge {
  onTokenCallback: (token: string) => void = () => {};

  onToken(token: string): void {
    hilog.info(DOMAIN, TAG, 'recaptcha token received');
    this.onTokenCallback(token);
  }
}

@Component
export struct RecaptchaPage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;

  /**
   * I18N-HOTSWITCH-101：语言 tick。
   *
   * 装配层（entry/Index）订阅 Lang，把**有效语言**（'en' | 'zh'，不是偏好 'system'）镜像进
   * AppStorage('activeLanguage')；本页把它接成自己的可观察属性，于是 t() 读到的永远是
   * 当前语言，而**换语言会重渲染本页**——不再是「等下一次取数才有新字」（103/104 设备记录的头号
   * 盲区）。键缺席时 @StorageProp 用本行默认值自举，且挂载时自动取 AppStorage 现值，所以首帧
   * 就是对的，不需要再写一次手工同步。类型收在 string 而不是 SupportedLanguage：装饰器成员
   * 的字面量联合类型没有保证，而 t() 里反正要过一次收敛。
   */
  @StorageProp('activeLanguage') effectiveLanguage: string = 'en';
  @Prop recaptchaKeyId: string = '';
  @Prop isSubmitting: boolean = false;
  onToken: (token: string) => void = () => {};
  onUseQrCode: () => void = () => {};
  onBackToPhone: () => void = () => {};
  controller: webview.WebviewController = new webview.WebviewController();
  @State htmlContent: string = '';
  bridge: RecaptchaBridge = new RecaptchaBridge();

  aboutToAppear(): void {
    this.bridge.onTokenCallback = (token: string): void => {
      this.onToken(token);
    };
    this.htmlContent = '<!DOCTYPE html><html><head>'
      + '<meta charset="utf-8">'
      + '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">'
      + '<style>'
      + 'body{margin:0;padding:24px;background:white;font-family:sans-serif;'
      + 'display:flex;flex-direction:column;align-items:center;justify-content:center;'
      + 'min-height:100vh;box-sizing:border-box;}'
      + 'h2{font-size:18px;margin:0 0 16px 0;color:rgb(51,51,51);}'
      + '</style>'
      + '<script src="https://www.google.com/recaptcha/api.js" async defer></script>'
      + '<script>'
      + 'function onRecaptchaSuccess(token){'
      + 'if(window.recaptchaBridge){window.recaptchaBridge.onToken(token);}'
      + '}'
      + '</script>'
      + '</head><body>'
      + '<h2>Verify you are human</h2>'
      + '<div class="g-recaptcha" data-sitekey="' + this.recaptchaKeyId + '" '
      + 'data-callback="onRecaptchaSuccess"></div>'
      + '</body></html>';
  }

  private t(key: string, ...args: (string | number)[]): string {
    const langCode: SupportedLanguage = this.effectiveLanguage === 'zh' ? 'zh' : 'en';
    return Lang.getInstance().formatByKey(key, langCode, args);
  }

  build() {
    Column() {
      Web({ src: '', controller: this.controller })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onControllerAttached(() => {
          try {
            hilog.info(DOMAIN, TAG, 'Web onControllerAttached, registering proxy + loadData with baseUrl');
            this.controller.registerJavaScriptProxy(this.bridge, 'recaptchaBridge', ['onToken']);
            this.controller.loadData(
              this.htmlContent, 'text/html', 'UTF-8',
              'https://web.telegram.org/', 'https://web.telegram.org/'
            );
          } catch (error) {
            hilog.error(DOMAIN, TAG, 'Web init error: %{public}s', (error as BusinessError).message);
          }
        })
        .onPageBegin(() => {
          hilog.info(DOMAIN, TAG, 'Web onPageBegin');
        })
        .onPageEnd(() => {
          hilog.info(DOMAIN, TAG, 'Web onPageEnd — page loaded');
        })
        .onErrorReceive((error) => {
          hilog.error(DOMAIN, TAG, 'Web error: %{public}s', JSON.stringify(error));
        })
        .width('100%')
        .layoutWeight(1)

      Button(this.t('Log in with QR code instead'))
        .width('90%')
        .height(44)
        .fontColor(this.T.colors.accent)
        .backgroundColor(Color.Transparent)
        .margin({ top: this.T.spacing.sm, bottom: this.T.spacing.huge })
        .enabled(!this.isSubmitting)
        .onClick(() => {
          this.onUseQrCode();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }
}
