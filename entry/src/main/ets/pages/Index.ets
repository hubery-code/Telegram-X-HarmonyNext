import native from 'libtdcore_napi.so';

interface TdCoreNative {
  getVersion(): string;
  execute(requestUtf8: string): string | null;
  createClient(): number;
  send(clientId: number, requestUtf8: string): void;
}

const tdcore: TdCoreNative = native as TdCoreNative;

@Entry
@Component
struct Index {
  @State versionResult: string = '(未运行)';
  @State executeResult: string = '(未运行)';
  @State clientResult: string = '(未运行)';
  @State errorMessage: string = '';

  private runTdlibCheck(): void {
    try {
      this.versionResult = tdcore.getVersion();
      const response = tdcore.execute('{"@type":"getTextEntities","text":"hello @telegram"}');
      this.executeResult = response !== null
        ? (response.length > 200 ? response.substring(0, 200) + '…' : response)
        : '(null)';
      const clientId = tdcore.createClient();
      tdcore.send(clientId, '{"@type":"getOption","name":"version"}');
      this.clientResult = `clientId=${clientId} (异步响应需 BRG-003 receive)`;
      this.errorMessage = '';
    } catch (e) {
      this.errorMessage = `错误: ${String(e)}`;
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('Telegram X HarmonyOS')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
      Button('TDLib 验证')
        .onClick(() => {
          this.runTdlibCheck();
        })
      Text(`TDLib 版本: ${this.versionResult}`)
        .fontSize(14)
      Text(`execute 结果: ${this.executeResult}`)
        .fontSize(12)
      Text(`createClient/send: ${this.clientResult}`)
        .fontSize(12)
      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor(Color.Red)
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
  }

  aboutToAppear(): void {
    this.runTdlibCheck();
  }
}
