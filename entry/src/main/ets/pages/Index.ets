@Entry
@Component
struct Index {
  build() {
    Column() {
      Text('Telegram X HarmonyOS')
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }
}
