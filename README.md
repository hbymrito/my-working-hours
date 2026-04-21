# MyWorkingHours

一个面向 macOS 的刘海区工时计时器应用。

常驻菜单栏，可在刘海区域或顶部中央呼出横条计时面板，以接近 macOS 原生的磨砂 / 胶囊风格完成开始、暂停、停止计时；同时提供主界面，用来管理任务、项目、标签和工时记录，以及按日期或时间范围查看汇总。

## 功能概览

- 刘海区 / 顶部横条计时面板
- 菜单栏常驻入口 + Dock 图标常驻（关窗后可从 Dock 重新唤起）
- 并行任务工作台：可同时跑多个任务，主任务逻辑自动轮换
- 大号计时器与今日累计工时
- 今日 Tab 顶部日期选择器，可浏览任意一天的任务与记录
- 总览 Tab：今日 / 本周 / 本月 / 自定义区间四种范围；展示累计工时、墙钟时长，按任务 / 项目 / 标签三维度细分
- 任务、项目、标签、计时记录管理
- 手动补录和修正工时记录
- 本地 SwiftData 持久化

## 技术栈

- `SwiftUI`
- `AppKit`
- `SwiftData`
- `Swift Package Manager`（同时提供 `MyWorkingHours.xcodeproj`）
- 最低系统要求：`macOS 14`

## 本地运行

需要本机已安装 Xcode 和对应的 Command Line Tools。

```bash
swift run
```

开发期以 `swift run` 启动是裸二进制，Dock 图标会是系统默认样式；如需看到正式图标，走打包流程（见下方）。

## 用 Xcode 打开

仓库同时支持两种打开方式：

- 直接打开 `Package.swift`
- 直接打开 `MyWorkingHours.xcodeproj`

Xcode 工程里已经包含：

- macOS app target
- 单元测试 target
- 共享 scheme

## 运行测试

```bash
swift test
```

当前测试覆盖了这些核心逻辑：

- 开始 / 暂停 / 恢复 / 停止状态迁移
- 跨午夜累计工时计算
- 并行启动多个任务时分别持有独立的打开记录
- 暂停一个任务不影响其它任务、停止全部时只保留已关闭的记录
- 主任务在停止 / 暂停后按规则轮换
- 手动修改记录后聚合结果刷新

## 打包为可安装 `.app`

项目内置了打包脚本：

```bash
./scripts/build_app.sh
```

产出：

- `dist/MyWorkingHours.app`
- `dist/MyWorkingHours.zip`

脚本会自动完成这些步骤：

- 以 `release` 模式构建可执行文件
- 组装标准 macOS `.app` bundle
- 写入 `Info.plist`
- 嵌入 Swift 运行时依赖
- 做本地 ad-hoc 签名
- 额外生成 zip 压缩包

支持通过环境变量覆盖版本号：

```bash
MARKETING_VERSION=1.2.0 BUILD_NUMBER=3 ./scripts/build_app.sh
```

重新生成应用图标可运行：

```bash
./scripts/generate_app_icon.sh
```

## 安装方式

1. 运行 `./scripts/build_app.sh`
2. 打开 `dist/MyWorkingHours.app`
3. 拖到 `/Applications` 目录

或直接下载 [Release](https://github.com/hbymrito/my-working-hours/releases) 页里的 `MyWorkingHours.zip`，解压后拖进 `/Applications`。

如果系统提示"无法验证开发者"：

- 这是因为当前版本使用的是本地 ad-hoc 签名
- 可以在"系统设置 → 隐私与安全性"里允许打开
- 如果后续需要发给更多人安装，建议做正式开发者签名和 Apple 公证

## 项目结构

```text
.
├── Package.swift
├── MyWorkingHours.xcodeproj/
├── Packaging/
│   └── Info.plist
├── Resources/
│   ├── AppIcon.icns
│   └── AppIcon.iconset/
├── scripts/
│   ├── build_app.sh
│   ├── generate_app_icon.sh
│   └── generate_app_icon.swift
├── Sources/MyWorkingHoursApp/
│   ├── MainWindowRouter.swift
│   ├── MainWindowView.swift
│   ├── MenuBarContentView.swift
│   ├── Models.swift
│   ├── MyWorkingHoursApp.swift
│   ├── NotchOverlayController.swift
│   ├── NotchOverlayView.swift
│   ├── PersistenceStore.swift
│   ├── QuickTaskSwitcherView.swift
│   ├── TimeAggregationService.swift
│   ├── TimerEngine.swift
│   └── Utilities.swift
└── Tests/MyWorkingHoursAppTests/
    └── MyWorkingHoursAppTests.swift
```

## 当前设计说明

- 刘海屏下顶部横条会优先贴合刘海区域显示
- 无刘海屏下会回退到顶部中间区域显示
- 顶部横条当前展示：
  - 当前任务名
  - 单次计时持续时间
  - 开始 / 暂停 / 停止按钮
- 长任务名会在横条内自动滚动展示
- 主界面分三栏：侧边栏导航 / 中间内容 / 右侧详情，中间栏有最小宽度保证总览布局

## 当前限制

- 数据仅保存在本地，不包含 iCloud 同步
- 暂未提供报表导出
- 暂未接入番茄钟、自动上下班、团队协作等扩展功能

## 后续可继续完善

- 接入正式签名与公证
- 统计报表导出（CSV / 表格）
- 支持最近任务快速切换与更完整的快捷键体系
- 可视化图表（如每日趋势、项目占比饼图）
