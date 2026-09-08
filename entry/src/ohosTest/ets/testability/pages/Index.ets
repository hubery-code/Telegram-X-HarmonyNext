@Entry
@Component
struct Index {
  aboutToAppear(): void {
    console.log('testIndex page aboutToAppear');
  }

  build() {
    Column() {
      Text('Telegram X HarmonyOS Test')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }
}
