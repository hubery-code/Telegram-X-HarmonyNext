/**
 * feature/settings — 四位数字密码键盘（APPLOCK-101）。
 *
 * 设置页的「创建 / 修改 / 关闭」流程和 entry 的锁屏遮罩共用这一个组件：键盘只有一处实现，
 * 才不会出现「设置页允许某位输入、锁屏页不允许」这类两套真相。对标 Android `PasscodeView`：
 * 四个点 + 数字盘 + 退格，**满四位自动提交**（`PasscodeController.java:419-431`），
 * 不再要求按一次「确定」。
 *
 * ## 输入的值为什么留在组件里
 *
 * `entry` 只是本组件的 `@State`，提交后立刻清空：不进 `SettingsUiState`、不进 reducer、
 * 不进日志。理由与端口层一致 —— 可观察状态会被复制、快照、打印，秘密值一旦进去就到处留副本。
 * 组件对外只交出一次性回调 `onSubmit(pin)`，父级把它转成 intent 交给 coordinator 落盘。
 */

import { Theme, ThemeManager, ThemePreference, LightTheme } from '@tgx/core-design-system';
import { Lang, SupportedLanguage } from '@tgx/core-common';
import { APP_LOCK_PIN_LENGTH } from '@tgx/core-domain';

/** 数字盘排布：前三行 1-9，末行是退格、0、取消。 */
const KEY_ROWS: string[][] = [
  ['1', '2', '3'],
  ['4', '5', '6'],
  ['7', '8', '9'],
  ['', '0', '']
];

/** 末行的两列不是数字，按下走别的动作（-1 表示退格、-2 表示取消）。 */
const SPECIAL_ROW_INDEX: number = 3;
const BACKSPACE_COLUMN: number = 0;
const CANCEL_COLUMN: number = 2;

@Component
export struct PasscodeKeypad {
  /** 已经翻译好的提示语；父级负责取文案，组件不做语言判定。 */
  @Prop prompt: string = '';
  @Prop notice: string = '';
  @Prop themeMode: ThemePreference = 'system';
  /** 一次校验/写盘在途：数字盘吞掉输入，避免等待期里堆出第二次提交。 */
  @Prop busy: boolean = false;
  /** 锁屏遮罩里没有「取消」可点 —— 不解锁就是不让进。 */
  @Prop cancellable: boolean = true;
  onSubmit: (pin: string) => void = (): void => {};
  onCancel: () => void = (): void => {};

  @State private entry: string = '';
  @State private effectiveTheme: Theme = LightTheme;
  @State private effectiveLang: SupportedLanguage = 'en';

  private unsubscribeTheme: (() => void) | null = null;
  private unsubscribeLang: (() => void) | null = null;

  aboutToAppear(): void {
    this.updateEffectiveTheme();
    this.effectiveLang = Lang.getInstance().getLanguage();
    const self: PasscodeKeypad = this;
    this.unsubscribeTheme = ThemeManager.getInstance().subscribe((_theme: Theme): void => {
      self.updateEffectiveTheme();
    });
    this.unsubscribeLang = Lang.getInstance().subscribe((lang: SupportedLanguage): void => {
      self.effectiveLang = lang;
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
    if (this.unsubscribeLang !== null) {
      this.unsubscribeLang();
      this.unsubscribeLang = null;
    }
  }

  private updateEffectiveTheme(): void {
    this.effectiveTheme = ThemeManager.getInstance().resolveTheme(this.themeMode);
  }

  private getTheme(): Theme {
    return this.effectiveTheme;
  }

  private t(key: string, ...args: (string | number)[]): string {
    return Lang.getInstance().formatByKey(key, this.effectiveLang, args);
  }

  /** 父级在流程重置时清空输入（例如从「确认」退回「输入新密码」）。 */
  clearEntry(): void {
    this.entry = '';
  }

  private appendDigit(digit: string): void {
    if (this.busy || this.entry.length >= APP_LOCK_PIN_LENGTH) {
      return;
    }
    const next: string = this.entry + digit;
    if (next.length < APP_LOCK_PIN_LENGTH) {
      this.entry = next;
      return;
    }
    // 满位即提交并清空：留在屏上的四位数字既没意义也是多余的暴露面。
    this.entry = '';
    this.onSubmit(next);
  }

  private popDigit(): void {
    if (this.busy || this.entry.length === 0) {
      return;
    }
    this.entry = this.entry.substring(0, this.entry.length - 1);
  }

  build() {
    Column() {
      Blank()

      this.PromptView()
      this.DotsView()
      this.NoticeView()

      Blank()

      this.KeysView()
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.getTheme().spacing.xl,
      right: this.getTheme().spacing.xl,
      bottom: this.getTheme().spacing.xxl
    })
    .backgroundColor(this.getTheme().colors.background)
  }

  @Builder
  PromptView() {
    Text(this.prompt)
      .fontSize(this.getTheme().typography.title.fontSize)
      .fontWeight(this.getTheme().typography.title.fontWeight)
      .fontColor(this.getTheme().colors.textPrimary)
      .textAlign(TextAlign.Center)
      .id('passcode-prompt')
      .margin({ bottom: this.getTheme().spacing.lg })
  }

  @Builder
  DotsView() {
    Row() {
      ForEach([0, 1, 2, 3], (slot: number) => {
        // 用圆角矩形而不是 Circle().fill()：后者在当前兼容 SDK（6.1.1/24）上是
        // 26.0.0 才有的属性，编译器会报版本告警，而这里不需要形状组件。
        Column()
          .width(16)
          .height(16)
          .borderRadius(8)
          .margin({ left: this.getTheme().spacing.md, right: this.getTheme().spacing.md })
          .backgroundColor(slot < this.entry.length
            ? this.getTheme().colors.textPrimary
            : this.getTheme().colors.textSecondary)
          .opacity(slot < this.entry.length ? 1 : 0.32)
      })
    }
    .id('passcode-dots')
    .justifyContent(FlexAlign.Center)
    .margin({ bottom: this.getTheme().spacing.lg })
  }

  @Builder
  NoticeView() {
    // 固定一行高度：出现错误文案时不推动键盘位置，避免用户按错位。
    Text(this.notice)
      .fontSize(this.getTheme().typography.footnote.fontSize)
      .fontColor(this.getTheme().colors.destructive)
      .textAlign(TextAlign.Center)
      .height(20)
      .id('passcode-notice')
  }

  @Builder
  KeysView() {
    Column() {
      ForEach(KEY_ROWS, (row: string[], rowIndex: number) => {
        Row() {
          ForEach(row, (key: string, columnIndex: number) => {
            this.KeyView(key, rowIndex, columnIndex)
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      })
    }
    .width('100%')
  }

  @Builder
  KeyView(key: string, rowIndex: number, columnIndex: number) {
    Stack() {
      if (rowIndex === SPECIAL_ROW_INDEX && columnIndex === BACKSPACE_COLUMN) {
        Text(this.t('Delete'))
          .fontSize(this.getTheme().typography.title.fontSize)
          .fontColor(this.getTheme().colors.textPrimary)
          .id('passcode-backspace')
      } else if (rowIndex === SPECIAL_ROW_INDEX && columnIndex === CANCEL_COLUMN) {
        Text(this.t('Cancel'))
          .fontSize(this.getTheme().typography.subheadline.fontSize)
          .fontColor(this.cancellable ? this.getTheme().colors.accent : this.getTheme().colors.textTertiary)
          .id('passcode-cancel')
      } else {
        Text(key)
          .fontSize(this.getTheme().typography.largeTitle.fontSize)
          .fontWeight(this.getTheme().typography.largeTitle.fontWeight)
          .fontColor(this.getTheme().colors.textPrimary)
          .id(`passcode-key-${key}`)
      }
    }
    .width(84)
    .height(84)
    .margin({ top: this.getTheme().spacing.md, bottom: this.getTheme().spacing.md })
    .borderRadius(this.getTheme().radius.full)
    .backgroundColor(this.getTheme().colors.surface)
    .onClick((): void => {
      if (rowIndex === SPECIAL_ROW_INDEX && columnIndex === BACKSPACE_COLUMN) {
        this.popDigit();
        return;
      }
      if (rowIndex === SPECIAL_ROW_INDEX && columnIndex === CANCEL_COLUMN) {
        if (this.cancellable) {
          this.onCancel();
        }
        return;
      }
      this.appendDigit(key);
    })
  }
}
