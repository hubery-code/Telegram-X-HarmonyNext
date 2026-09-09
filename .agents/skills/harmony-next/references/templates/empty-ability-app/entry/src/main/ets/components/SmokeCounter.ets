@Component
export struct SmokeCounter {
  @State message: string = 'Harmony Smoke Ready';
  @State taps: number = 0;

  build() {
    Row() {
      Column({ space: 12 }) {
        Text(this.message)
          .fontSize($r('app.float.page_title_font_size'))
          .fontWeight(FontWeight.Bold)
          .id('smoke-title')

        Text('tapCount=' + this.taps)
          .fontSize($r('app.float.page_body_font_size'))
          .id('smoke-counter')

        Button('Increment')
          .id('smoke-increment')
          .onClick(() => {
            this.taps += 1;
            this.message = 'Harmony Smoke Tapped';
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .height('100%')
    .padding(24)
    .backgroundColor($r('app.color.page_background'))
  }
}
