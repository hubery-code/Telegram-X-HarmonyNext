import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LightTheme } from '@tgx/core-design-system';

const T = LightTheme;
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

      Button('Log in with QR code instead')
        .width('90%')
        .height(44)
        .fontColor(T.colors.accent)
        .backgroundColor(Color.Transparent)
        .margin({ top: T.spacing.sm, bottom: T.spacing.huge })
        .enabled(!this.isSubmitting)
        .onClick(() => {
          this.onUseQrCode();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(T.colors.background)
  }
}
