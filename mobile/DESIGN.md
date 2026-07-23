---
name: "轻影 Luma"
description: "克制、安静、可信的私人媒体播放器"
colors:
  ink: "#101820"
  deep-blue: "#131D27"
  surface: "#1B2732"
  elevated: "#24323E"
  mist: "#9DBFC0"
  gold: "#D0AA69"
  paper: "#F3F5F4"
  success: "#7BAF8A"
  warning: "#D9A05B"
  light-primary: "#426D70"
  dark-primary: "#A8CACA"
  light-secondary: "#866629"
  light-surface-container: "#E8ECEB"
  light-surface-container-high: "#DDE3E2"
  on-ink: "#F3F5F4"
typography:
  headline:
    fontFamily: "system-ui, sans-serif"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.3px"
  title:
    fontFamily: "system-ui, sans-serif"
    fontWeight: 600
    lineHeight: 1.25
  body:
    fontFamily: "system-ui, sans-serif"
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: "system-ui, sans-serif"
    fontWeight: 600
    lineHeight: 1.2
rounded:
  sm: "8px"
  md: "12px"
  lg: "18px"
spacing:
  xxs: "4px"
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "24px"
  xl: "32px"
  xxl: "48px"
components:
  button-primary:
    backgroundColor: "{colors.light-primary}"
    textColor: "{colors.paper}"
    rounded: "{rounded.md}"
    height: "52px"
  surface-card:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.paper}"
    rounded: "{rounded.md}"
    padding: "{spacing.md}"
  player-hud:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    rounded: "{rounded.md}"
    padding: "12px 16px"
layout:
  page-padding-h: "20px"
  page-padding-bottom: "40px"
  button-height: "52px"
  navigation-bar-height: "68px"
  min-tap-target: "48px"
brand:
  connection: "horizontal wordmark (color light / white dark)"
  navigation-home: "symbol (color light / white dark)"
  about: "horizontal wordmark"
---

# Design System: 轻影 Luma

## Overview

**Creative North Star: "安静的家庭放映室"**

轻影的界面服务于私人媒体，不把设计本身变成主角。深蓝黑播放环境降低环境光干扰，雾青色承担交互强调，低饱和金色只用于少量辅助信息。布局熟悉、紧凑而不拥挤，反馈清楚但不会盖过内容。

系统拒绝营销落地页式的大标题、霓虹紫渐变、玻璃拟态和装饰性动效。响应式变化只解决设备尺寸与方向问题，播放器状态变化使用短促淡入淡出。

**Key Characteristics:**

- 内容优先的克制层级
- 低饱和冷中性色与单一主强调色
- Material 3 的原生可预期控件
- 8px、12px、18px 的递进圆角
- 150–250ms 的状态型动效

## Colors

主色板以深蓝黑和纸白建立安静背景，以雾青色表达主操作，金色只承担稀少的次级强调。

### Primary

- **雾青主色**：用于主要操作、当前选择、焦点和播放器进度，不作为大面积装饰。

### Secondary

- **低饱和金色**：用于需要区分但不抢占主操作层级的辅助信息。

### Neutral

- **深夜墨色**：播放器和深色页面的最深背景。
- **深蓝表面**：深色主题的页面与工具栏表面。
- **雾纸白**：浅色主题背景，避免纯白刺眼。

**The One Voice Rule.** 主强调色只表达操作和状态；非交互装饰不得借用主色。

## Typography

**Display Font:** 系统无衬线字体
**Body Font:** 系统无衬线字体

**Character:** 字体保持原生、清晰和可信；层级依靠字号与字重，而不是装饰字体。

### Hierarchy

- **Headline**（600，紧凑行高）：页面主标题和重要区段。
- **Title**（600，1.25 行高）：卡片、工具栏与播放器标题。
- **Body**（400，1.45 行高）：说明、元数据和错误信息，长文限制在 65–75 个字符宽度。
- **Label**（600，紧凑行高）：按钮、筛选与状态标签。

**The Native Voice Rule.** 禁止在按钮、数据和播放器控制上使用展示字体。

## Elevation

界面默认平坦，通过相邻表面的明度差和轮廓建立层级。阴影只用于系统弹出层；播放器 HUD 使用不透明深色表面，不使用玻璃模糊。

**The Flat-by-Default Rule.** 静止表面不使用装饰阴影，只有系统浮层和交互反馈允许获得临时层级。

## Components

### Buttons

- **Shape:** 清晰柔和的中圆角（12px），主要按钮高度至少 52px。
- **Primary:** 雾青背景配高对比文字；图标和标签共同说明行为。
- **Hover / Focus:** 使用 Material 状态层和明确焦点，不改变布局尺寸。
- **Secondary / Ghost:** 保持标准 Material 3 轮廓或文字按钮语义。

### Chips

- **Style:** 低对比表面、紧凑标签和标准 Material 选中状态。
- **State:** 选中态使用主色容器，未选中态不得使用高饱和强调。

### Cards / Containers

- **Corner Style:** 中圆角（12px），媒体封面可使用大圆角（18px）。
- **Background:** 通过 surfaceContainer 层级区分主题表面。
- **Shadow Strategy:** 默认零阴影。
- **Internal Padding:** 标准为 16px，信息密集区域可使用 12px。

### Inputs / Fields

- **Style:** 填充表面、中圆角（12px）和轻轮廓。
- **Focus:** 1.5px 主色描边，不使用光晕。
- **Error / Disabled:** 通过 Material 语义色、文字和禁用状态共同表达。

### Navigation

手机使用 68px Material 3 底部导航，宽屏切换为 NavigationRail；当前项使用主色容器，其他项保持低对比。

### Player Feedback HUD

使用紧凑深色实面容器、白色图标与文字、单条进度反馈。HUD 只在手势持续期间和结束后的短暂时间出现，不遮挡关键媒体区域。

## Do's and Don'ts

### Do:

- **Do** 保持关键触控目标至少 48dp，并提供中文语义标签。
- **Do** 使用 150–250ms 淡入淡出表达显隐和状态变化。
- **Do** 让播放器内容占据视觉中心，控制层按需出现。
- **Do** 使用现有 4/8/12/16/24/32/48px 间距节奏。

### Don't:

- **Don't** 使用营销落地页式的大标题和视觉表演。
- **Don't** 使用霓虹紫渐变、玻璃拟态或高饱和色装饰播放器。
- **Don't** 使用冗长、弹跳或纯装饰动画打断观看。
- **Don't** 把关键功能做成只能猜到的手势；必须保留可见控件与语义说明。
- **Don't** 在卡片或提示上使用大于 1px 的彩色单侧边框。
