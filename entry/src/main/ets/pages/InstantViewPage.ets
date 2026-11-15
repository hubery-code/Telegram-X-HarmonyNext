/**
 * entry — Instant View 阅读器页（IV-102）。
 *
 * 数据链路：路由参数 url → WebPageProjection.fetchInstantView（IV-101 的
 * core/domain 数据层，AccountScope 由装配层 Index 传入）→ pending.promise
 * → projectInstantView 解码为本页 @State 的 InstantViewPage 模型。
 * 取数直接发生在页面里而不是协调器：Instant View 是「按 URL 取一次、渲染完即走」
 * 的只读页面，没有意图/状态机可谈，MVI 那套在这只有一个取数动作 —— 照搬协调器
 * 只会得到一个只有一个方法的空壳。重试（onRetry）就是重新 fetchPage。
 *
 * fallback 语义（v1）：fetch 失败 / TDLib 回空 blocks / 解码失败 一律**不外跳
 * 浏览器**，页内出错误态 + 重试。TDLib `internalLinkTypeInstantView` 携带的
 * fallback_url 在分流层（AppLinkRouter）就已被丢弃，本页无从也不必感知。
 *
 * 渲染：InstantViewBlock[] 按 kind 分支（if/else 链 —— ArkUI 条件渲染不支持
 * switch）。文本已由数据层拍平为纯文本，这里只做排版分级与装饰；
 * anchor / unknown 跳过（数据层注释里的降级契约）。
 *
 * 已知边界（如实注释，后续包接手）：
 * - figure 家族（photo/video/audio/...）只出高度占位框 + caption：媒体 fileId
 *   下载链路是后续包，imageUrl 恒空（数据层预留直链位），无图可渲染；
 * - buttons / related 卡片 / chatLink / figure 的 url 均不接跳转（外跳语义待定）；
 * - isFull=false 只出「全文仅部分」提示条，不做增量展开（本仓 schema 无
 *   rv_version，无法做 TDLib 的 iv 变更流式刷新）；
 * - RTL 只做文本 textAlign 右对齐的轻量支持，行方向/边距不做镜像。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import {
  A11y,
  a11y,
  AppError,
  datePartsFrom,
  formatMonthDayYear,
  Lang,
  Result,
  SupportedLanguage
} from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import {
  InstantViewBlock,
  InstantViewListItem,
  InstantViewPage as InstantViewPageData,
  WebPageProjection
} from '@tgx/core-domain';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { TdJsonRaw } from '@tgx/core-td-api-generated';

/** figure 占位框的固定高度（vp）。真实宽高比等 fileId 下载链路（后续包）再还原。 */
const FIGURE_PLACEHOLDER_HEIGHT: number = 160;
/** details 折叠头（含 chevron）的最小高度。 */
const DETAILS_HEADER_HEIGHT: number = 44;

@Component
export struct InstantViewPage {
  /**
   * FEAT-UI-001 / I18N-HOTSWITCH-101：与 CommentsPage 同构的主题/语言订阅。
   * t() 读 effectiveLanguage、样式读 T，换语言/主题时本页随之重渲染。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @StorageProp('activeLanguage') effectiveLanguage: string = 'zh';

  /**
   * 要取 Instant View 的网页地址。@Watch 是给「已在阅读页又深链了另一篇」的
   * 场景：同一分支复用组件实例时 aboutToAppear 不会再走，靠属性变化重取。
   */
  @Prop @Watch('onUrlChanged') url: string = '';
  /** 账号级 scope，装配层（Index）传入；登出清栈时页面会先被卸载，仅需判空。 */
  scope: AccountScope | null = null;
  onBack: () => void = () => {};

  @State isLoading: boolean = true;
  /** 出错时存 Lang key（不是原文）——词典未落期间屏幕回吐 key 本身，见交付报告。 */
  @State errorKey: string = '';
  @State pageModel: InstantViewPageData | null = null;
  /**
   * details 折叠状态的版本戳。openDetailsMap 本身不是可观察状态（Map 内容变化
   * 不触发 ArkUI 重渲染），每次切换时自增版本号，读取方经 isDetailsOpen 把
   * 版本号折进渲染依赖（与 t() 读 effectiveLanguage 同一机制）。
   */
  @State detailsVersion: number = 0;
  /** details 折叠状态表，key 是块路径（'b3' / 'b3/1'），值是当前是否展开。 */
  private openDetailsMap: Map<string, boolean> = new Map();
  /** 请求序号：重试/换 url 时作废在途回包，防止旧响应写进新页面。 */
  private fetchSeq: number = 0;
  /** 生命周期哨兵：页面销毁后迟到的 promise 回调不再碰 @State。 */
  private isAlive: boolean = false;

  aboutToAppear(): void {
    this.isAlive = true;
    this.fetchPage();
  }

  aboutToDisappear(): void {
    this.isAlive = false;
  }

  private onUrlChanged(): void {
    // 组件被复用（同分支换参）时重取；首次挂载走 aboutToAppear，两者都到也无害
    // （fetchSeq 会把第一次的回包作废）。
    this.fetchPage();
  }

  // ---------- 取数 ----------

  /** 发起（或重试）一次 Instant View 取数。错误一律落 errorKey，页内呈现。 */
  private fetchPage(): void {
    if (this.scope === null) {
      // 装配层未给 scope（未登录窗口期等）——按失败呈现，不重试到有为止。
      this.isLoading = false;
      this.errorKey = 'Failed to load page';
      return;
    }
    const seq: number = this.fetchSeq + 1;
    this.fetchSeq = seq;
    this.isLoading = true;
    this.errorKey = '';
    this.pageModel = null;
    this.openDetailsMap.clear();
    const projector: WebPageProjection = new WebPageProjection(this.scope);
    const res: Result<TdPendingRequest, AppError> = projector.fetchInstantView(this.url);
    // ArkTS 不做 early-return 后的 Result 收窄：err / ok 双分支并列（编译红线）。
    if (res.err) {
      // 本地参数校验被拒（深链分流已保证 http(s)，这里是防御路径）。
      this.isLoading = false;
      this.errorKey = 'Failed to load page';
      return;
    }
    if (res.ok) {
      const pending: TdPendingRequest | null = res.getOrNull();
      if (pending === null) {
        this.isLoading = false;
        this.errorKey = 'Failed to load page';
        return;
      }
      pending.promise.then((reply: Result<TdWireObject, AppError>): void => {
        if (!this.isAlive || seq !== this.fetchSeq) {
          // 页面已销毁 / 已有更新的请求在途：丢弃，绝不写旧状态。
          return;
        }
        this.settleReply(projector, reply);
      });
    }
  }

  /** TDLib 回包 → 页模型；取不到可用页面时按 v1 口径页内报错，不外跳浏览器。 */
  private settleReply(projector: WebPageProjection, reply: Result<TdWireObject, AppError>): void {
    this.isLoading = false;
    if (reply.err) {
      this.errorKey = 'Failed to load page';
      return;
    }
    if (reply.ok) {
      const raw: TdJsonRaw | null = reply.getOrNull() as TdJsonRaw;
      const model: InstantViewPageData | null = raw === null ? null : projector.projectInstantView(raw);
      if (model === null || model.blocks.length === 0) {
        // TDLib 对没有 Instant View 的网页回空 blocks；解码失败同理。
        this.errorKey = 'Instant View is not available for this page';
        return;
      }
      this.pageModel = model;
    }
  }

  private onRetry(): void {
    this.fetchPage();
  }

  // ---------- 渲染辅助（@Builder 内不能声明局部变量，逻辑全收在方法里） ----------

  private t(key: string, ...args: (string | number)[]): string {
    const langCode: SupportedLanguage = this.effectiveLanguage === 'zh' ? 'zh' : 'en';
    return Lang.getInstance().formatByKey(key, langCode, args);
  }

  private langCode(): SupportedLanguage {
    return this.effectiveLanguage === 'zh' ? 'zh' : 'en';
  }

  /** RTL 页面文本右对齐（轻量支持：只对齐文本，不镜像行方向/边距）。 */
  private isRtl(): boolean {
    return this.pageModel !== null && this.pageModel.isRtl;
  }

  private bodyAlign(): TextAlign {
    return this.isRtl() ? TextAlign.End : TextAlign.Start;
  }

  private blocks(): InstantViewBlock[] {
    return this.pageModel === null ? [] : this.pageModel.blocks;
  }

  private pageIsFull(): boolean {
    return this.pageModel !== null && this.pageModel.isFull;
  }

  /** 顶栏标题：取第一个非空 title 块，页面未就绪时回退到固定标题。 */
  private titleText(): string {
    const all: InstantViewBlock[] = this.blocks();
    for (const block of all) {
      if (block.kind === 'title' && block.text.length > 0) {
        return block.text;
      }
    }
    return this.t('Instant View');
  }

  private isDetailsOpen(key: string, initial: boolean): boolean {
    // 版本号参与读取表达式，建立渲染依赖（见 detailsVersion 注释）。
    const stamp: boolean = this.detailsVersion >= 0;
    const stored: boolean | undefined = this.openDetailsMap.get(key);
    return stamp && (stored === undefined ? initial : stored);
  }

  private toggleDetails(key: string, initial: boolean): void {
    const stored: boolean | undefined = this.openDetailsMap.get(key);
    const current: boolean = stored === undefined ? initial : stored;
    this.openDetailsMap.set(key, !current);
    this.detailsVersion = this.detailsVersion + 1;
  }

  /** figure 家族占位图标（真实媒体渲染等 fileId 下载链路，后续包）。 */
  private figureIcon(mediaType: string): Resource {
    if (mediaType === 'video' || mediaType === 'animation') {
      return $r('app.media.ic_video');
    }
    if (mediaType === 'audio' || mediaType === 'voiceNote') {
      return $r('app.media.ic_music');
    }
    if (mediaType === 'document') {
      return $r('app.media.ic_file');
    }
    if (mediaType === 'embedded' || mediaType === 'embeddedPost') {
      return $r('app.media.ic_link');
    }
    // photo / cover / collage / slideshow / map / 未知 —— map 无专用图标，先落 info。
    return $r('app.media.ic_photo');
  }

  /** byline 一行串：作者 + 发表日期（日期形态统一走 core/common 的 DateFormat）。 */
  private bylineText(block: InstantViewBlock): string {
    if (block.publishDate > 0 && block.text.length > 0) {
      return `${block.text} · ${formatMonthDayYear(this.langCode(), datePartsFrom(block.publishDate * 1000))}`;
    }
    if (block.publishDate > 0) {
      return formatMonthDayYear(this.langCode(), datePartsFrom(block.publishDate * 1000));
    }
    return block.text;
  }

  // ---------- build ----------

  build() {
    Column() {
      this.TopBar()
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(this.T.colors.accent)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.T.colors.background)
      } else if (this.errorKey.length > 0) {
        this.ErrorState()
      } else {
        this.LoadedBody()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }

  @Builder
  TopBar() {
    Row() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(this.T.colors.textPrimary)
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .accessibilityText(a11y(A11y.BACK))
      .onClick(() => {
        this.onBack();
      })

      Text(this.titleText())
        .fontSize(this.T.typography.title.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.T.colors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: this.T.spacing.xs })
    }
    .width('100%')
    .height(56)
    .padding({ left: this.T.spacing.sm, right: this.T.spacing.md })
    .backgroundColor(this.T.colors.surface)
    .borderWidth({ bottom: 0.5 })
    .borderColor(this.T.colors.divider)
  }

  /** 错误态：页内呈现 + 重试。v1 不做 fallback_url 外跳浏览器（分流层已丢弃该字段）。 */
  @Builder
  ErrorState() {
    Column() {
      Image($r('app.media.ic_info'))
        .width(48)
        .height(48)
        .fillColor(this.T.colors.textTertiary)
        .margin({ bottom: this.T.spacing.sm })

      Text(this.t(this.errorKey))
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ bottom: this.T.spacing.md })

      Text(this.t('Retry'))
        .fontSize(this.T.typography.callout.fontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.T.colors.accent)
        .padding({ left: this.T.spacing.lg, right: this.T.spacing.lg, top: this.T.spacing.sm, bottom: this.T.spacing.sm })
        .borderRadius(this.T.radius.full)
        .borderWidth(1)
        .borderColor(this.T.colors.accent)
        .onClick(() => {
          this.onRetry();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: this.T.spacing.xl, right: this.T.spacing.xl })
    .backgroundColor(this.T.colors.background)
  }

  @Builder
  LoadedBody() {
    Scroll() {
      Column() {
        ForEach(this.blocks().slice(), (block: InstantViewBlock, idx: number) => {
          this.blockView(block, `b${idx}`)
        }, (block: InstantViewBlock, idx: number) => `b${idx}_${block.kind}`)

        // isFull=false：底部提示条。v1 不做增量展开 —— 本仓 InstantViewModel
        // 未投出 rv_version，TDLib 的 iv 版本流式刷新没有落点（如实注释）。
        if (!this.pageIsFull()) {
          Row() {
            Image($r('app.media.ic_info'))
              .width(14)
              .height(14)
              .fillColor(this.T.colors.textSecondary)
              .margin({ right: this.T.spacing.xs })

            Text(this.t('This article is not fully loaded yet'))
              .fontSize(this.T.typography.footnote.fontSize)
              .fontColor(this.T.colors.textSecondary)
          }
          .width('100%')
          .padding(this.T.spacing.md)
          .backgroundColor(this.T.colors.surfaceVariant)
          .borderRadius(this.T.radius.md)
          .margin({ top: this.T.spacing.sm, bottom: this.T.spacing.lg })
        }
      }
      .width('100%')
      .padding({
        left: this.T.spacing.md,
        right: this.T.spacing.md,
        top: this.T.spacing.md
      })
      .alignItems(this.isRtl() ? HorizontalAlign.End : HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
    .backgroundColor(this.T.colors.background)
  }

  /**
   * 单块渲染分发（if/else 链 —— ArkUI 条件渲染不支持 switch）。
   * path 是块在树里的唯一路径（'b3' / 'b3/1'），作 details 折叠状态的 key。
   */
  @Builder
  blockView(block: InstantViewBlock, path: string) {
    if (block.kind === 'title') {
      if (block.text.length > 0) {
        Text(block.text)
          .fontSize(this.T.typography.largeTitle.fontSize)
          .lineHeight(this.T.typography.largeTitle.lineHeight)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.T.colors.textPrimary)
          .textAlign(this.bodyAlign())
          .width('100%')
          .margin({ top: this.T.spacing.xs, bottom: this.T.spacing.sm })
      }
    } else if (block.kind === 'subtitle') {
      if (block.text.length > 0) {
        Text(block.text)
          .fontSize(this.T.typography.subheadline.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .textAlign(this.bodyAlign())
          .width('100%')
          .margin({ bottom: this.T.spacing.sm })
      }
    } else if (block.kind === 'kicker') {
      if (block.text.length > 0) {
        Text(block.text)
          .fontSize(this.T.typography.footnote.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.accent)
          .textAlign(this.bodyAlign())
          .width('100%')
          .margin({ bottom: this.T.spacing.xs })
      }
    } else if (block.kind === 'byline') {
      if (block.text.length > 0 || block.publishDate > 0) {
        Text(this.bylineText(block))
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .textAlign(this.bodyAlign())
          .width('100%')
          .margin({ bottom: this.T.spacing.sm })
      }
    } else if (block.kind === 'header') {
      // header 家族带 level（2=pageBlockHeader / 3=subheader / 4=sectionHeading）。
      if (block.text.length > 0) {
        Text(block.text)
          .fontSize(block.level <= 2 ? this.T.typography.headline.fontSize : (block.level === 3 ? this.T.typography.subheadline.fontSize : this.T.typography.footnote.fontSize))
          .fontWeight(FontWeight.Bold)
          .fontColor(this.T.colors.textPrimary)
          .textAlign(this.bodyAlign())
          .width('100%')
          .margin({ top: this.T.spacing.sm, bottom: this.T.spacing.xs })
      }
    } else if (block.kind === 'paragraph') {
      if (block.text.length > 0) {
        Text(block.text)
          .fontSize(this.T.typography.body.fontSize)
          .lineHeight(this.T.typography.body.lineHeight)
          .fontColor(this.T.colors.textPrimary)
          .textAlign(this.bodyAlign())
          .width('100%')
          .margin({ bottom: this.T.spacing.sm })
      }
    } else if (block.kind === 'preformatted') {
      // 等宽 + 背景块。v1 让长行自动换行（不做横向滚动，等宽语义仍保留）。
      Column() {
        Text(block.text)
          .fontSize(this.T.typography.footnote.fontSize)
          .lineHeight(this.T.typography.body.lineHeight)
          .fontFamily('monospace')
          .fontColor(this.T.colors.textPrimary)
          .textAlign(this.bodyAlign())
          .width('100%')
      }
      .width('100%')
      .padding(this.T.spacing.sm)
      .backgroundColor(this.T.colors.surfaceVariant)
      .borderRadius(this.T.radius.md)
      .margin({ bottom: this.T.spacing.sm })
    } else if (block.kind === 'quote') {
      this.quoteView(block, false)
    } else if (block.kind === 'pullquote') {
      this.quoteView(block, true)
    } else if (block.kind === 'figure') {
      this.figureView(block, path)
    } else if (block.kind === 'list') {
      this.listView(block)
    } else if (block.kind === 'details') {
      this.detailsView(block, path)
    } else if (block.kind === 'table') {
      this.tableView(block)
    } else if (block.kind === 'related') {
      this.relatedView(block)
    } else if (block.kind === 'buttons') {
      this.buttonsView(block)
    } else if (block.kind === 'divider') {
      Row()
        .width('100%')
        .height(0.5)
        .backgroundColor(this.T.colors.divider)
        .margin({ top: this.T.spacing.xs, bottom: this.T.spacing.sm })
    } else if (block.kind === 'chatLink') {
      // chatLink：卡片呈现标题与用户名。v1 不接跳转（进会话要 searchPublicChat，
      // 与阅读器的纯浏览语义待产品对齐后再接，如实注释）。
      Row() {
        Column() {
          Text(block.text)
            .fontSize(this.T.typography.headline.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.T.colors.accent)
            .textAlign(this.bodyAlign())
            .width('100%')
          if (block.url.length > 0) {
            Text(`@${block.url}`)
              .fontSize(this.T.typography.footnote.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .textAlign(this.bodyAlign())
              .width('100%')
              .margin({ top: 2 })
          }
        }
        .alignItems(this.isRtl() ? HorizontalAlign.End : HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(this.T.spacing.md)
      .backgroundColor(this.T.colors.surface)
      .borderRadius(this.T.radius.md)
      .borderWidth(0.5)
      .borderColor(this.T.colors.divider)
      .margin({ bottom: this.T.spacing.sm })
    }
    // anchor（纯锚点，无可见内容）与 unknown（TDLib 新块型降级）不渲染任何节点。
  }

  /**
   * quote / pullquote：左重音描边 + 缩进文本；pullquote 更重（标题级字重）。
   * 重音条用单边 border 而不是独立色条 —— 色条要靠 height('100%') 撑满，
   * 在自适应高度的 Row 里会塌陷，描边则随文本自然等高。
   */
  @Builder
  quoteView(block: InstantViewBlock, isPull: boolean) {
    Column() {
      if (block.text.length > 0) {
        Text(block.text)
          .fontSize(isPull ? this.T.typography.headline.fontSize : this.T.typography.body.fontSize)
          .lineHeight(this.T.typography.body.lineHeight)
          .fontWeight(isPull ? FontWeight.Bold : FontWeight.Regular)
          .fontStyle(isPull ? FontStyle.Normal : FontStyle.Italic)
          .fontColor(this.T.colors.textPrimary)
          .textAlign(this.bodyAlign())
          .width('100%')
      }
      if (block.credit.length > 0) {
        Text(block.credit)
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .textAlign(this.bodyAlign())
          .width('100%')
          .margin({ top: this.T.spacing.xs })
      }
    }
    .width('100%')
    .alignItems(this.isRtl() ? HorizontalAlign.End : HorizontalAlign.Start)
    .padding({ left: this.T.spacing.sm })
    .borderWidth({ left: isPull ? 4 : 3 })
    .borderColor(this.T.colors.accent)
    .margin({ top: this.T.spacing.xs, bottom: this.T.spacing.sm })
  }

  /**
   * figure 家族（photo/video/animation/audio/voiceNote/document/map/embedded/
   * embeddedPost/collage/slideshow/cover）。v1 一律渲染「占位框 + caption/credit」：
   * 媒体走 fileId 下载链路（后续包），imageUrl 恒空，无直链可拉；
   * 占位框内按 mediaType 给图标，height 不参与布局（像素语义未经换算，如实注释）。
   */
  @Builder
  figureView(block: InstantViewBlock, path: string) {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(this.T.colors.surfaceVariant)

        Image(this.figureIcon(block.mediaType))
          .width(32)
          .height(32)
          .fillColor(this.T.colors.textTertiary)
          .accessibilityLevel('no')
      }
      .width('100%')
      .height(FIGURE_PLACEHOLDER_HEIGHT)
      .borderRadius(this.T.radius.md)

      if (block.caption.length > 0) {
        Text(block.caption)
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .textAlign(this.bodyAlign())
          .width('100%')
          .margin({ top: this.T.spacing.xs })
      }
      if (block.credit.length > 0) {
        Text(block.credit)
          .fontSize(this.T.typography.caption.fontSize)
          .fontColor(this.T.colors.textTertiary)
          .textAlign(this.bodyAlign())
          .width('100%')
          .margin({ top: 2 })
      }
      // embeddedPost 内嵌帖子正文（作者在 text 里）；collage/slideshow/cover 的
      // 子块（多为 photo）也平铺渲染成各自的占位卡。
      if (block.text.length > 0 && block.mediaType === 'embeddedPost') {
        Text(this.bylineText(block))
          .fontSize(this.T.typography.subheadline.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.textPrimary)
          .textAlign(this.bodyAlign())
          .width('100%')
          .margin({ top: this.T.spacing.xs })
      }
      if (block.children.length > 0) {
        ForEach(block.children.slice(), (child: InstantViewBlock, idx: number) => {
          this.blockView(child, `${path}/${idx}`)
        }, (child: InstantViewBlock, idx: number) => `${path}/${idx}_${child.kind}`)
      }
    }
    .width('100%')
    .margin({ bottom: this.T.spacing.sm })
  }

  /** list：编号/项目符号 label 或只读勾选框 + 条目文本（checkbox 不可点，纯展示）。 */
  @Builder
  listView(block: InstantViewBlock) {
    Column() {
      ForEach(block.items.slice(), (item: InstantViewListItem, idx: number) => {
        Row() {
          if (item.hasCheckbox) {
            Stack({ alignContent: Alignment.Center }) {
              Image($r('app.media.ic_checkbox_empty'))
                .width(18)
                .height(18)
                .fillColor(this.T.colors.accent)
              if (item.isChecked) {
                Image($r('app.media.ic_check_single'))
                  .width(14)
                  .height(14)
                  .fillColor(this.T.colors.accent)
              }
            }
            .width(20)
            .height(20)
            .margin({ right: this.T.spacing.sm })
            .accessibilityLevel('no')
          } else if (item.label.length > 0) {
            Text(item.label)
              .fontSize(this.T.typography.body.fontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.T.colors.accent)
              .width(24)
              .margin({ right: this.T.spacing.xs })
          }

          Text(item.text)
            .fontSize(this.T.typography.body.fontSize)
            .lineHeight(this.T.typography.body.lineHeight)
            .fontColor(this.T.colors.textPrimary)
            .textAlign(this.bodyAlign())
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .margin({ bottom: idx === block.items.length - 1 ? this.T.spacing.sm : this.T.spacing.xs })
      }, (item: InstantViewListItem, idx: number) => `li${idx}_${item.text.length}`)
    }
    .width('100%')
  }

  /** details：可折叠块。isOpen 是 TDLib 投出的初值，点击头部展开/收起 children。 */
  @Builder
  detailsView(block: InstantViewBlock, path: string) {
    Column() {
      Row() {
        Text(block.text)
          .fontSize(this.T.typography.headline.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.textPrimary)
          .textAlign(this.bodyAlign())
          .layoutWeight(1)

        if (block.children.length > 0) {
          Image($r('app.media.ic_chevron_down'))
            .width(16)
            .height(16)
            .fillColor(this.T.colors.textSecondary)
            .rotate({ angle: this.isDetailsOpen(path, block.isOpen) ? 180 : 0 })
            .accessibilityLevel('no')
        }
      }
      .width('100%')
      .height(DETAILS_HEADER_HEIGHT)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.toggleDetails(path, block.isOpen);
      })

      // 展开条件读 isDetailsOpen（内部折入 detailsVersion）→ 切换即重渲染。
      if (this.isDetailsOpen(path, block.isOpen) && block.children.length > 0) {
        Column() {
          ForEach(block.children.slice(), (child: InstantViewBlock, idx: number) => {
            this.blockView(child, `${path}/${idx}`)
          }, (child: InstantViewBlock, idx: number) => `${path}/${idx}_${child.kind}`)
        }
        .width('100%')
        .padding({ left: this.T.spacing.md })
        .borderWidth({ left: 0.5 })
        .borderColor(this.T.colors.divider)
        .margin({ bottom: this.T.spacing.sm })
      }
    }
    .width('100%')
    .margin({ bottom: this.T.spacing.xs })
  }

  /** table：简单网格（每格一行文本，等分宽）。v1 不做列对齐/跨行跨列（如实注释）。 */
  @Builder
  tableView(block: InstantViewBlock) {
    Column() {
      if (block.caption.length > 0) {
        Text(block.caption)
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .textAlign(this.bodyAlign())
          .width('100%')
          .margin({ bottom: this.T.spacing.xs })
      }
      ForEach(block.rows.slice(), (row: string[], rowIdx: number) => {
        Row() {
          ForEach(row.slice(), (cell: string, cellIdx: number) => {
            Text(cell)
              .fontSize(this.T.typography.footnote.fontSize)
              .fontColor(this.T.colors.textPrimary)
              .textAlign(this.bodyAlign())
              .layoutWeight(1)
              .padding(this.T.spacing.xs)
          }, (cell: string, cellIdx: number) => `c${rowIdx}_${cellIdx}_${cell.length}`)

        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .backgroundColor(block.isStriped && rowIdx % 2 === 1 ? this.T.colors.surfaceVariant : Color.Transparent)
        .borderWidth({ bottom: block.isBordered ? 0.5 : 0 })
        .borderColor(this.T.colors.divider)
      }, (row: string[], rowIdx: number) => `r${rowIdx}_${row.length}`)
    }
    .width('100%')
    .margin({ bottom: this.T.spacing.sm })
  }

  /** related：相关文章区（区头 + 子卡文本）。v1 卡片不接跳转（url 留在数据层）。 */
  @Builder
  relatedView(block: InstantViewBlock) {
    Column() {
      if (block.text.length > 0) {
        Text(block.text)
          .fontSize(this.T.typography.headline.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.T.colors.textPrimary)
          .textAlign(this.bodyAlign())
          .width('100%')
          .margin({ bottom: this.T.spacing.xs })
      }
      ForEach(block.children.slice(), (card: InstantViewBlock, idx: number) => {
        Column() {
          if (card.text.length > 0) {
            Text(card.text)
              .fontSize(this.T.typography.subheadline.fontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.T.colors.accent)
              .textAlign(this.bodyAlign())
              .width('100%')
          }
          if (card.caption.length > 0) {
            Text(card.caption)
              .fontSize(this.T.typography.footnote.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .textAlign(this.bodyAlign())
              .width('100%')
              .margin({ top: 2 })
          }
          if (card.publishDate > 0) {
            Text(formatMonthDayYear(this.langCode(), datePartsFrom(card.publishDate * 1000)))
              .fontSize(this.T.typography.caption.fontSize)
              .fontColor(this.T.colors.textTertiary)
              .width('100%')
              .margin({ top: 2 })
          }
        }
        .width('100%')
        .alignItems(this.isRtl() ? HorizontalAlign.End : HorizontalAlign.Start)
        .padding({ top: this.T.spacing.xs, bottom: this.T.spacing.xs })
        // 子卡之间用细线分隔（最后一根随区块 margin 收口，不影响可读）。
        .borderWidth({ bottom: idx === block.children.length - 1 ? 0 : 0.5 })
        .borderColor(this.T.colors.divider)
      }, (card: InstantViewBlock, idx: number) => `ra${idx}_${card.text.length}`)
    }
    .width('100%')
    .margin({ bottom: this.T.spacing.sm })
  }

  /**
   * buttons：文字按钮列。v1 渲染按钮外观但**不接 onClick**——块级 url 外跳
   * 语义（浏览器/路由/会话）待后续包定夺，接了空 onClick 反而给读屏器假可点语义。
   */
  @Builder
  buttonsView(block: InstantViewBlock) {
    Column() {
      ForEach(block.children.slice(), (button: InstantViewBlock, idx: number) => {
        if (button.kind === 'button' && button.text.length > 0) {
          Text(button.text)
            .fontSize(this.T.typography.callout.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.T.colors.accent)
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding(this.T.spacing.sm)
            .borderRadius(this.T.radius.md)
            .borderWidth(1)
            .borderColor(this.T.colors.accent)
            .margin({ bottom: idx === block.children.length - 1 ? this.T.spacing.sm : this.T.spacing.xs })
        }
      }, (button: InstantViewBlock, idx: number) => `btn${idx}_${button.text.length}`)
    }
    .width('100%')
  }
}
