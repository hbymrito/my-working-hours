# MyWorkingHours

一个面向 macOS 的刘海区工时计时器应用。

它常驻菜单栏，支持在刘海区域或顶部中央呼出横条计时面板，用接近 macOS 原生的磨砂和胶囊风格完成开始、暂停、停止计时；同时提供一个主界面，用来管理任务、项目、标签和工时记录。

## 功能概览

- 刘海区 / 顶部横条计时面板
- 菜单栏常驻入口
- 大号计时器与今日累计工时
- 一键开始、暂停、停止
- 任务、项目、标签、计时记录管理
- 手动补录和修正工时记录
- 本地 SwiftData 持久化
- 单一活动计时互斥，避免同时跑多个任务

## 技术栈

- `SwiftUI`
- `AppKit`
- `SwiftData`
- `Swift Package Manager`
- 最低系统要求：`macOS 14`

## 本地运行

先确保本机安装了 Xcode 以及对应的 Command Line Tools。

```bash
swift run
```

应用启动后会常驻菜单栏，不显示 Dock 图标。

## 用 Xcode 打开

仓库现在同时支持两种打开方式：

- 直接打开 `Package.swift`
- 直接打开 `MyWorkingHours.xcodeproj`

如果你更习惯用 Xcode 的原生 target、scheme、Run/Test 面板，推荐直接双击：

```text
MyWorkingHours.xcodeproj
```

当前工程里已经包含：

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
- 切换任务时只保留一条活动记录
- 手动修改记录后聚合结果刷新

## 打包为可安装 `.app`

项目已经内置了打包脚本：

```bash
./scripts/build_app.sh
```

执行完成后会生成：

- `dist/MyWorkingHours.app`
- `dist/MyWorkingHours.zip`

脚本会自动完成这些步骤：

- 以 `release` 模式构建可执行文件
- 组装标准 macOS `.app` bundle
- 写入 `Info.plist`
- 嵌入 Swift 运行时依赖
- 做本地 ad-hoc 签名
- 额外生成 zip 压缩包

如果你想重新生成应用图标，可以运行：

```bash
./scripts/generate_app_icon.sh
```

## 安装方式

本机安装最简单的方式：

1. 运行 `./scripts/build_app.sh`
2. 打开 `dist/MyWorkingHours.app`
3. 拖到 `Applications` 目录

如果系统提示“无法验证开发者”：

- 这是因为当前版本使用的是本地 ad-hoc 签名
- 你可以在“系统设置 -> 隐私与安全性”里允许打开
- 如果后续需要发给更多人安装，建议再做正式开发者签名和 Apple 公证

## 项目结构

```text
.
├── Package.swift
├── Packaging/
│   └── Info.plist
├── scripts/
│   └── build_app.sh
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

## 当前限制

- 数据仅保存在本地，不包含 iCloud 同步
- 暂未提供报表导出
- 暂未接入番茄钟、自动上下班、团队协作等扩展功能
- 目前仍然以 `Swift Package + Xcode Project` 双入口维护，后续如果继续扩展，可能需要统一一套主构建链路

## 后续可继续完善

- 增加应用图标和品牌资源
- 生成标准 Xcode 工程
- 接入正式签名和公证
- 增加统计报表与导出
- 支持最近任务快速切换和更完整的快捷键体系
