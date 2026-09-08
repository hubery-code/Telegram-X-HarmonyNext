import { TdBridge, TdNativeEvent } from '../tdbridge/TdBridge';

function extractType(payloadUtf8: string): string {
  try {
    const parsed = JSON.parse(payloadUtf8) as Record<string, Object>;
    const typeValue: Object = parsed['@type'];
    if (typeValue !== undefined && typeValue !== null) {
      return typeValue.toString();
    }
  } catch (e) {
    return '(非法 JSON)';
  }
  return '(无 @type)';
}

@Entry
@Component
struct Index {
  @State versionResult: string = '(未运行)';
  @State executeResult: string = '(未运行)';
  @State clientResult: string = '(未运行)';
  @State errorMessage: string = '';

  // BRG-003/004 订阅验证状态
  @State subscriptionId: number = 0;
  @State smokeClientId: number = -1;
  @State smokeMatchText: string = '(等待 getOption 响应…)';
  @State lastEvents: string[] = [];
  @State metricsText: string = '';

  private runTdlibCheck(): void {
    try {
      this.versionResult = TdBridge.getVersion();
      const response = TdBridge.execute('{"@type":"getTextEntities","text":"hello @telegram"}');
      this.executeResult = response !== null
        ? (response.length > 200 ? response.substring(0, 200) + '…' : response)
        : '(null)';
      this.errorMessage = '';
    } catch (e) {
      this.errorMessage = `错误: ${String(e)}`;
    }
  }

  // 订阅 -> createClient -> send getOption(version, @extra.requestId=smoke-1)
  // 异步响应经 receive 线程 + TSFN 回到这里。
  private runSubscribeCheck(): void {
    try {
      if (this.subscriptionId !== 0) {
        TdBridge.unsubscribe(this.subscriptionId);
        this.subscriptionId = 0;
      }
      const subscriptionId = TdBridge.subscribe((event: TdNativeEvent): void => {
        this.onTdEvent(event);
      });
      this.subscriptionId = subscriptionId;
      const clientId = TdBridge.createClient();
      this.smokeClientId = clientId;
      this.smokeMatchText = '(等待 getOption 响应…)';
      TdBridge.send(clientId,
        '{"@type":"getOption","name":"version","@extra":{"requestId":"smoke-1"}}');
      this.refreshMetrics();
    } catch (e) {
      this.errorMessage = `订阅错误: ${String(e)}`;
    }
  }

  private onTdEvent(event: TdNativeEvent): void {
    const typeText: string = extractType(event.payloadUtf8);
    const summary: string =
      `#${event.sequence.toString()} client=${event.clientId} ${typeText}`;
    const nextEvents: string[] = [summary].concat(this.lastEvents).slice(0, 4);
    this.lastEvents = nextEvents;
    if (event.payloadUtf8.indexOf('"requestId":"smoke-1"') >= 0) {
      this.smokeMatchText =
        `收到请求响应: clientId=${event.clientId} sequence=${event.sequence.toString()} @type=${typeText}`;
    }
  }

  private refreshMetrics(): void {
    const m = TdBridge.getMetrics();
    this.metricsText =
      `queue=${m.queueSize} overflowWait=${m.overflowWaitCount} dropped=${m.droppedCount} ` +
      `forwarded=${m.eventsForwarded} subs=${m.subscriptions} running=${m.dispatcherRunning}`;
  }

  build() {
    Column({ space: 10 }) {
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
      Divider()
      Button('订阅验证 (BRG-003/004)')
        .onClick(() => {
          this.runSubscribeCheck();
        })
      Text(`订阅: id=${this.subscriptionId} client=${this.smokeClientId}`)
        .fontSize(12)
      Text(this.smokeMatchText)
        .fontSize(12)
        .fontColor(Color.Blue)
      Text('最近事件:')
        .fontSize(12)
      ForEach(this.lastEvents, (item: string) => {
        Text(item)
          .fontSize(11)
      }, (item: string) => item)
      Button('刷新指标 / 退订')
        .onClick(() => {
          this.refreshMetrics();
          if (this.subscriptionId !== 0) {
            TdBridge.unsubscribe(this.subscriptionId);
            this.subscriptionId = 0;
            this.refreshMetrics();
          }
        })
      Text(this.metricsText)
        .fontSize(11)
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
    this.runSubscribeCheck();
  }
}
