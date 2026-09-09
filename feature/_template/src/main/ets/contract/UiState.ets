/**
 * feature/_template — UiState / Intent / Effect 标记约定（UI-003）。
 *
 * 三个空接口是计划 §5.11「每个 Feature 使用 UiState + Intent + Effect」
 * 的编译期约定标记：
 * - UiState：页面渲染所需的完整可观察状态，不可变，经 copyWith 派生；
 * - Intent：用户动作 / 系统事件，由 UI 层单向发送给 reducer；
 * - Effect：一次性副作用描述（导航、弹窗、震动、异步请求发起等），
 *   reducer 只产出描述，不执行；执行由 EffectHandler / UseCase 完成。
 *
 * 本模块是纯 ArkTS 契约层：不 import ArkUI / Ability / 任何 Kit。
 */

export interface UiState {
}

export interface Intent {
}

export interface Effect {
}
