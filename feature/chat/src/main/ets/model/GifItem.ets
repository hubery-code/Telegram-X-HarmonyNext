/**
 * Telegram X HarmonyOS NEXT
 * GIF 动图模型（FEAT-P2-004）
 * 100% Kit-free 纯 ArkTS
 *
 * ## 这个文件为什么只剩模型（GIF-SEND-101，2026-10-24）
 *
 * 这里原先还有 `DEFAULT_GIF_PACKS`（5 个分类、25 个「预置动图」）与
 * `DEFAULT_RECENT_GIFS`（4 项），每项只有 `title` / `previewEmoji` /
 * 一个 **2001-2040 的假 fileId**，**没有任何真实文件**。
 *
 * 它们造成的后果不是「少一个功能」，而是**发出去的东西是假的**：
 * `ChatCoordinator.handleSendAnimation` 里有一段专门为这个号段写的分支 ——
 * 一旦命中就 `sendTextMessage('🎬 ' + title, 0)`，也就是**把「发 GIF」悄悄
 * 变成「发一句带 emoji 的文本」，连 chatId 都传的是 0**。用户在面板上点一张
 * 动图，以为发出去的是动图。
 *
 * 真正能发的动图一直都有：GIF-SAVED-101 已经把 TDLib 的 `getSavedAnimations`
 * 接进 `recentGifs`（`onSavedAnimationsLoaded` 写的就是这个字段），那些条目带
 * **真实 fileId**，走的是正常的 `inputMessageAnimation` 路径。
 *
 * 所以修法是删掉占位库，让面板**只显示真实动图**：这样「面板上能点的，就一定
 * 发得出去」成为一条不变量，而不是靠一个号段判断去兜。代价是首次打开面板时
 * 若 TDLib 还没回包，列表是空的 —— 那是**诚实的空**，比一排点了发文本的假图好。
 *
 * 分类也相应收成「最近」一项：远端没有「热门动图」接口（Telegram 的 GIF 搜索
 * 走 `searchAnimation`，本端未接），凭空造 5 个分类等于又造一次假数据。
 */

export interface GifItem {
  id: string;
  title: string;
  tag: string;
  category: string;
  /** TDLib 的 animation file id；**必须是真实文件**，否则发不出去。 */
  fileId: number;
  width: number;
  height: number;
  duration: number;
  previewEmoji: string;
}

/**
 * GIF 面板的分类。
 *
 * 只有「最近」一项，因为它是唯一有真实数据来源的分类（TDLib 的
 * `getSavedAnimations`）。热门/搞笑/派对那些分类在 Telegram 上要么走
 * `searchAnimation`（本端未接），要么由服务端下发的 GIF 集合提供 ——
 * 都不在本端能力内，写死分类只会导向又一批假条目。
 */
export const GIF_CATEGORIES: string[] = [
  '🕒 Recent'
];

/** 首次打开面板时的空列表（不用假数据填充）。 */
export const EMPTY_GIFS: GifItem[] = [];
